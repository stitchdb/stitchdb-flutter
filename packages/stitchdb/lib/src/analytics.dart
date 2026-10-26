import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

import 'crash_store.dart';
import 'crashes.dart' show crashUuid;

// Product analytics (`stitchdb.analytics`): the events your app tracks, linked
// to the signed-in user (an anonymous id before sign-in, merged into the user
// when they sign in), for active users, funnels, retention and breakdowns in
// Studio › Analytics.
//
// Nothing is sent before `start()`, and nothing is stored unless the project
// has analytics turned on (Studio › Analytics). Events that cannot be sent
// (offline, the app closing) stay in the [AnalyticsStore] and are sent later.

const _maxQueue = 1000;
const _maxEarly = 100;
const _batchSize = 100;
const _flushAt = 20;
const _maxProps = 8 * 1024;
final _nameRe = RegExp(r'^[$A-Za-z0-9_][\w$.:\- /]{0,63}$');
final _log = Logger('stitchdb.analytics');

/// Where analytics keeps the events waiting to be sent, the anonymous id and
/// the opt-out. Values are strings (JSON).
///
/// Every [CrashStore] is also an [AnalyticsStore].
abstract class AnalyticsStore {
  /// The value under [key], or `null` when there is none.
  Future<String?> get(String key);

  /// Stores [value] under [key]; `null` removes it.
  Future<void> set(String key, String? value);
}

/// An [AnalyticsStore] that keeps everything in memory: waiting events, the
/// anonymous id and the opt-out are lost when the process exits. Use
/// [FileAnalyticsStore] (dart:io) or, in Flutter apps,
/// `SharedPreferencesAnalyticsStore` to keep them.
class MemoryAnalyticsStore implements AnalyticsStore {
  final _m = <String, String>{};

  @override
  Future<String?> get(String key) async => _m[key];

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}

/// One tracked event, as it is sent. Change it in `beforeSend`.
class AnalyticsEvent {
  /// Letters, digits and `_ $ . : - /` and spaces, up to 64 characters.
  String name;

  /// A JSON object of at most 8 KB; flat values are easiest to break down by.
  Map<String, dynamic> props;

  /// ISO 8601 time; set when the event is tracked.
  String at;

  AnalyticsEvent({required this.name, Map<String, dynamic>? props, String? at})
    : props = props ?? {},
      at = at ?? _now();

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
    name: '${json['name']}',
    props: json['props'] is Map
        ? (json['props'] as Map).cast<String, dynamic>()
        : null,
    at: json['at'] is String ? json['at'] as String : null,
  );

  Map<String, dynamic> toJson() => {'name': name, 'props': props, 'at': at};

  @override
  String toString() => 'AnalyticsEvent(${jsonEncode(toJson())})';
}

/// Change an event or return `null` to not send it.
typedef AnalyticsBeforeSend = AnalyticsEvent? Function(AnalyticsEvent event);

/// Installs a listener (for example for the app going to the background) and
/// returns a function that removes it. Used by platform integrations such as
/// `stitchdb_flutter`.
typedef AnalyticsHook = void Function() Function(AnalyticsClient analytics);

/// Product analytics for one [StitchClient] (`stitchdb.analytics`).
///
/// ```dart
/// await stitchdb.analytics.start(release: '1.4.0');
/// stitchdb.analytics.track('purchase', {'plan': 'pro', 'amount': 29});
/// await stitchdb.analytics.optOut(); // the user does not want to be tracked
/// ```
class AnalyticsClient {
  final String _url;
  final Client _http;
  final Map<String, String> Function() _headers;
  final void Function() Function(void Function() onChange)? _onAuthChange;

  String _platform = 'dart';
  String? Function() _os = _dartOs;
  String? Function() _country = _dartCountry;
  AnalyticsStore _defaultStore = MemoryAnalyticsStore();
  AnalyticsStore? _store;
  AnalyticsHook? _backgroundHook;

  String? _release;
  AnalyticsBeforeSend? _beforeSend;

  bool _started = false;
  bool _loaded = false;
  bool _disabled = false;
  bool _optedOut = false;
  bool _saveScheduled = false;
  Future<void>? _ready;
  Future<void>? _sending;
  Future<void> _writes = Future.value();
  String _anonId = crashUuid();
  final String _sessionId = crashUuid();
  final _queue = <AnalyticsEvent>[];
  final _off = <void Function()>[];

  @internal
  AnalyticsClient(this._url, this._http, this._headers, [this._onAuthChange]);

  /// For platform integrations such as `stitchdb_flutter`: the platform name
  /// sent with events, the default [store], the OS and country of the device
  /// and the [background] hook that is installed on [start] (to flush when
  /// the app goes to the background).
  void configure({
    String? platform,
    AnalyticsStore? store,
    String? Function()? os,
    String? Function()? country,
    AnalyticsHook? background,
  }) {
    if (platform != null) _platform = platform;
    if (store != null) _defaultStore = store;
    if (os != null) _os = os;
    if (country != null) _country = country;
    if (background != null) _backgroundHook = background;
  }

