import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:test/test.dart';

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _link = {
  'code': 'aB3kP9x',
  'url': 'https://go.shop.test/l/aB3kP9x',
  'path': '/product/42',
  'data': {'ref': 'spring'},
};

Map<String, dynamic> _full(Map<String, dynamic> over) => {
  ..._link,
  'web_url': null,
  'ios_url': null,
  'android_url': null,
  'title': null,
  'description': null,
  'image_url': null,
  'expires_at': null,
  'disabled': false,
  'source': 'api',
  'created_by': null,
  'clicks': 3,
  'opens': 2,
  'installs': 1,
  'last_click_at': '2026-10-20T10:00:00.000Z',
  'created_at': '2026-10-01T00:00:00.000Z',
  'updated_at': '2026-10-01T00:00:00.000Z',
  ...over,
};

/// A fake project: the links endpoints, with [resolveStatus] for resolve
/// and [deferredMatch] for deferred (or throwing when [offline]).
class _Server {
  int resolveStatus = 200;
  int deferredStatus = 200;
  bool offline = false;
  Map<String, dynamic>? deferredMatch;
  final requests = <http.Request>[];

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (!path.contains('/links/v1/')) return _json(200, []);
    if (offline) throw http.ClientException('network is down', req.url);
    requests.add(req);
    if (path.contains('/links/v1/resolve/')) {
      if (resolveStatus == 410) {
        return _json(410, {'message': 'This link has expired', 'code': 'x'});
      }
      if (resolveStatus == 404) return _json(404, {'message': 'No such link'});
      return _json(200, _link);
    }
    if (path.endsWith('/links/v1/deferred')) {
      if (deferredStatus != 200) {
        return _json(deferredStatus, {'message': 'busy'});
      }
      return _json(200, {'match': deferredMatch});
    }
    if (path.endsWith('/links/v1/links') && req.method == 'POST') {
      return _json(201, _full(jsonDecode(req.body) as Map<String, dynamic>));
    }
    if (path.endsWith('/links/v1/links')) {
      return _json(200, {
        'links': [_full({})],
        'total': 1,
      });
    }
    if (req.method == 'DELETE') return _json(200, {'deleted': 'summer'});
    if (req.method == 'PATCH') {
      return _json(200, _full(jsonDecode(req.body) as Map<String, dynamic>));
    }
    return _json(200, {
      'link': _full({'code': 'summer'}),
      'days': 7,
      'daily': [
        {'day': '2026-10-20', 'clicks': 3, 'opens': 2, 'installs': 1},
      ],
      'platforms': [
        {'k': 'ios', 'n': 2},
        {'k': 'android', 'n': 1},
      ],
      'countries': [
        {'k': 'DE', 'n': 3},
      ],
      'outcomes': [
        {'k': 'store', 'n': 3},
      ],
      'referrers': <Object>[],
    });
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
  test('codeFrom: short link URLs and bare codes', () {
    expect(LinksClient.codeFrom('https://go.shop.test/l/aB3kP9x'), 'aB3kP9x');
    expect(LinksClient.codeFrom('https://x.test/l/a_b-9/?utm=1'), 'a_b-9');
    expect(LinksClient.codeFrom('summer'), 'summer');
    expect(LinksClient.codeFrom('  summer  '), 'summer');
    expect(LinksClient.codeFrom('https://shop.test/about'), isNull);
    expect(LinksClient.codeFrom('https://shop.test/l/a/b'), isNull);
    expect(LinksClient.codeFrom('https://shop.test/l/'), isNull);
    expect(LinksClient.codeFrom('not a code'), isNull);
    expect(LinksClient.codeFrom('x' * 65), isNull);
  });

  test('resolve sends GET /resolve/<code> with the API key and platform; '
      'other URLs return null without a request', () async {
    final server = _Server();
    final c = server.stitch();
    final link = await c.links.resolve(
      'https://go.shop.test/l/aB3kP9x',
      platform: 'ios',
    );
    expect(link!.code, 'aB3kP9x');
    expect(link.path, '/product/42');
    expect(link.data, {'ref': 'spring'});
    expect(link.matchedBy, isNull);
    final req = server.requests.single;
    expect(req.method, 'GET');
    expect(
      req.url.toString(),
      'http://localhost:9999/links/v1/resolve/aB3kP9x?platform=ios',
    );
    expect(req.headers['apikey'], 'anon-key');
    expect(req.headers['Authorization'], 'Bearer anon-key');

    expect(await c.links.resolve('https://shop.test/about'), isNull);
    expect(server.requests, hasLength(1));

    // no platform off iOS/Android (the tests run on a desktop OS)
    c.links.configure(platform: () => null);
    await c.links.resolve('summer');
    expect(
      server.requests.last.url.toString(),
      'http://localhost:9999/links/v1/resolve/summer',
    );
    c.links.configure(platform: () => 'android');
    await c.links.resolve('summer');
    expect(server.requests.last.url.queryParameters['platform'], 'android');
  });

