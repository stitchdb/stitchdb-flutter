import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stitchdb/src/analytics.dart' show analyticsCountry, analyticsOs;
import 'package:stitchdb/stitchdb.dart';
import 'package:test/test.dart';

http.Response _json(int status, Object body, [http.BaseRequest? request]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

/// A fake project: the analytics endpoints answer [trackStatus] (or throw
/// when [offline]).
class _Server {
  int trackStatus = 200;
  bool offline = false;
  final batches = <Map<String, dynamic>>[];
  final trackRequests = <http.Request>[];
  final optOutRequests = <http.Request>[];
  final crashReports = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get events => [
    for (final b in batches) ...(b['events'] as List).cast(),
  ];

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (path.endsWith('/analytics/v1/track')) {
      if (offline) throw http.ClientException('network is down', req.url);
      trackRequests.add(req);
      if (trackStatus == 200) {
        batches.add(jsonDecode(req.body) as Map<String, dynamic>);
      }
      return _json(trackStatus, {'received': 1, 'dropped': 0});
    }
    if (path.endsWith('/analytics/v1/opt-out')) {
      optOutRequests.add(req);
      return _json(200, {'ok': true});
    }
    if (path.endsWith('/crashes/v1/report')) {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      crashReports.addAll((b['reports'] as List).cast());
      return _json(200, {'received': 1});
    }
    return _json(200, [], req);
  });

  StitchClient stitch() {
    final c = StitchClient(
      'http://localhost:9999',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: client,
    );
    addTearDown(c.dispose);
    return c;
  }
}