  AnalyticsStore get _st => _store ?? _defaultStore;

  /// The store in use: the one passed to [start], else the default one.
  /// Also keeps whether the deferred deep link was checked (`client.links`).
  @internal
  AnalyticsStore get store => _st;

  /// Whether [start] was called (and not [stop]).
  bool get isStarted => _started;

  /// Whether the user opted out on this device (see [optOut]). Read from the
  /// store on [start].
  bool get isOptedOut => _optedOut;

  /// The id of this device before sign-in, kept in the store. Read from the
  /// store on [start]; before that it is the id a new install would get.
  String get anonymousId => _anonId;

  /// Start sending: the events tracked so far and the ones kept from earlier
  /// runs go out in the background, then every [flushInterval] or when 20
  /// events are waiting, and when the signed-in user changes.
  ///
  /// [release] is your app's version (for the breakdown by release).
  /// [beforeSend] can change an event or return `null` to drop it. [store]
  /// keeps waiting events, the anonymous id and the opt-out (default: in
  /// memory, or SharedPreferences in Flutter apps).
  ///
  /// The returned future completes when the store is loaded.
  Future<void> start({
    String? release,
    AnalyticsBeforeSend? beforeSend,
    Duration flushInterval = const Duration(seconds: 10),
    AnalyticsStore? store,
  }) {
    _release = release;
    _beforeSend = beforeSend;
    if (_started) return _ready ?? Future.value();
    _started = true;
    _disabled = false;
    _loaded = false;
    if (store != null) _store = store;
    final every = flushInterval < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : flushInterval;
    final timer = Timer.periodic(every, (_) => unawaited(flush()));
    _off.add(timer.cancel);
    // A batch belongs to one user: send what is waiting before it changes.
    final onAuth = _onAuthChange;
    if (onAuth != null) _off.add(onAuth(() => unawaited(flush())));
    final hook = _backgroundHook;
    if (hook != null) _off.add(hook(this));
    return _ready = _load();
  }

  /// Stop sending (for example when the user withdraws consent). Waiting
  /// events stay in the store.
  void stop() {
    if (!_started) return;
    _started = false;
    for (final f in _off.reversed.toList()) {
      f();
    }
    _off.clear();
    if (_loaded) unawaited(_save());
  }

  /// Track an event named [name] with [props] (a JSON object of at most
  /// 8 KB). Events tracked before [start] wait in memory (up to 100). Invalid
  /// names and props are dropped with a log message.
  void track(String name, [Map<String, dynamic>? props]) {
    if (_optedOut || _disabled) return;
    if (!_nameRe.hasMatch(name)) {
      _log.warning(
        '"$name" is not a valid event name (letters, digits, '
        r'_ $ . : - / and spaces, up to 64): dropped',
      );
      return;
    }
    AnalyticsEvent? ev = AnalyticsEvent(name: name, props: {...?props});
    final before = _beforeSend;
    if (before != null) {
      try {
        ev = before(ev);
      } catch (_) {
        ev = null; // a throwing beforeSend drops the event
      }
    }
    if (ev == null) return;
    if (!_nameRe.hasMatch(ev.name)) {
      _log.warning('"${ev.name}" is not a valid event name: dropped');
      return;
    }
    try {
      if (utf8.encode(jsonEncode(ev.props)).length > _maxProps) {
        _log.warning('props of "${ev.name}" are larger than 8 KB: dropped');
        return;
      }
    } catch (e) {
      _log.warning('props of "${ev.name}" are not JSON: dropped ($e)');
      return;
    }
    _queue.add(ev);
    _trim(_started ? _maxQueue : _maxEarly);
    if (!_started) return;
    _persist();
    if (_queue.length >= _flushAt) unawaited(flush());
  }

