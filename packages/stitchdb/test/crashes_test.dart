import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:stitchdb/src/version.dart';
import 'package:test/test.dart';

http.Response _json(int status, Object body, [http.BaseRequest? request]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

/// A fake project: REST answers 500 with an error code, the crash endpoints
/// answer [reportStatus] (or throw when [offline]).
class _Server {
  int reportStatus = 200;
  bool offline = false;
  final reports = <Map<String, dynamic>>[];
  final reportRequests = <http.Request>[];
  final sessions = <Map<String, dynamic>>[];

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (path.endsWith('/crashes/v1/report')) {
      if (offline) throw http.ClientException('network is down', req.url);
      reportRequests.add(req);
      if (reportStatus == 200) {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        reports.addAll((b['reports'] as List).cast<Map<String, dynamic>>());
      }
      return _json(reportStatus, {'received': 1, 'stored': 1});
    }
    if (path.endsWith('/crashes/v1/session')) {
      if (offline) throw http.ClientException('network is down', req.url);
      sessions.add(jsonDecode(req.body) as Map<String, dynamic>);
      return _json(200, {'ok': true});
    }
    if (path.endsWith('/rest/v1/orders')) {
      return _json(500, {'code': 'XX000', 'message': 'boom'}, req);
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
  test(
    'a report is sent with the breadcrumbs of a failed API call, without query values',
    () async {
      final server = _Server();
      final c = server.stitch();
      await c.crashes.start(release: '1.4.0');
      c.crashes.addBreadcrumb(type: 'ui', message: 'tapped Checkout');
      try {
        await c.from('orders').select().eq('id', 5);
        fail('the request should fail');
      } catch (e, s) {
        c.crashes.captureException(
          e,
          stackTrace: s,
          context: {'step': 'payment'},
        );
      }
      await c.crashes.flush();

      expect(server.reports, hasLength(1));
      final r = server.reports.single;
      expect(r['platform'], 'dart');
      expect(r['release'], '1.4.0');
      expect(r['environment'], 'production');
      expect(r['handled'], true);
      expect(r['install_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(r['context'], {'step': 'payment'});
      expect((r['exception'] as Map)['type'], 'PostgrestException');
      expect((r['exception'] as Map)['stack'], contains('crashes_test.dart'));
      expect((r['device'] as Map)['sdk'], 'stitchdb-dart/$version');
      expect((r['device'] as Map)['os'], isNotNull);

      final crumbs = (r['breadcrumbs'] as List).cast<Map<String, dynamic>>();
      expect(crumbs.first['message'], 'tapped Checkout');
      final api = crumbs.where((b) => b['type'] == 'api').toList();
      expect(api, hasLength(1));
      expect(api.single['message'], 'GET /rest/v1/orders?select&id 500');
      expect(api.single['level'], 'error');
      final data = api.single['data'] as Map<String, dynamic>;
      expect(data['method'], 'GET');
      expect(data['url'], '/rest/v1/orders?select&id');
      expect(data['status'], 500);
      expect(data['error_code'], 'XX000');
      expect(data['ms'], isA<int>());
      // No query values, no host, no calls to the crash endpoints.
      final body = jsonEncode(crumbs);
      expect(body, isNot(contains('eq.5')));
      expect(body, isNot(contains('localhost')));
      expect(body, isNot(contains('/crashes/v1/')));

      final req = server.reportRequests.single;
      expect(req.headers['apikey'], 'anon-key');
      expect(req.headers['Authorization'], 'Bearer anon-key');
    },
  );

  test('nothing is recorded or sent before start', () async {
    final server = _Server();
    final c = server.stitch();
    c.crashes.addBreadcrumb(type: 'ui', message: 'before');
    c.crashes.captureException(StateError('before'));
    await c.from('orders').select().then((_) {}, onError: (_) {});
    await c.crashes.flush();
    expect(server.reportRequests, isEmpty);
    expect(server.sessions, isEmpty);

    await c.crashes.start(release: '1.4.0');
    c.crashes.captureMessage('should never happen');
    await c.crashes.flush();
    expect(server.reports, hasLength(1));
    expect(server.reports.single['breadcrumbs'], isEmpty);
    expect((server.reports.single['exception'] as Map)['type'], 'Message');
  });

  test('beforeSend returning null drops the report', () async {
    final server = _Server();
    final c = server.stitch();
    final seen = <CrashReport>[];
    await c.crashes.start(
      release: '1.4.0',
      beforeSend: (r) {
        seen.add(r);
        return r.context['consent'] == true ? r : null;
      },
    );
    c.crashes.captureException(StateError('no consent'));
    await c.crashes.flush();
    expect(seen, hasLength(1));
    expect(server.reportRequests, isEmpty);

    c.crashes.captureException(
      StateError('with consent'),
      context: {'consent': true},
    );
    await c.crashes.flush();
    expect(server.reports, hasLength(1));
    expect(
      (server.reports.single['exception'] as Map)['message'],
      contains('with consent'),
    );
  });

  test(
    '404: crash reporting is off, the queue is cleared and sending stops',
    () async {
      final server = _Server()..reportStatus = 404;
      final store = MemoryCrashStore();
      final c = server.stitch();
      await c.crashes.start(release: '1.4.0', store: store);
      c.crashes.captureException(StateError('one'));
      await c.crashes.flush();
      expect(server.reportRequests, hasLength(1));
      expect(await store.get('queue'), isNull);

      c.crashes.captureException(StateError('two'));
      await c.crashes.flush();
      expect(server.reportRequests, hasLength(1));
    },
  );

  test(
    'a network failure keeps the report in the store; it is sent on the next start',
    () async {
      final store = MemoryCrashStore();
      final first = _Server()..offline = true;
      final c1 = first.stitch();
      await c1.crashes.start(release: '1.4.0', store: store);
      c1.crashes.captureException(StateError('offline'));
      await c1.crashes.flush();
      await pumpEventQueue();
      expect(first.reports, isEmpty);
      final kept = jsonDecode((await store.get('queue'))!) as List;
      expect(kept, hasLength(1));
      final installId = await store.get('install');
      c1.crashes.stop();

      // The next launch of the app.
      final second = _Server();
      final c2 = second.stitch();
      await c2.crashes.start(release: '1.4.0', store: store);
      await c2.crashes.flush();
      expect(second.reports, hasLength(1));
      expect(second.reports.single['install_id'], installId);
      expect(
        (second.reports.single['exception'] as Map)['message'],
        contains('offline'),
      );
      expect(await store.get('queue'), isNull);
    },
  );

  test('the daily session is sent once per day and release', () async {
    final server = _Server();
    final store = MemoryCrashStore();
    final c1 = server.stitch();
    await c1.crashes.start(release: '1.4.0', store: store);
    await pumpEventQueue();
    expect(server.sessions, hasLength(1));
    expect(server.sessions.single['release'], '1.4.0');
    expect(server.sessions.single['environment'], 'production');
    expect(server.sessions.single['install_id'], await store.get('install'));
    c1.crashes.stop();

    final c2 = server.stitch();
    await c2.crashes.start(release: '1.4.0', store: store);
    await pumpEventQueue();
    expect(server.sessions, hasLength(1));
    c2.crashes.stop();

    final c3 = server.stitch();
    await c3.crashes.start(release: '1.5.0', store: store);
    await pumpEventQueue();
    expect(server.sessions, hasLength(2));
  });

  test('runGuarded reports uncaught errors as unhandled', () async {
    final server = _Server();
    final c = server.stitch();
    await c.crashes.start(release: '1.4.0');
    final handed = Completer<Object>();
    c.crashes.runGuarded(() {
      scheduleMicrotask(() => throw StateError('async crash'));
    }, onError: (e, s) => handed.complete(e));
    expect(await handed.future, isA<StateError>());
    await c.crashes.flush();
    expect(server.reports, hasLength(1));
    final r = server.reports.single;
    expect(r['handled'], false);
    expect((r['exception'] as Map)['mechanism'], 'runZonedGuarded');
    expect((r['exception'] as Map)['type'], 'StateError');
  });

  test(
    'FileCrashStore keeps values across instances, also when written synchronously',
    () async {
      final dir = await Directory.systemTemp.createTemp('stitchdb-crashes');
      addTearDown(() => dir.delete(recursive: true));
      final a = FileCrashStore('${dir.path}/store');
      a.setNow('queue', '[1]');
      await a.set('install', 'abc');
      final b = FileCrashStore('${dir.path}/store');
      expect(await b.get('queue'), '[1]');
      expect(await b.get('install'), 'abc');
      await b.set('queue', null);
      expect(await a.get('queue'), isNull);
    },
  );
}
