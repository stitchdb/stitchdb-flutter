import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:stitchdb_common/stitchdb_common.dart';
import 'package:stitchdb_flutter/src/constants.dart';
import 'package:stitchdb_flutter/src/crash_reporting.dart';
import 'package:stitchdb_flutter/src/flutter_auth_client_options.dart';
import 'package:stitchdb_flutter/src/local_storage.dart';
import 'package:stitchdb_flutter/src/realtime_lifecycle_options.dart';
import 'package:stitchdb_flutter/src/stitch_auth.dart';

import 'hot_restart_cleanup_stub.dart'
    if (dart.library.js_interop) 'hot_restart_cleanup_web.dart';
import 'version.dart';

final _log = Logger('stitchdb.stitchdb_flutter');

/// StitchDB instance.
///
/// It must be initialized before used, otherwise an error is thrown.
///
/// ```dart
/// await Stitch.initialize(...)
/// ```
///
/// Use it:
///
/// ```dart
/// final instance = Stitch.instance;
/// ```
///
/// See also:
///
///   * [StitchAuth]
class Stitch {
  /// Gets the current stitchdb instance.
  ///
  /// An [AssertionError] is thrown if stitchdb isn't initialized yet.
  /// Call [Stitch.initialize] to initialize it.
  static Stitch get instance {
    assert(
      _instance._isInitialized,
      'You must initialize the stitchdb instance before calling Stitch.instance',
    );
    return _instance;
  }

  /// Initialize the current stitchdb instance
  ///
  /// This must be called only once. If called more than once, an
  /// [AssertionError] is thrown
  ///
  /// [url] and [anonKey] are on your StitchDB dashboard under
  /// **Settings → API keys**. Use the `anon` key here — never the
  /// `service_role` key in a Flutter app.
  ///
  /// [publishableKey] is an alias of [anonKey], kept for compatibility.
  ///
  /// You can access none public schema by passing different [schema].
  ///
  /// Default headers can be overridden by specifying [headers].
  ///
  /// Pass [localStorage] to override the default local storage option used to
  /// persist auth.
  ///
  /// Custom http client can be used by passing [httpClient] parameter.
  ///
  /// [storageRetryAttempts] specifies how many retry attempts there should be
  /// to upload a file to StitchDB storage when failed due to network
  /// interruption.
  ///
  /// [realtimeLifecycleOptions] controls how the realtime socket follows the
  /// app lifecycle. By default it is disconnected as soon as the app is paused
  /// and reconnected, with every joined channel rejoined, when the app is
  /// resumed. See [RealtimeLifecycleOptions] to delay the disconnect or to
  /// manage the socket yourself.
  ///
  /// Set [authFlowType] to [AuthFlowType.implicit] to use the old implicit flow for authentication
  /// involving deep links.
  ///
  /// PKCE flow uses shared preferences for storing the code verifier by default.
  /// Pass a custom storage to [pkceAsyncStorage] to override the behavior.
  ///
  /// If [debug] is set to `true`, debug logs will be printed in debug console. Default is `kDebugMode`.
  static Future<Stitch> initialize({
    required String url,
    String? anonKey,
    @Deprecated('Use anonKey instead.')
    String? publishableKey,
    Map<String, String>? headers,
    Client? httpClient,
    RealtimeClientOptions realtimeClientOptions = const RealtimeClientOptions(),
    RealtimeLifecycleOptions realtimeLifecycleOptions =
        const RealtimeLifecycleOptions(),
    PostgrestClientOptions postgrestOptions = const PostgrestClientOptions(),
    StorageClientOptions storageOptions = const StorageClientOptions(),
    FlutterAuthClientOptions authOptions = const FlutterAuthClientOptions(),
    TracePropagationOptions tracePropagationOptions =
        const TracePropagationOptions(),
    Future<String?> Function()? accessToken,
    bool? debug,
  }) async {
    assert(
      anonKey != null || publishableKey != null,
      'Pass your project\'s anon key as anonKey.',
    );
    final effectiveKey = anonKey ?? publishableKey!;

    if (_instance._isInitialized) {
      _log.info('StitchDB is already initialized. Skipping reinitialization.');
      return _instance;
    }

    _instance._debugEnable = debug ?? (kDebugMode && !isRunningInFlutterTest);

    if (_instance._debugEnable) {
      _instance._logSubscription = Logger('stitchdb').onRecord.listen((record) {
        if (record.level >= Level.INFO) {
          debugPrint(
            '${record.loggerName}: ${record.level.name}: ${record.message} ${record.error ?? ""}',
          );
        }
      });
    }

    _log.config("Initialize StitchDB v$version");

    if (authOptions.pkceAsyncStorage == null) {
      authOptions = authOptions.copyWith(
        pkceAsyncStorage: SharedPreferencesStitchAuthAsyncStorage(),
      );
    }
    if (authOptions.localStorage == null) {
      authOptions = authOptions.copyWith(
        localStorage: authOptions.persistSession
            ? SharedPreferencesLocalStorage(
                persistSessionKey:
                    "stitchdb-${Uri.parse(url).host.split(".").first}-auth-token",
              )
            : const EmptyLocalStorage(),
      );
    }
    _instance._init(
      url,
      effectiveKey,
      httpClient: httpClient,
      customHeaders: headers,
      realtimeClientOptions: realtimeClientOptions,
      realtimeLifecycleOptions: realtimeLifecycleOptions,
      authOptions: authOptions,
      postgrestOptions: postgrestOptions,
      storageOptions: storageOptions,
      tracePropagationOptions: tracePropagationOptions,
      accessToken: accessToken,
    );

    if (accessToken == null) {
      final stitchAuth = StitchAuth();
      _instance._stitchAuth = stitchAuth;
      await stitchAuth.initialize(options: authOptions);

      // Wrap `recoverSession()` in a `CancelableOperation` so that it can be canceled in dispose
      // if still in progress
      _instance._restoreSessionCancellableOperation =
          CancelableOperation.fromFuture(stitchAuth.recoverSession());
    }

    _log.info('***** StitchDB init completed *****');

    return _instance;
  }