  /// The user does not want to be tracked: their events are deleted on the
  /// server and no new ones are sent. Remembered on this device.
  Future<void> optOut() async {
    _optedOut = true;
    _queue.clear();
    final store = _st;
    await _chain(() async {
      await store.set('queue', null);
      await store.set('optout', 'true');
    });
    try {
      await _http.post(
        Uri.parse('$_url/opt-out'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: '{}',
      );
    } catch (_) {
      // the device remembers it
    }
  }

  /// Track again after [optOut].
  Future<void> optIn() async {
    _optedOut = false;
    final store = _st;
    await _chain(() => store.set('optout', null));
    try {
      await _http.delete(Uri.parse('$_url/opt-out'), headers: _headers());
    } catch (_) {
      // ok
    }
  }

  /// Send what is waiting now. Does nothing before [start] or while opted out.
  Future<void> flush() {
    if (!_started || _optedOut) return Future.value();
    final current = _sending;
    if (current != null) {
      // events tracked while sending
      return current.then(
        (_) => _queue.isNotEmpty && !_disabled ? flush() : null,
      );
    }
    if (!_loaded) {
      final ready = _ready;
      return ready == null ? Future.value() : ready.then((_) => flush());
    }
    late final Future<void> f;
    f = _send().whenComplete(() {
      if (identical(_sending, f)) _sending = null;
    });
    _sending = f;
    return f;
  }

  Future<void> _load() async {
    final s = _st;
    try {
      final id = await s.get('anon');
      if (id != null && id.isNotEmpty) {
        _anonId = id;
      } else {
        await s.set('anon', _anonId);
      }
    } catch (_) {}
    try {
      if (await s.get('optout') == 'true') _optedOut = true;
    } catch (_) {}
    if (_optedOut) {
      _queue.clear();
    } else {
      try {
        final saved = await s.get('queue');
        final list = saved == null ? null : jsonDecode(saved);
        if (list is List && list.isNotEmpty) {
          _queue.insertAll(0, [
            for (final e in list.whereType<Map<dynamic, dynamic>>())
              AnalyticsEvent.fromJson(e.cast<String, dynamic>()),
          ]);
        }
      } catch (_) {}
    }
    _trim(_maxQueue);
    _loaded = true;
    if (!_started) return;
    unawaited(_save());
    unawaited(flush());
  }

  void _trim(int max) {
    if (_queue.length > max) _queue.removeRange(0, _queue.length - max);
  }

  /// Runs store writes one after another.
  Future<void> _chain(Future<void> Function() write) {
    return _writes = _writes.then((_) async {
      try {
        await write();
      } catch (_) {}
    });
  }

  /// Writes the queue once for all the changes made in this turn.
  void _persist() {
    if (!_loaded || _saveScheduled) return;
    _saveScheduled = true;
    unawaited(_save());
  }

  Future<void> _save() {
    final store = _st;
    return _chain(() {
      _saveScheduled = false;
      if (!_loaded) return Future.value();
      _trim(_maxQueue);
      return store.set(
        'queue',
        _queue.isEmpty || _optedOut
            ? null
            : jsonEncode([for (final e in _queue) e.toJson()]),
      );
    });
  }

  Future<void> _send() async {
    try {
      while (_queue.isNotEmpty && !_disabled && !_optedOut) {
        final batch = _queue.take(_batchSize).toList();
        final country = _safe(_country);
        final os = _safe(_os);
        final res = await _http.post(
          Uri.parse('$_url/track'),
          headers: {..._headers(), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'anon_id': _anonId,
            'session_id': _sessionId,
            'release': _release,
            'platform': _platform,
            'os': ?os,
            'country': ?country,
            'events': [for (final e in batch) e.toJson()],
          }),
        );
        final status = res.statusCode;
        if (status == 404 || status == 403) {
          // analytics is off for the project: stop for this run
          _disabled = true;
          _queue.clear();
          break;
        }
        if ((status < 200 || status >= 300) && status != 400 && status != 413) {
          // 429 (the month's events are used up), 5xx: kept for later
          throw _RetryLater(status);
        }
        if (status == 400 || status == 413) {
          _log.warning('analytics batch rejected with $status: dropped');
        }
        _queue.removeWhere((e) => batch.any((b) => identical(b, e)));
      }
    } catch (_) {
      // offline or the server is busy: kept for the next flush or start
    }
    await _save();
  }
}

class _RetryLater implements Exception {
  final int status;
  const _RetryLater(this.status);
}

String? _safe(String? Function() f) {
  try {
    return f();
  } catch (_) {
    return null;
  }
}

const _osNames = {
  'android': 'Android',
  'ios': 'iOS',
  'macos': 'macOS',
  'windows': 'Windows',
  'linux': 'Linux',
  'fuchsia': 'Fuchsia',
};

/// The OS name sent with analytics events, e.g. `Android` or `macOS`.
@internal
String? analyticsOs(String? platform) =>
    platform == null ? 'Web' : (_osNames[platform.toLowerCase()] ?? platform);

/// The 2-letter region of a locale such as `de_DE`, `en-US` or
/// `pt_BR.UTF-8`, upper case; `null` when it has none.
@internal
String? analyticsCountry(String? locale) {
  if (locale == null) return null;
  final parts = locale.split('.').first.split(RegExp('[-_]'));
  for (final p in parts.skip(1)) {
    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(p)) return p.toUpperCase();
  }
  return null;
}

String? _dartOs() => analyticsOs(conditionalPlatform);

String? _dartCountry() => analyticsCountry(crashLocale());

String _now() => DateTime.now().toUtc().toIso8601String();
