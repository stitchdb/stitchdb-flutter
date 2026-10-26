import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

import 'crash_http_client.dart';
import 'crash_store.dart';
import 'version.dart';

// Crash and error reporting (`stitchdb.crashes`): uncaught errors and errors
// you report yourself, grouped into issues in Studio › Crashes with the stack,
// app version, device, the signed-in user and the user's last actions and API
// calls ("crashed right after GET /rest/v1/orders returned 500").
//
// Nothing is captured, recorded or sent before `start()`, and nothing is
// stored unless the project has crash reporting turned on (Studio › Crashes).
// Reports that cannot be sent (offline, the app closing) stay in the
// [CrashStore] and are sent on the next start.

const _maxQueue = 30;
const _batchSize = 20;

/// Where crash reporting keeps the reports waiting to be sent, the install id
/// and the day the last session was sent. Values are strings (JSON).
abstract class CrashStore {
  /// The value under [key], or `null` when there is none.
  Future<String?> get(String key);

  /// Stores [value] under [key]; `null` removes it.
  Future<void> set(String key, String? value);

  /// Like [set], but used while the app crashes: writes synchronously where
  /// the store can, otherwise starts the write and returns at once.
  void setNow(String key, String? value);
}

/// A [CrashStore] that keeps everything in memory: reports that could not be
/// sent are lost when the process exits. Use [FileCrashStore] (dart:io) or,
/// in Flutter apps, `SharedPreferencesCrashStore` to keep them.
class MemoryCrashStore implements CrashStore {
  final _m = <String, String>{};

  @override
  Future<String?> get(String key) async => _m[key];

  @override
  Future<void> set(String key, String? value) async => setNow(key, value);

  @override
  void setNow(String key, String? value) {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}

/// Something the user did or the app went through; the last ones are sent
/// with the next report.
class Breadcrumb {
  /// `api`, `navigation`, `ui`, `log` or your own word.
  final String? type;
  final String? message;

  /// `debug`, `info`, `warning` or `error`.
  final String? level;
  final Map<String, dynamic>? data;

  /// ISO 8601 time; set when the breadcrumb is added.
  final String? at;

  const Breadcrumb({this.type, this.message, this.level, this.data, this.at});

  Map<String, dynamic> toJson() => {
    if (at != null) 'at': at,
    if (type != null) 'type': type,
    if (message != null) 'message': message,
    if (level != null) 'level': level,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'Breadcrumb(${jsonEncode(toJson())})';
}

/// The error of a [CrashReport].
class CrashException {
  String type;
  String message;

  /// The normal Dart stack trace text.
  String? stack;

  /// How it was caught, e.g. `FlutterError.onError` or `runZonedGuarded`.
  String? mechanism;

  CrashException({
    required this.type,
    required this.message,
    this.stack,
    this.mechanism,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'message': message,
    if (stack != null) 'stack': stack,
    if (mechanism != null) 'mechanism': mechanism,
  };
}

/// One report, as it is sent. Change it in `beforeSend`.
class CrashReport {
  String platform;
  String? release;
  String environment;
  String installId;

  /// ISO 8601 time of the crash.
  String at;
  bool handled;
  CrashException exception;
  List<Breadcrumb> breadcrumbs;
  Map<String, dynamic> device;
  Map<String, dynamic> context;
  List<String>? fingerprint;

  CrashReport({
    required this.platform,
    required this.release,
    required this.environment,
    required this.installId,
    required this.at,
    required this.handled,
    required this.exception,
    required this.breadcrumbs,
    required this.device,
    required this.context,
    this.fingerprint,
  });

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'release': release,
    'environment': environment,
    'install_id': installId,
    'at': at,
    'handled': handled,
    'exception': exception.toJson(),
    'breadcrumbs': [for (final b in breadcrumbs) b.toJson()],
    'device': device,
    'context': context,
    if (fingerprint != null) 'fingerprint': fingerprint,
  };
}

/// Change a report or return `null` to not send it (consent, filtering).
typedef CrashBeforeSend = FutureOr<CrashReport?> Function(CrashReport report);

/// Installs handlers for uncaught errors and returns a function that removes
/// them. Used by platform integrations such as `stitchdb_flutter`.
typedef CrashUnhandledHook = void Function() Function(CrashesClient crashes);

/// Crash and error reporting for one [StitchClient] (`stitchdb.crashes`).
///
/// ```dart
/// await stitchdb.crashes.start(release: '1.4.0');
/// try {
///   await checkout();
/// } catch (e, s) {
///   stitchdb.crashes.captureException(e, stackTrace: s, context: {'step': 'payment'});
/// }
/// stitchdb.crashes.addBreadcrumb(type: 'ui', message: 'tapped Checkout');
/// ```
class CrashesClient {
  final String _url;
  final Client _http;
  final Map<String, String> Function() _headers;
  final CrashRecordingClient _recorder;