  Stitch._();
  static final Stitch _instance = Stitch._();

  bool _isInitialized = false;

  /// Whether the StitchDB instance has been initialized. Useful for debugging.
  bool get isInitialized => _isInitialized;

  /// The stitchdb client for this instance
  ///
  /// Throws an error if [Stitch.initialize] was not called.
  late StitchClient client;

  StitchAuth? _stitchAuth;

  bool _debugEnable = false;

  /// Wraps the `recoverSession()` call so that it can be terminated when `dispose()` is called
  ///
  /// Only set when [Stitch.initialize] is called without a custom
  /// `accessToken`, since session recovery is skipped for third-party auth.
  CancelableOperation<dynamic>? _restoreSessionCancellableOperation;

  // Listener for app lifecycle events to handle Realtime reconnection.
  AppLifecycleListener? _lifecycleListener;

  RealtimeLifecycleOptions _realtimeLifecycleOptions =
      const RealtimeLifecycleOptions();

  /// Counts down [RealtimeLifecycleOptions.disconnectAfterPause] while the
  /// app is paused. Cancelled when the app is resumed or detached first.
  Timer? _pendingPause;

  /// When [_pendingPause] started. The operating system may freeze the app
  /// before the timer fires, so on resume the elapsed wall-clock time decides
  /// whether the pause counts as expired.
  DateTime? _pausedAt;

  /// Serial queue for lifecycle operations (connect/disconnect). Each event
  /// appends via `.then()` so operations never overlap.
  Future<void> _pendingLifecycleOperation = Future.value();

  /// The most recently requested lifecycle state. Checked inside
  /// [_processLifecycle] after each `await` to skip stale operations
  /// (e.g. abort a reconnect if the app went back to background).
  AppLifecycleState? _targetLifecycleState;

  StreamSubscription<dynamic>? _logSubscription;

  /// Dispose the instance to free up resources.
  Future<void> dispose() async {
    _targetLifecycleState = null;
    _cancelPendingPause();
    await _restoreSessionCancellableOperation?.cancel();
    await _logSubscription?.cancel();
    await client.dispose();
    _instance._stitchAuth?.dispose();
    _lifecycleListener?.dispose();
    _isInitialized = false;
  }