  test('resolve: 410 and 404 throw LinksException with the status', () async {
    final server = _Server()..resolveStatus = 410;
    final c = server.stitch();
    await expectLater(
      c.links.resolve('old'),
      throwsA(
        isA<LinksException>()
            .having((e) => e.status, 'status', 410)
            .having((e) => e.message, 'message', 'This link has expired'),
      ),
    );
    server.resolveStatus = 404;
    await expectLater(
      c.links.resolve('gone'),
      throwsA(isA<LinksException>().having((e) => e.status, 'status', 404)),
    );
    server.offline = true;
    await expectLater(
      c.links.resolve('gone'),
      throwsA(isA<LinksException>().having((e) => e.status, 'status', 0)),
    );
  });

  test('deferred is asked once per install, kept in the analytics store; '
      'force asks again', () async {
    final server = _Server()
      ..deferredMatch = {..._link, 'matched_by': 'referrer'};
    final store = MemoryAnalyticsStore();
    final c = server.stitch();
    await c.analytics.start(store: store);

    final first = await c.links.deferred(
      platform: 'android',
      referrer: 'stitch_link=aB3kP9x',
    );
    expect(first!.code, 'aB3kP9x');
    expect(first.matchedBy, 'referrer');
    final req = server.requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/links/v1/deferred');
    expect(jsonDecode(req.body), {
      'platform': 'android',
      'referrer': 'stitch_link=aB3kP9x',
    });
    expect(await store.get('deferred_link_checked'), 'true');

    expect(await c.links.deferred(platform: 'android'), isNull);
    expect(server.requests, hasLength(1));

    server.deferredMatch = null;
    expect(await c.links.deferred(platform: 'ios', force: true), isNull);
    expect(server.requests, hasLength(2));
    expect(jsonDecode(server.requests.last.body), {'platform': 'ios'});
  });

  test('deferred: no match is also remembered; errors are not', () async {
    final server = _Server()..deferredStatus = 429;
    final c = server.stitch();
    c.links.configure(platform: () => 'ios');
    await expectLater(
      c.links.deferred(),
      throwsA(isA<LinksException>().having((e) => e.status, 'status', 429)),
    );
    server.offline = true;
    await expectLater(c.links.deferred(), throwsA(isA<LinksException>()));
    expect(await c.analytics.store.get('deferred_link_checked'), isNull);

    server
      ..offline = false
      ..deferredStatus = 200;
    expect(await c.links.deferred(), isNull);
    expect(await c.analytics.store.get('deferred_link_checked'), 'true');
    expect(await c.links.deferred(), isNull);
    expect(server.requests, hasLength(2));
  });

  test('deferred needs ios or android', () async {
    final server = _Server();
    final c = server.stitch();
    c.links.configure(platform: () => null);
    expect(() => c.links.deferred(), throwsArgumentError);
    expect(() => c.links.deferred(platform: 'web'), throwsArgumentError);
    expect(server.requests, isEmpty);
  });

  test('create, list, get, update and remove', () async {
    final server = _Server();
    final c = server.stitch();
    final made = await c.links.create(
      LinkInput(
        path: '/invite/7',
        data: {'from': 'ana'},
        expiresAt: DateTime.utc(2026, 12),
      ),
    );
    var req = server.requests.last;
    expect(req.method, 'POST');
    expect(req.url.path, '/links/v1/links');
    expect(req.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(req.body), {
      'path': '/invite/7',
      'data': {'from': 'ana'},
      'expires_at': '2026-12-01T00:00:00.000Z',
    });
    expect(made.path, '/invite/7');
    expect(made.expiresAt, DateTime.utc(2026, 12));
    expect(made.clicks, 3);
    expect(made.source, 'api');

    final page = await c.links.list(search: 'spring', limit: 5);
    expect(
      server.requests.last.url.toString(),
      'http://localhost:9999/links/v1/links?q=spring&limit=5',
    );
    expect(page.total, 1);
    expect(page.links.single.code, 'aB3kP9x');
    await c.links.list();
    expect(
      server.requests.last.url.toString(),
      'http://localhost:9999/links/v1/links',
    );

    final stats = await c.links.get('summer', days: 7);
    expect(
      server.requests.last.url.toString(),
      'http://localhost:9999/links/v1/links/summer?days=7',
    );
    expect(stats.link.code, 'summer');
    expect(stats.days, 7);
    expect(stats.daily.single.installs, 1);
    expect(stats.platforms, {'ios': 2, 'android': 1});
    expect(stats.countries, {'DE': 3});
    expect(stats.referrers, isEmpty);

    final changed = await c.links.update(
      'summer',
      const LinkInput(disabled: true, clear: {'title'}),
    );
    req = server.requests.last;
    expect(req.method, 'PATCH');
    expect(req.url.path, '/links/v1/links/summer');
    expect(jsonDecode(req.body), {'title': null, 'disabled': true});
    expect(changed.disabled, isTrue);

    expect(await c.links.remove('summer'), 'summer');
    expect(server.requests.last.method, 'DELETE');
    expect(server.requests.last.url.path, '/links/v1/links/summer');
  });

  test('a signed-in user is sent as the bearer token', () async {
    final server = _Server();
    final c = StitchClient(
      'http://localhost:9999',
      'anon-key',
      accessToken: () async => 'user-jwt',
      httpClient: server.client,
    );
    addTearDown(c.dispose);
    await c.links.resolve('summer');
    expect(server.requests.single.headers['Authorization'], 'Bearer user-jwt');
    expect(server.requests.single.headers['apikey'], 'anon-key');
  });
}