  String _platform = 'dart';
  String _sdk = 'stitchdb-dart/$version';
  Map<String, dynamic> Function() _device = _dartDevice;
  CrashUnhandledHook? _unhandledHook;
  CrashStore _defaultStore = MemoryCrashStore();
  CrashStore _store = MemoryCrashStore();

  String? _release;
  String _environment = 'production';
  CrashBeforeSend? _beforeSend;
  int _maxBreadcrumbs = 50;

  bool _started = false;
  bool _loaded = false;
  bool _disabled = false;
  Future<void>? _ready;
  Future<void>? _sending;
  Future<void> _writes = Future.value();
  String? _installId;
  final _crumbs = <Breadcrumb>[];
  final _queue = <Map<String, dynamic>>[];
  final _off = <void Function()>[];

  @internal
  CrashesClient(this._url, this._http, this._headers, this._recorder);

  /// Whether [start] was called (and not [stop]).
  bool get isStarted => _started;

  /// For platform integrations such as `stitchdb_flutter`: the platform name
  /// sent with reports, the SDK name, the default [store], the device info and
  /// the [unhandled] hook that installs handlers for uncaught errors when
  /// `start(captureUnhandled: true)` is called.
  void configure({
    String? platform,
    String? sdk,
    CrashStore? store,
    Map<String, dynamic> Function()? device,
    CrashUnhandledHook? unhandled,
  }) {
    if (platform != null) _platform = platform;
    if (sdk != null) _sdk = sdk;
    if (store != null) _defaultStore = store;
    if (device != null) _device = device;
    if (unhandled != null) _unhandledHook = unhandled;
  }

  /// Start reporting: records API calls as breadcrumbs, catches uncaught
  /// errors (unless [captureUnhandled] is false; in pure Dart wrap your app in
  /// [runGuarded]), sends the reports kept from earlier runs and, once a day,
  /// the session used for crash-free users.
  ///
  /// [release] is your app's version (issues and crash-free users are shown
  /// per release). [beforeSend] can change a report or return `null` to drop
  /// it. [maxBreadcrumbs] is how many breadcrumbs are kept (at most 100).
  /// [store] keeps unsent reports (default: in memory, or the platform's
  /// persistent store in Flutter apps).
  ///
  /// The returned future completes when the store is loaded; sending happens
  /// in the background.
  Future<void> start({
    String? release,
    String environment = 'production',
    bool captureUnhandled = true,
    CrashBeforeSend? beforeSend,
    int maxBreadcrumbs = 50,
    CrashStore? store,
  }) {
    _release = release;
    _environment = environment;
    _beforeSend = beforeSend;
    _maxBreadcrumbs = min(max(maxBreadcrumbs, 0), 100);
    if (_started) return _ready ?? Future.value();
    _started = true;
    _disabled = false;
    _loaded = false;
    _store = store ?? _defaultStore;
    void sink(Breadcrumb c) => _addCrumb(c);
    _recorder.sink = sink;
    _off.add(() {
      if (_recorder.sink == sink) _recorder.sink = null;
    });
    final hook = _unhandledHook;
    if (captureUnhandled && hook != null) _off.add(hook(this));
    return _ready = _load();
  }

  /// Stop reporting and remove the handlers (for example when the user
  /// withdraws consent). Queued reports stay in the store.
  void stop() {
    _started = false;
    for (final f in _off.reversed.toList()) {
      f();
    }
    _off.clear();
  }

