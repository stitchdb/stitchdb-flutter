import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart';

// Offline-first sync (`stitchdb.offline()`): a local copy of the rows the
// signed-in user may see in the tables that sync (Studio › Database › Offline
// sync). Reads come from the local copy, writes apply locally at once and are
// queued; the queue is pushed and changes are pulled whenever the device is
// online.

/// Where the local copy lives: `get/set/delete/entries` over string keys.
/// Values are JSON-serialisable.
abstract class OfflineStore {
  /// The value under [key], or `null` when there is none.
  Future<dynamic> get(String key);

  /// Stores [value] under [key].
  Future<void> set(String key, dynamic value);

  /// Removes [key].
  Future<void> delete(String key);

  /// Every entry whose key starts with [prefix].
  Future<List<MapEntry<String, dynamic>>> entries(String prefix);

  /// Removes every entry.
  Future<void> clear();
}

/// An [OfflineStore] that keeps everything in memory (lost when the app
/// exits). Values are stored as JSON, so every read returns a fresh copy.
class MemoryOfflineStore implements OfflineStore {
  final _m = <String, String>{};

  @override
  Future<dynamic> get(String key) async {
    final v = _m[key];
    return v == null ? null : jsonDecode(v);
  }

  @override
  Future<void> set(String key, dynamic value) async {
    _m[key] = jsonEncode(value);
  }

  @override
  Future<void> delete(String key) async {
    _m.remove(key);
  }

  @override
  Future<List<MapEntry<String, dynamic>>> entries(String prefix) async => [
    for (final e in _m.entries)
      if (e.key.startsWith(prefix)) MapEntry(e.key, jsonDecode(e.value)),
  ];

  @override
  Future<void> clear() async {
    _m.clear();
  }
}

/// Thrown when the sync server refuses a request or a key is invalid.
class OfflineException implements Exception {
  final String message;
  final int status;

  const OfflineException(this.message, this.status);

  @override
  String toString() => 'OfflineException($status): $message';
}

/// The state of an [OfflineClient].
class SyncStatus {
  final bool online;
  final bool syncing;

  /// Writes waiting to be pushed.
  final int pending;

  /// ISO 8601 time of the last sync that finished.
  final String? lastSyncAt;
  final String? error;

  const SyncStatus({
    this.online = true,
    this.syncing = false,
    this.pending = 0,
    this.lastSyncAt,
    this.error,
  });

  SyncStatus _copy({
    bool? online,
    bool? syncing,
    int? pending,
    String? lastSyncAt,
    Object? error = _keep,
  }) => SyncStatus(
    online: online ?? this.online,
    syncing: syncing ?? this.syncing,
    pending: pending ?? this.pending,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    error: identical(error, _keep) ? this.error : error as String?,
  );

  static const _keep = Object();

  @override
  String toString() =>
      'SyncStatus(online: $online, syncing: $syncing, pending: $pending, lastSyncAt: $lastSyncAt, error: $error)';
}

/// Your write lost (`conflict`) or was refused (`rejected`); the local copy
/// now holds [server].
class ConflictEvent {
  final String table;
  final Map<String, dynamic> pk;
  final Map<String, dynamic>? local;
  final Map<String, dynamic>? server;

  /// `conflict` or `rejected`.
  final String status;
  final String? message;

  const ConflictEvent({
    required this.table,
    required this.pk,
    required this.local,
    required this.server,
    required this.status,
    this.message,
  });

  @override
  String toString() =>
      'ConflictEvent(table: $table, pk: $pk, status: $status, message: $message)';
}

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

String _rid([int n = 16]) {
  final r = Random.secure();
  return String.fromCharCodes(
    List.generate(n, (_) => _alphabet.codeUnitAt(r.nextInt(64))),
  );
}

String _now() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

String _qKey(int n) => 'q/${n.toString().padLeft(12, '0')}';

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

class _Entry {
  final Map<String, dynamic> row;
  final int seq;

  _Entry(this.row, this.seq);

  Map<String, dynamic> toJson() => {'row': row, 'seq': seq};

  static _Entry from(dynamic v) =>
      _Entry(_map(v['row']) ?? {}, (v['seq'] as num?)?.toInt() ?? 0);
}

/// One synced table of an [OfflineClient].
class OfflineTable {
  final OfflineClient _c;
  final String name;