void main() {
  test('events tracked before start wait and are sent after it', () async {
    final server = _Server();
    final c = server.stitch();
    c.analytics.track('app_open');
    c.analytics.track('purchase', {'plan': 'pro', 'amount': 29});
    await c.analytics.flush();
    expect(server.trackRequests, isEmpty);

    await c.analytics.start(release: '1.4.0');
    await c.analytics.flush();
    expect(server.batches, hasLength(1));
    final b = server.batches.single;
    expect(b['anon_id'], c.analytics.anonymousId);
    expect(b['anon_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(b['session_id'], isA<String>());
    expect(b['release'], '1.4.0');
    expect(b['platform'], 'dart');
    expect(b['os'], isA<String>());
    final events = (b['events'] as List).cast<Map<String, dynamic>>();
    expect(events.map((e) => e['name']), ['app_open', 'purchase']);
    expect(events[1]['props'], {'plan': 'pro', 'amount': 29});
    expect(DateTime.parse(events[0]['at'] as String).isUtc, isTrue);

    final req = server.trackRequests.single;
    expect(req.headers['apikey'], 'anon-key');
    expect(req.headers['Authorization'], 'Bearer anon-key');
  });

  test('invalid event names and oversized props are dropped', () async {
    final server = _Server();
    final c = server.stitch();
    await c.analytics.start();
    c.analytics.track('');
    c.analytics.track('bad\nname');
    c.analytics.track('-starts-with-dash');
    c.analytics.track('x' * 65);
    c.analytics.track('too_big', {'blob': 'x' * 9000});
    c.analytics.track(r'$screen view: /home');
    await c.analytics.flush();
    expect(server.events.map((e) => e['name']), [r'$screen view: /home']);
  });

  test('beforeSend can change an event or return null to drop it', () async {
    final server = _Server();
    final c = server.stitch();
    await c.analytics.start(
      beforeSend: (e) => e.name == 'secret' ? null : (e..props['tagged'] = 1),
    );
    c.analytics.track('secret', {'a': 1});
    c.analytics.track('visible');
    await c.analytics.flush();
    expect(server.events, hasLength(1));
    expect(server.events.single['name'], 'visible');
    expect(server.events.single['props'], {'tagged': 1});
  });

  test('20 waiting events are sent without waiting for the timer', () async {
    final server = _Server();
    final c = server.stitch();
    await c.analytics.start(flushInterval: const Duration(hours: 1));
    for (var i = 0; i < 20; i++) {
      c.analytics.track('e$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.events, hasLength(20));
  });

  test('optOut sends POST /opt-out, drops the queue and stops tracking; '
      'remembered on the device', () async {
    final server = _Server();
    final store = MemoryAnalyticsStore();
    final c = server.stitch();
    await c.analytics.start(store: store);
    c.analytics.track('before_opt_out');
    await c.analytics.optOut();
    expect(c.analytics.isOptedOut, isTrue);
    final req = server.optOutRequests.single;
    expect(req.method, 'POST');
    expect(req.body, '{}');
    expect(req.headers['apikey'], 'anon-key');

    c.analytics.track('after_opt_out');
    await c.analytics.flush();
    expect(server.trackRequests, isEmpty);
    expect(await store.get('queue'), isNull);

    // A new run on the same device stays opted out.
    final c2 = server.stitch();
    await c2.analytics.start(store: store);
    expect(c2.analytics.isOptedOut, isTrue);
    c2.analytics.track('next_run');
    await c2.analytics.flush();
    expect(server.trackRequests, isEmpty);

    await c2.analytics.optIn();
    expect(c2.analytics.isOptedOut, isFalse);
    expect(server.optOutRequests.last.method, 'DELETE');
    c2.analytics.track('opted_in');
    await c2.analytics.flush();
    expect(server.events.map((e) => e['name']), ['opted_in']);
  });

  test('404 (analytics off) clears the queue and stops sending', () async {
    final server = _Server()..trackStatus = 404;
    final store = MemoryAnalyticsStore();
    final c = server.stitch();
    await c.analytics.start(store: store);
    c.analytics.track('one');
    await c.analytics.flush();
    expect(server.trackRequests, hasLength(1));

    c.analytics.track('two');
    await c.analytics.flush();
    expect(server.trackRequests, hasLength(1));
    expect(await store.get('queue'), isNull);
  });

  test('400 drops the batch, 429 keeps it for later', () async {
    final server = _Server()..trackStatus = 400;
    final c = server.stitch();
    await c.analytics.start();
    c.analytics.track('rejected');
    await c.analytics.flush();
    server.trackStatus = 429;
    c.analytics.track('over_quota');
    await c.analytics.flush();
    server.trackStatus = 200;
    await c.analytics.flush();
    expect(server.events.map((e) => e['name']), ['over_quota']);
  });

  test(
    'a network failure keeps the queue in the store for the next start',
    () async {
      final server = _Server()..offline = true;
      final store = MemoryAnalyticsStore();
      final c = server.stitch();
      await c.analytics.start(release: '1.4.0', store: store);
      final anon = c.analytics.anonymousId;
      c.analytics.track('offline_1');
      c.analytics.track('offline_2', {'n': 2});
      await c.analytics.flush();
      expect(server.events, isEmpty);
      final saved = jsonDecode((await store.get('queue'))!) as List;
      expect(saved.map((e) => (e as Map)['name']), ['offline_1', 'offline_2']);
      c.analytics.stop();

      // The next launch, online again.
      server.offline = false;
      final c2 = server.stitch();
      c2.analytics.track('early');
      await c2.analytics.start(release: '1.4.0', store: store);
      expect(c2.analytics.anonymousId, anon);
      await c2.analytics.flush();
      expect(server.events.map((e) => e['name']), [
        'offline_1',
        'offline_2',
        'early',
      ]);
      expect(server.batches.single['anon_id'], anon);
      expect(await store.get('queue'), isNull);
    },
  );

  test('analytics calls are not crash breadcrumbs', () async {
    final server = _Server();
    final c = server.stitch();
    await c.crashes.start(captureUnhandled: false);
    await c.analytics.start();
    c.analytics.track('purchase');
    await c.analytics.flush();
    await c.analytics.optOut();
    await c.from('orders').select();
    c.crashes.captureMessage('after analytics');
    await c.crashes.flush();
    final crumbs = jsonEncode(server.crashReports.single['breadcrumbs']);
    expect(crumbs, contains('/rest/v1/orders'));
    expect(crumbs, isNot(contains('/analytics/v1/')));
  });

  test('a CrashStore can be used as the analytics store', () async {
    final server = _Server()..offline = true;
    final store = MemoryCrashStore();
    final c = server.stitch();
    await c.analytics.start(store: store);
    c.analytics.track('kept');
    await c.analytics.flush();
    expect(await store.get('queue'), contains('kept'));
    expect(await store.get('anon'), c.analytics.anonymousId);
  });

  test('country is the region of the locale', () {
    expect(analyticsCountry('de_DE'), 'DE');
    expect(analyticsCountry('en-us'), 'US');
    expect(analyticsCountry('pt_BR.UTF-8'), 'BR');
    expect(analyticsCountry('zh-Hant-TW'), 'TW');
    expect(analyticsCountry('C'), isNull);
    expect(analyticsCountry(null), isNull);
    expect(analyticsOs('android'), 'Android');
    expect(analyticsOs(null), 'Web');
  });
}