  /// Report an error you caught. Returns once it is queued; sending happens
  /// in the background (or await [flush]). Uses [StackTrace.current] when no
  /// [stackTrace] is given.
  void captureException(
    Object error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    List<String>? fingerprint,
    bool handled = true,
    String? mechanism,
  }) {
    if (!_started) return;
    _enqueue(
      CrashException(
        type: error is String ? 'Error' : error.runtimeType.toString(),
        message: _cut('$error'),
        stack: (stackTrace ?? StackTrace.current).toString(),
        mechanism: mechanism,
      ),
      handled,
      context,
      fingerprint,
    );
  }

  /// Report a message as an error, e.g. a state that should never happen.
  void captureMessage(
    String message, {
    Map<String, dynamic>? context,
    List<String>? fingerprint,
  }) {
    if (!_started) return;
    _enqueue(
      CrashException(
        type: 'Message',
        message: _cut(message),
        stack: StackTrace.current.toString(),
      ),
      true,
      context,
      fingerprint,
    );
  }

  /// Something the user did or the app went through; the last ones are sent
  /// with the next report. Ignored before [start].
  void addBreadcrumb({
    String? type,
    String? message,
    Map<String, dynamic>? data,
    String level = 'info',
  }) {
    if (!_started) return;
    _addCrumb(
      Breadcrumb(type: type, message: message, data: data, level: level),
    );
  }

  /// Runs [body] in a zone that reports its uncaught errors (sync and async)
  /// as crashes, then hands them to [onError] (default: printed like the Dart
  /// VM does). Wrap your `main` in it:
  ///
  /// ```dart
  /// void main() => stitchdb.crashes.runGuarded(() async {
  ///   await stitchdb.crashes.start(release: '1.4.0');
  ///   await runApp();
  /// });
  /// ```
  R? runGuarded<R>(
    R Function() body, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    return runZonedGuarded(body, (error, stackTrace) {
      captureException(
        error,
        stackTrace: stackTrace,
        handled: false,
        mechanism: 'runZonedGuarded',
      );
      if (onError != null) {
        onError(error, stackTrace);
      } else {
        Zone.root.print('Unhandled exception:\n$error\n$stackTrace');
      }
    });
  }

  /// Send what is queued now (also retried on the next start).
  Future<void> flush() {
    final current = _sending;
    if (current != null) {
      // reports queued while sending
      return current.then(
        (_) => _queue.isNotEmpty && !_disabled ? flush() : null,
      );
    }
    if (!_loaded) {
      final ready = _ready;
      return ready == null || !_started
          ? Future.value()
          : ready.then((_) => flush());
    }
    late final Future<void> f;
    f = _send().whenComplete(() {
      if (identical(_sending, f)) _sending = null;
    });
    _sending = f;
    return f;
  }

  void _addCrumb(Breadcrumb c) {
    _crumbs.add(
      c.at != null
          ? c
          : Breadcrumb(
              type: c.type,
              message: c.message,
              level: c.level,
              data: c.data,
              at: _now(),
            ),
    );
    if (_crumbs.length > _maxBreadcrumbs) {
      _crumbs.removeRange(0, _crumbs.length - _maxBreadcrumbs);
    }
  }

  Future<void> _load() async {
    final s = _store;
    String? id;
    try {
      id = await s.get('install');
    } catch (_) {}
    if (id == null || id.isEmpty) {
      id = _uuid();
      try {
        await s.set('install', id);
      } catch (_) {}
    }
    _installId = id;
    try {
      final saved = await s.get('queue');
      final list = saved == null ? null : jsonDecode(saved);
      if (list is List && list.isNotEmpty) {
        // The store holds every report queued so far, sent ones removed.
        _queue
          ..clear()
          ..addAll(
            list.whereType<Map<dynamic, dynamic>>().map(
              (r) => r.cast<String, dynamic>(),
            ),
          );
        if (_queue.length > _maxQueue) {
          _queue.removeRange(0, _queue.length - _maxQueue);
        }
      }
    } catch (_) {}
    _loaded = true;
    unawaited(_session());
    unawaited(flush());
  }