  OfflineTable._(this._c, this.name);

  /// Every local row.
  List<Map<String, dynamic>> all() =>
      _c._rows(name).values.map((e) => e.row).toList();

  /// One row by primary key (a map, or the value for a one-column key).
  Map<String, dynamic>? get(Object pk) =>
      _c._rows(name)[_c._key(name, pk)]?.row;

  /// Local rows that match.
  List<Map<String, dynamic>> where(
    bool Function(Map<String, dynamic> row) test,
  ) => all().where(test).toList();

  /// Insert or update a row locally and queue it for the server. The row must
  /// include its primary key.
  Future<void> upsert(Map<String, dynamic> row) =>
      _c._write(name, 'upsert', row);

  /// Delete a row locally and on the server.
  Future<void> delete(Object pk) => _c._write(name, 'delete', pk);

  /// The table's rows after every local or synced change.
  Stream<List<Map<String, dynamic>>> stream() =>
      _c.changes.where((t) => t == name).map((_) => all());

  /// Calls [fn] with the table's rows after every local or synced change.
  /// Returns a function that stops it.
  void Function() subscribe(void Function(List<Map<String, dynamic>> rows) fn) {
    final sub = stream().listen(fn);
    return () => unawaited(sub.cancel());
  }
}

/// Offline-first sync client. Create it with `StitchClient.offline()`.
class OfflineClient {
  /// Completes once the local copy is loaded.
  late final Future<void> ready;

  final String _url;
  final Client _http;
  final Map<String, String> Function() _headers;
  final List<String>? _tables;
  final OfflineStore _store;
  final Duration _interval;
  final int _batch;

  String _client = '';
  Map<String, dynamic> _cursors = {};
  int _next = 1;
  Map<String, List<String>> _pk = {};
  final _data = <String, Map<String, _Entry>>{};
  List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  Future<void>? _running;
  bool _closed = false;

  final _changes = StreamController<String>.broadcast();
  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  final _conflicts = StreamController<ConflictEvent>.broadcast();

  SyncStatus _status = const SyncStatus();

  /// The current state.
  SyncStatus get status => _status;

  /// The name of a table after every local or synced change in it.
  Stream<String> get changes => _changes.stream;

  /// Every new [status].
  Stream<SyncStatus> get statusChanges => _statusCtrl.stream;

  /// Writes that lost against the server or were refused.
  Stream<ConflictEvent> get conflicts => _conflicts.stream;

  /// Use `StitchClient.offline()`.
  OfflineClient(
    this._url,
    this._http,
    this._headers, {
    List<String>? tables,
    OfflineStore? store,
    Duration interval = const Duration(seconds: 30),
    int batch = 500,
  }) : _tables = tables,
       _store = store ?? MemoryOfflineStore(),
       _interval = interval,
       _batch = batch {
    ready = _open();
    ready.ignore();
  }