  void _init(
    String stitchUrl,
    String stitchKey, {
    Client? httpClient,
    Map<String, String>? customHeaders,
    required RealtimeClientOptions realtimeClientOptions,
    required RealtimeLifecycleOptions realtimeLifecycleOptions,
    required PostgrestClientOptions postgrestOptions,
    required StorageClientOptions storageOptions,
    required AuthClientOptions authOptions,
    required TracePropagationOptions tracePropagationOptions,
    required Future<String?> Function()? accessToken,
  }) {
    _realtimeLifecycleOptions = realtimeLifecycleOptions;
    final headers = {
      ...Constants.defaultHeaders,
      ...?customHeaders,
    };
    client = StitchClient(
      stitchUrl,
      stitchKey,
      httpClient: httpClient,
      headers: headers,
      realtimeClientOptions: realtimeClientOptions,
      postgrestOptions: postgrestOptions,
      storageOptions: storageOptions,
      authOptions: authOptions,
      tracePropagationOptions: tracePropagationOptions,
      accessToken: accessToken,
    );
    // `client.crashes.start()` reports as a Flutter app and keeps unsent
    // reports in SharedPreferences.
    configureFlutterCrashes(
      client,
      storeName:
          'stitchdb-${Uri.parse(stitchUrl).host.split('.').first}-crashes',
    );

    // Close any previous realtime client that may still be connected due to
    // flutter web hot-restart.
    if (kDebugMode) {
      disposePreviousClient();
      markClientToDispose(client);
    }

    _setupLifecycleListener();

    _isInitialized = true;
  }

  void _setupLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        switch (state) {
          case AppLifecycleState.resumed:
            final pauseExpired = _pendingPauseExpired();
            _cancelPendingPause();
            _enqueueLifecycle(state, replaceConnection: pauseExpired);
          case AppLifecycleState.detached:
            _cancelPendingPause();
            _enqueueLifecycle(state);
          case AppLifecycleState.paused:
            final delay = _realtimeLifecycleOptions.disconnectAfterPause;
            if (delay == Duration.zero) {
              _enqueueLifecycle(state);
            } else {
              _cancelPendingPause();
              _pausedAt = DateTime.now();
              _pendingPause = Timer(delay, () {
                _cancelPendingPause();
                _enqueueLifecycle(AppLifecycleState.paused);
              });
            }
          case AppLifecycleState.inactive:
          case AppLifecycleState.hidden:
            break;
        }
      },
    );
  }

  void _enqueueLifecycle(
    AppLifecycleState state, {
    bool replaceConnection = false,
  }) {
    _targetLifecycleState = state;
    _pendingLifecycleOperation = _pendingLifecycleOperation
        .then(
          (_) => _processLifecycle(state, replaceConnection: replaceConnection),
        )
        .catchError((_) {});
  }

  bool _pendingPauseExpired() {
    final pausedAt = _pausedAt;
    if (_pendingPause == null || pausedAt == null) return false;
    return DateTime.now().difference(pausedAt) >=
        _realtimeLifecycleOptions.disconnectAfterPause;
  }

  void _cancelPendingPause() {
    _pendingPause?.cancel();
    _pendingPause = null;
    _pausedAt = null;
  }

  /// Processes a lifecycle state change. Operations are serialized via
  /// [_pendingLifecycleOp] so that disconnect and connect never overlap.
  ///
  /// [captured] is the lifecycle state at the time the event was enqueued.
  /// If a newer event has arrived since, this one is skipped (stale).
  ///
  /// [replaceConnection] closes an open socket before reconnecting, for a
  /// resume after a pause that outlasted its grace period while the app was
  /// frozen, since the socket may be dead by then.
  Future<void> _processLifecycle(
    AppLifecycleState captured, {
    bool replaceConnection = false,
  }) async {
    // Skip if a newer lifecycle event has superseded this one.
    if (captured != _targetLifecycleState) return;
    if (!_realtimeLifecycleOptions.managed) return;

    final realtime = Stitch.instance.client.realtime;

    if (captured == AppLifecycleState.resumed) {
      // No channels subscribed — nothing to reconnect.
      if (realtime.channels.isEmpty) return;

      if (replaceConnection && realtime.isConnected) {
        await realtime.disconnect();
        if (_targetLifecycleState != AppLifecycleState.resumed) return;
      }

      // Already connected (e.g. coming from [AppLifecycleState.inactive]
      // where no disconnect happened).
      if (realtime.isConnected) return;

      // ignore: invalid_use_of_internal_member
      await realtime.connect();

      // Abort rejoin if app went back to background during connect.
      if (_targetLifecycleState != AppLifecycleState.resumed) return;

      // Re-send join messages for channels that were previously joined.
      // After a disconnect/reconnect the WebSocket is fresh, but the
      // channel objects still have joined state — forceRejoin() restores
      // the server-side subscriptions.
      for (final channel in realtime.channels) {
        // ignore: invalid_use_of_internal_member
        if (channel.isJoined) {
          // ignore: invalid_use_of_internal_member
          channel.forceRejoin();
        }
      }
    } else {
      // paused or detached — disconnect the WebSocket if it is active.
      // These states are not triggered on web
      if (realtime.isConnected ||
          realtime.connState == SocketStates.connecting) {
        await realtime.disconnect();
      }
    }
  }
}