  void _enqueue(
    CrashException ex,
    bool handled,
    Map<String, dynamic>? context,
    List<String>? fingerprint,
  ) {
    Map<String, dynamic> device;
    try {
      device = {..._device(), 'sdk': _sdk};
    } catch (_) {
      device = {'sdk': _sdk};
    }
    final report = CrashReport(
      platform: _platform,
      release: _release,
      environment: _environment,
      installId: _installId ?? '',
      at: _now(),
      handled: handled,
      exception: ex,
      breadcrumbs: List.of(_crumbs),
      device: device,
      context: {...?context},
      fingerprint: fingerprint,
    );
    if (_loaded) {
      _process(report);
    } else {
      unawaited(
        _ready?.then((_) {
          report.installId = _installId ?? '';
          _process(report);
        }),
      );
    }
  }

  void _process(CrashReport report) {
    final FutureOr<CrashReport?> out;
    try {
      out = _beforeSend == null ? report : _beforeSend!(report);
    } catch (_) {
      return; // a throwing beforeSend drops the report
    }
    if (out is Future<CrashReport?>) {
      unawaited(out.then(_add, onError: (_) {}));
    } else {
      _add(out);
    }
  }

  void _add(CrashReport? r) {
    if (r == null || !_started) return;
    _queue.add(r.toJson());
    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue);
    }
    // Kept until sent, in case the app closes now.
    if (r.handled) {
      unawaited(_save());
    } else {
      try {
        _store.setNow('queue', jsonEncode(_queue));
      } catch (_) {}
    }
    unawaited(flush());
  }

  /// Writes the queue; writes run one after another.
  Future<void> _save() {
    final store = _store;
    return _writes = _writes.then((_) async {
      try {
        await store.set(
          'queue',
          _queue.isEmpty
              ? null
              : jsonEncode(
                  _queue.length > _maxQueue
                      ? _queue.sublist(_queue.length - _maxQueue)
                      : _queue,
                ),
        );
      } catch (_) {}
    });
  }

  Future<void> _send() async {
    try {
      while (_queue.isNotEmpty && !_disabled) {
        final batch = _queue.take(_batchSize).toList();
        final res = await _http.post(
          Uri.parse('$_url/report'),
          headers: {..._headers(), 'Content-Type': 'application/json'},
          body: jsonEncode({'reports': batch}),
        );
        final status = res.statusCode;
        if (status == 404 || status == 403) {
          // crash reporting is off for the project
          _disabled = true;
          _queue.clear();
          break;
        }
        if ((status < 200 || status >= 300) &&
            status != 400 &&
            status != 413 &&
            status != 429) {
          throw _RetryLater(status);
        }
        _queue.removeWhere((r) => batch.any((b) => identical(b, r)));
      }
    } catch (_) {
      // offline or the server is busy: kept for the next start
    }
    await _save();
  }

  // Once a day per install and release, for crash-free users in Studio.
  Future<void> _session() async {
    final store = _store;
    final mark = '${_now().substring(0, 10)}|${_release ?? ''}';
    try {
      if (await store.get('session') == mark) return;
      final res = await _http.post(
        Uri.parse('$_url/session'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'release': _release,
          'install_id': _installId,
          'environment': _environment,
        }),
      );
      if (res.statusCode == 404 || res.statusCode == 403) {
        _disabled = true;
      } else if (res.statusCode >= 200 && res.statusCode < 300) {
        await store.set('session', mark);
      }
    } catch (_) {
      // offline: tried again on the next start
    }
  }
}

class _RetryLater implements Exception {
  final int status;
  const _RetryLater(this.status);
}

Map<String, dynamic> _dartDevice() => {
  'os': conditionalPlatform ?? 'web',
  if (conditionalPlatformVersion != null)
    'os_version': conditionalPlatformVersion,
  'runtime': 'dart',
  if (conditionalRuntimeVersion != null)
    'runtime_version': conditionalRuntimeVersion,
  if (crashLocale() != null) 'locale': crashLocale(),
};

String _cut(String s) => s.length > 2000 ? s.substring(0, 2000) : s;

String _now() => DateTime.now().toUtc().toIso8601String();

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
