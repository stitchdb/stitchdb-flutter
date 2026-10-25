import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:test/test.dart';

void main() {
  test(
    'offline: writes queue while the server is down and survive a restart of the app',
    () async {
      var up = false;
      final pushed = <Map<String, dynamic>>[];
      final requests = <http.Request>[];
      http.Response json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
      final mock = MockClient((req) async {
        requests.add(req);
        if (!up) return json(503, {'message': 'down'});
        final path = req.url.path;
        if (path.endsWith('/sync/v1/tables')) {
          return json(200, {
            'tables': [
              {
                'name': 'todos',
                'pk': ['id'],
                'conflict': 'last_write_wins',
              },
            ],
          });
        }
        if (path.endsWith('/sync/v1/push')) {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final mutations = (b['mutations'] as List)
              .cast<Map<String, dynamic>>();
          pushed.addAll(mutations);
          return json(200, {
            'results': [
              for (final m in mutations)
                {
                  'id': m['id'],
                  'status': 'applied',
                  'seq': 7,
                  'pk': {'id': m['row']['id']},
                  'row': m['row'],
                },
            ],
          });
        }
        if (path.endsWith('/sync/v1/pull')) {
          return json(200, {
            'changes': {
              'todos': [
                {
                  'seq': 8,
                  'op': 'u',
                  'pk': {'id': 'b'},
                  'row': {'id': 'b', 'title': 'from server'},
                },
              ],
            },
            'cursors': {'todos': 8},
            'more': false,
            'reset': [],
          });
        }
        return json(404, {'message': 'not found'});
      });

      final store = MemoryOfflineStore();
      final c = StitchClient(
        'http://localhost:9999',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: mock,
      );
      addTearDown(c.dispose);

      up = true;
      var off = c.offline(store: store, interval: Duration.zero);
      await off.ready;
      await off.sync().catchError((Object _) {});
      up = false;
      await off.table('todos').upsert({'id': 'a', 'title': 'offline'});
      expect(off.status.pending, 1);
      await off.close();

      off = c.offline(store: store, interval: Duration.zero);
      await off.ready;
      expect(off.status.pending, 1, reason: 'queue persisted');
      expect(off.table('todos').get('a')!['title'], 'offline');

      up = true;
      await off.sync();
      expect(off.status.pending, 0);
      expect(off.status.online, isTrue);
      expect(off.status.error, isNull);
      expect(
        pushed.map((m) => [m['table'], m['op'], m['row']['title'], m['base']]),
        [
          ['todos', 'upsert', 'offline', null],
        ],
      );
      expect(pushed[0].keys.toSet(), {
        'id',
        'table',
        'op',
        'row',
        'base',
        'at',
      });
      expect(pushed[0]['id'], matches(RegExp(r'^[A-Za-z0-9_-]{16}\.\d+$')));
      expect(DateTime.tryParse(pushed[0]['at'] as String), isNotNull);
      expect(off.table('todos').get('b')!['title'], 'from server');
      expect(off.table('todos').get('a')!['title'], 'offline');

      final push = requests.lastWhere((r) => r.url.path.endsWith('/push'));
      expect(push.url.toString(), 'http://localhost:9999/sync/v1/push');
      expect(push.headers['apikey'], 'anon-key');
      expect(push.headers['Authorization'], 'Bearer anon-key');

      await off.close(clear: true);
      expect(await store.entries(''), isEmpty);
    },
  );

  test('offline: a conflict takes the server row and emits an event', () async {
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/tables')) {
        return http.Response(
          jsonEncode({
            'tables': [
              {
                'name': 'todos',
                'pk': ['id'],
              },
            ],
          }),
          200,
        );
      }
      if (path.endsWith('/push')) {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'results': [
              for (final m in b['mutations'] as List)
                {
                  'id': m['id'],
                  'status': 'conflict',
                  'seq': 3,
                  'row': {'id': 'a', 'title': 'server'},
                },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'changes': {}, 'cursors': {}, 'more': false}),
        200,
      );
    });
    final c = StitchClient(
      'http://localhost:9999',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: mock,
    );
    addTearDown(c.dispose);
    final off = c.offline(interval: Duration.zero);
    await off.ready;
    await off.sync();
    final conflict = off.conflicts.first;
    await off.table('todos').upsert({'id': 'a', 'title': 'mine'});
    await off.sync();
    final e = await conflict;
    expect(e.status, 'conflict');
    expect(e.pk, {'id': 'a'});
    expect(e.local, {'id': 'a', 'title': 'mine'});
    expect(off.table('todos').get('a')!['title'], 'server');
    expect(off.status.pending, 0);
    await off.close();
  });
}