  Future<dynamic> _req(String path, [Object? body]) async {
    final uri = Uri.parse(_url + path);
    final headers = {..._headers()};
    final Response res;
    if (body == null) {
      res = await _http.get(uri, headers: headers);
    } else {
      headers['Content-Type'] = 'application/json';
      res = await _http.post(uri, headers: headers, body: jsonEncode(body));
    }
    dynamic json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      json = <String, dynamic>{};
    }
    if (res.statusCode < 200 || res.statusCode > 299) {
      final message = json is Map ? json['message'] : null;
      throw OfflineException(
        message is String ? message : 'Sync failed (${res.statusCode})',
        res.statusCode,
      );
    }
    return json;
  }

  Map<String, dynamic> get _meta => {
    'client': _client,
    'cursors': _cursors,
    'next': _next,
  };

  Future<void> _open() async {
    final m = await _store.get('m');
    if (m is Map) {
      _client = (m['client'] as String?) ?? '';
      _cursors = _map(m['cursors']) ?? {};
      _next = (m['next'] as num?)?.toInt() ?? 1;
    }
    if (_client.isEmpty) {
      _client = _rid();
      await _store.set('m', _meta);
    }
    final pk = await _store.get('pk');
    _pk = pk is Map
        ? {
            for (final e in pk.entries)
              e.key as String: List<String>.from(e.value as List),
          }
        : {};
    final re = RegExp(r'^r/([^/]+)/(.*)$', dotAll: true);
    for (final e in await _store.entries('r/')) {
      final match = re.firstMatch(e.key);
      if (match != null) _rows(match[1]!)[match[2]!] = _Entry.from(e.value);
    }
    _queue =
        (await _store.entries(
            'q/',
          )).map((e) => Map<String, dynamic>.from(e.value as Map)).toList()
          ..sort((a, b) => (a['_n'] as num).compareTo(b['_n'] as num));
    _status = _status._copy(pending: _queue.length);
    try {
      await _loadTables();
    } catch (e) {
      if (_pk.isEmpty) _setStatus(online: false, error: _msg(e));
    }
    if (_interval > Duration.zero) {
      _timer = Timer.periodic(_interval, (_) {
        if (_status.online) _bg();
      });
    }
    _bg();
  }

  void _bg() => unawaited(sync().catchError((Object _) {}));

  Future<void> _loadTables() async {
    final res = await _req('/tables');
    final want = _tables;
    final pk = <String, List<String>>{};
    for (final t in (res['tables'] as List?) ?? const []) {
      final name = t['name'] as String;
      if (want == null || want.contains(name)) {
        pk[name] = List<String>.from(t['pk'] as List);
      }
    }
    for (final name in want ?? const <String>[]) {
      if (pk[name] == null) {
        throw OfflineException(
          '$name does not sync. Turn it on in Studio › Database › Offline sync.',
          404,
        );
      }
    }
    _pk = pk;
    await _store.set('pk', pk);
  }

  Map<String, _Entry> _rows(String table) => _data.putIfAbsent(table, () => {});

  String _key(String table, Object? v) {
    final cols = _pk[table];
    if (cols == null) {
      throw OfflineException('$table is not synced offline', 404);
    }
    final o = v is Map ? v : {cols[0]: v};
    final values = [];
    for (final c in cols) {
      if (o[c] == null) {
        throw OfflineException(
          '$table: the primary key column $c is missing',
          400,
        );
      }
      values.add(o[c]);
    }
    return jsonEncode(values);
  }

  Map<String, dynamic> _pkObj(String table, Object? v) {
    final cols = _pk[table]!;
    final o = v is Map ? v : {cols[0]: v};
    return {for (final c in cols) c: o[c]};
  }

  /// One synced table.
  OfflineTable table(String name) => OfflineTable._(this, name);

  Future<void> _write(String table, String op, Object v) async {
    await ready;
    final key = _key(table, v);
    final rows = _rows(table);
    final cur = rows[key];
    final id = '$_client.${_next++}';
    final m = <String, dynamic>{
      'id': id,
      '_n': _next,
      'table': table,
      'op': op,
      'base': cur?.seq,
      'at': _now(),
      if (op == 'upsert')
        'row': {...?cur?.row, ...(v as Map<String, dynamic>)}
      else
        'pk': _pkObj(table, v),
    };
    if (op == 'upsert') {
      final e = _Entry(m['row'] as Map<String, dynamic>, cur?.seq ?? 0);
      rows[key] = e;
      await _store.set('r/$table/$key', e.toJson());
    } else {
      rows.remove(key);
      await _store.delete('r/$table/$key');
    }
    _queue.add(m);
    await _store.set(_qKey(m['_n'] as int), m);
    await _store.set('m', _meta);
    _setStatus(pending: _queue.length);
    _emitChange(table);
    if (_status.online) _bg();
  }

  /// Push queued writes, then pull until up to date. Completes when done;
  /// throws if the server can't be reached.
  Future<void> sync() {
    if (_closed) return Future.value();
    final running = _running;
    if (running != null) {
      return running.then((_) => _queue.isNotEmpty ? sync() : null);
    }
    final f = _run().whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<void> _run() async {
    try {
      await ready;
    } catch (_) {}
    _setStatus(syncing: true);
    try {
      if (_pk.isEmpty) await _loadTables();
      await _pushAll();
      await _pullAll();
      _setStatus(online: true, syncing: false, error: null, lastSyncAt: _now());
    } catch (e) {
      _setStatus(
        syncing: false,
        online:
            e is! ClientException && !(e is OfflineException && e.status == 0),
        error: _msg(e),
      );
      rethrow;
    }
  }

  Object? _target(Map<String, dynamic> m) => m['row'] ?? m['pk'];

  Future<void> _pushAll() async {
    while (_queue.isNotEmpty) {
      final batch = _queue.take(200).toList();
      final res = await _req('/push', {
        'client': _client,
        'mutations': [
          for (final m in batch) {...m}..remove('_n'),
        ],
      });
      final results = (res['results'] as List?) ?? const [];
      for (var i = 0; i < results.length; i++) {
        final r = results[i] as Map;
        final m = batch[i];
        final table = m['table'] as String;
        final key = _key(table, _target(m));
        bool same(Map<String, dynamic> q) =>
            !identical(q, m) &&
            q['table'] == table &&
            _key(table, _target(q)) == key;
        final later = _queue.any(same);
        final status = r['status'];
        if (status == 'conflict' || status == 'rejected') {
          _emit(
            _conflicts,
            ConflictEvent(
              table: table,
              pk: _map(r['pk']) ?? _pkObj(table, _target(m)),
              local: _map(m['row']),
              server: _map(r['row']),
              status: status as String,
              message: r['message'] as String?,
            ),
          );
        }
        final seq = (r['seq'] as num?)?.toInt();
        if (!later) {
          final row = _map(r['row']);
          await _put(table, key, row != null ? _Entry(row, seq ?? 0) : null);
        } else if (seq != null && seq != 0) {
          for (final q in _queue) {
            if (same(q)) q['base'] = seq;
          }
        }
        _queue.remove(m);
        await _store.delete(_qKey((m['_n'] as num).toInt()));
        _emitChange(table);
      }
      _setStatus(pending: _queue.length);
    }
  }

  Future<void> _put(String table, String key, _Entry? v) async {
    final rows = _rows(table);
    if (v != null) {
      rows[key] = v;
      await _store.set('r/$table/$key', v.toJson());
    } else {
      rows.remove(key);
      await _store.delete('r/$table/$key');
    }
  }

  Future<void> _pullAll() async {
    for (var more = true; more;) {
      final tables = {for (final t in _pk.keys) t: _cursors[t] ?? 0};
      final r = await _req('/pull', {'tables': tables, 'limit': _batch});
      final reset = List<String>.from((r['reset'] as List?) ?? const []);
      for (final t in reset) {
        for (final k in _rows(t).keys.toList()) {
          await _put(t, k, null);
        }
        _cursors[t] = 0;
      }
      final changes = (r['changes'] as Map?) ?? const {};
      for (final e in changes.entries) {
        final t = e.key as String;
        final list = e.value as List;
        final pending = {
          for (final q in _queue)
            if (q['table'] == t) _key(t, _target(q)),
        };
        for (final ch in list) {
          final key = _key(t, ch['pk']);
          // The local write wins until it is pushed.
          if (pending.contains(key)) continue;
          await _put(
            t,
            key,
            ch['op'] == 'u'
                ? _Entry(_map(ch['row']) ?? {}, (ch['seq'] as num).toInt())
                : null,
          );
        }
        if (list.isNotEmpty || reset.contains(t)) _emitChange(t);
      }
      _cursors.addAll(_map(r['cursors']) ?? {});
      await _store.set('m', _meta);
      more = r['more'] == true;
    }
  }

  String _msg(Object e) => switch (e) {
    OfflineException(:final message) => message,
    ClientException(:final message) => message,
    _ => e.toString(),
  };

  void _emit<T>(StreamController<T> c, T v) {
    if (!c.isClosed) c.add(v);
  }

  void _emitChange(String table) => _emit(_changes, table);

  void _setStatus({
    bool? online,
    bool? syncing,
    int? pending,
    String? lastSyncAt,
    Object? error = SyncStatus._keep,
  }) {
    _status = _status._copy(
      online: online,
      syncing: syncing,
      pending: pending,
      lastSyncAt: lastSyncAt,
      error: error,
    );
    _emit(_statusCtrl, _status);
  }

  /// Stop syncing. With `clear: true` also delete the local copy and the
  /// queued writes (e.g. on sign-out).
  Future<void> close({bool clear = false}) async {
    _closed = true;
    _timer?.cancel();
    try {
      await _running;
    } catch (_) {}
    if (clear) await _store.clear();
    await Future.wait([
      _changes.close(),
      _statusCtrl.close(),
      _conflicts.close(),
    ]);
  }
}
