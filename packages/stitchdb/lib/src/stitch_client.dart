import 'dart:async';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:stitchdb/src/constants.dart';
import 'package:stitchdb/src/version.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

import 'api_key.dart';
import 'auth_http_client.dart';
import 'counter.dart';
import 'crash_http_client.dart';
import 'trace_http_client.dart';

/// {@template stitch_client}
/// Creates a StitchDB client to interact with your StitchDB instance.
///
/// [stitchUrl] and [stitchKey] are on your StitchDB dashboard under
/// **Settings → API keys**. Pass the `anon` key for client-side usage or the
/// `service_role` key for trusted server-side environments only.
///
/// You can access none public schema by passing different [schema].
///
/// Default headers can be overridden by specifying [headers].
///
/// Custom http client can be used by passing [httpClient] parameter.
///
/// [storageRetryAttempts] specifies how many retry attempts there should be to
///  upload a file to StitchDB storage when failed due to network interruption.
///
/// [realtimeClientOptions] specifies different options you can pass to `RealtimeClient`.
///
/// [accessToken] Optional function for using a third-party authentication system with StitchDB.
/// The function should return an access token or ID token (JWT) by obtaining
/// it from the third-party auth client library. Note that this function may be
/// called concurrently and many times. Use memoization and locking techniques
/// if this is not supported by the client libraries. When set, the `auth`
/// namespace of the StitchDB client cannot be used.
///
/// Pass an instance of `YAJsonIsolate` to [isolate] to use your own persisted
/// isolate instance. A new instance will be created if [isolate] is omitted.
///
/// Pass an instance of [stitchAuthAsyncStorage] and set the [authFlowType] to
/// `AuthFlowType.pkce`in order to perform auth actions with pkce flow.
/// {@endtemplate}
class StitchClient {
  final String _stitchKey;
  final PostgrestClientOptions _postgrestOptions;
  final FunctionsClientOptions _functionsOptions;

  final String _restUrl;
  final String _realtimeUrl;
  final String _authUrl;
  final String _storageUrl;
  final String _functionsUrl;
  final String _syncUrl;
  final String _crashesUrl;
  final Map<String, String> _headers;
  final Client? _httpClient;
  late final Client _authHttpClient;
  late final Client _functionsHttpClient;
  late final Client _stitchAuthHttpClient;

  StitchAuthClient? _authInstance;

  /// StitchDB Functions allows you to deploy and invoke edge functions.
  late final FunctionsClient functions;

  /// StitchDB Storage allows you to manage user-generated content, such as photos or videos.
  late final StitchStorageClient storage;
  late final RealtimeClient realtime;
  late final PostgrestClient rest;

  /// Crash and error reporting: uncaught errors and errors you report, with
  /// the last API calls and actions as breadcrumbs. Nothing is captured or
  /// sent before `crashes.start()`.
  ///
  /// ```dart
  /// await stitchdb.crashes.start(release: '1.4.0');
  /// stitchdb.crashes.captureException(error, stackTrace: stackTrace);
  /// ```
  late final CrashesClient crashes;
  StreamSubscription<AuthState>? _authStateSubscription;
  final YAJsonIsolate _isolate;
  final bool _hasCustomIsolate;
  final Future<String?> Function()? accessToken;

  /// Increment ID of the stream to create different realtime topic for each stream
  final _incrementId = Counter();

  final _log = Logger('stitchdb.stitchdb');

  /// Getter for the HTTP headers
  Map<String, String> get headers => Map.unmodifiable(_headers);

  /// To apply the new headers in existing realtime channels, manually unsubscribe and resubscribe these channels.
  set headers(Map<String, String> newHeaders) {
    _headers.clear();
    _headers.addAll({
      ...Constants.defaultHeaders,
      ...newHeaders,
    });

    rest.headers
      ..clear()
      ..addAll(_headers);

    functions.headers
      ..clear()
      ..addAll(_headers);

    storage.headers
      ..clear()
      ..addAll(_headers);

    if (accessToken == null) {
      auth.headers
        ..clear()
        ..addAll({
          ...Constants.defaultHeaders,
          ..._getAuthHeaders(),
          ...headers,
        });
    }

    // To apply the new headers in the realtime client,
    // manually unsubscribe and resubscribe to all channels.
    realtime.headers
      ..clear()
      ..addAll({
        'apikey': _stitchKey,
        ..._headers,
      });
  }

  /// {@macro stitch_client}
  StitchClient(
    String stitchUrl,
    String stitchKey, {
    PostgrestClientOptions postgrestOptions = const PostgrestClientOptions(),
    AuthClientOptions authOptions = const AuthClientOptions(),
    StorageClientOptions storageOptions = const StorageClientOptions(),
    FunctionsClientOptions functionsOptions = const FunctionsClientOptions(),
    RealtimeClientOptions realtimeClientOptions = const RealtimeClientOptions(),
    TracePropagationOptions tracePropagationOptions =
        const TracePropagationOptions(),
    this.accessToken,
    Map<String, String>? headers,
    Client? httpClient,
    YAJsonIsolate? isolate,
  }) : _stitchKey = stitchKey,
       _functionsOptions = functionsOptions,
       _restUrl = '$stitchUrl/rest/v1',
       _realtimeUrl = '$stitchUrl/realtime/v1'.replaceAll('http', 'ws'),
       _authUrl = '$stitchUrl/auth/v1',
       _storageUrl = '$stitchUrl/storage/v1',
       _functionsUrl = '$stitchUrl/functions/v1',
       _syncUrl = '$stitchUrl/sync/v1',
       _crashesUrl = '$stitchUrl/crashes/v1',
       _postgrestOptions = postgrestOptions,
       _headers = {
         ...Constants.defaultHeaders,
         ...?headers,
       },
       _httpClient = httpClient,
       _isolate = isolate ?? (YAJsonIsolate()..initialize()),
       _hasCustomIsolate = isolate != null {
    final baseHttpClient = httpClient ?? Client();
    final tracedHttpClient = tracePropagationOptions.enabled
        ? TracePropagationClient(
            baseHttpClient,
            tracePropagationOptions,
            stitchUrl,
          )
        : baseHttpClient;
    // Every request goes through here, so crash reports can show the last
    // API calls.
    final recordingHttpClient = CrashRecordingClient(tracedHttpClient);
    _stitchAuthHttpClient = recordingHttpClient;
    _authInstance = _initStitchAuthClient(
      autoRefreshToken: authOptions.autoRefreshToken,
      stitchAuthAsyncStorage: authOptions.pkceAsyncStorage,
      authFlowType: authOptions.authFlowType,
    );
    _authHttpClient = AuthHttpClient(
      _stitchKey,
      recordingHttpClient,
      _getAccessToken,
    );
    _functionsHttpClient = AuthHttpClient(
      _stitchKey,
      recordingHttpClient,
      _getAccessToken,
      omitNewApiKeyAsBearer: true,
    );
    warnOnUnrecognizedApiKey(_stitchKey, _log);
    rest = _initRestClient();
    functions = _initFunctionsClient();
    storage = _initStorageClient(
      storageOptions.retryAttempts,
      storageOptions.useNewHostname,
    );
    realtime = _initRealtimeClient(options: realtimeClientOptions);
    crashes = CrashesClient(
      _crashesUrl,
      _authHttpClient,
      () => this.headers,
      recordingHttpClient,
    );
    if (accessToken == null) {
      _log.config(
        'Initialize StitchClient v$version with no custom access token',
      );
      _listenForAuthEvents();
    } else {
      _log.config(
        'Initialize StitchClient v$version with custom access token',
      );
    }
  }

  StitchAuthClient get auth {
    if (accessToken == null) {
      return _authInstance!;
    }
    throw AuthException(
      'StitchDB Client is configured with the accessToken option, accessing stitchdb.auth is not possible.',
    );
  }

  /// Perform a table operation.
  StitchQueryBuilder from(String table) {
    final url = '$_restUrl/$table';
    return StitchQueryBuilder(
      url,
      realtime,
      headers: {...rest.headers, ...headers},
      schema: _postgrestOptions.schema,
      table: table,
      httpClient: _authHttpClient,
      incrementId: _incrementId.increment(),
      isolate: _isolate,
    );
  }

  /// Select a schema to query or perform an function (rpc) call.
  ///
  /// The schema needs to be on the list of exposed schemas inside StitchDB.
  StitchQuerySchema schema(String schema) {
    final newRest = rest.schema(schema);
    return StitchQuerySchema(
      counter: _incrementId,
      restUrl: _restUrl,
      headers: headers,
      schema: schema,
      isolate: _isolate,
      authHttpClient: _authHttpClient,
      realtime: realtime,
      rest: newRest,
    );
  }

  /// {@macro postgrest_rpc}
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) {
    rest.headers.addAll(headers);
    return rest.rpc(fn, params: params, get: get);
  }

  /// Creates a Realtime channel with Broadcast, Presence, and Postgres Changes.
  RealtimeChannel channel(
    String name, {
    RealtimeChannelConfig opts = const RealtimeChannelConfig(),
  }) {
    return realtime.channel(name, opts);
  }

  /// Returns all Realtime channels.
  List<RealtimeChannel> getChannels() {
    return realtime.getChannels();
  }

  /// Unsubscribes and removes Realtime channel from Realtime client.
  ///
  /// [channel] - The name of the Realtime channel.
  Future<String> removeChannel(RealtimeChannel channel) {
    return realtime.removeChannel(channel);
  }

  ///  Unsubscribes and removes all Realtime channels from Realtime client.
  Future<List<String>> removeAllChannels() {
    return realtime.removeAllChannels();
  }

  /// Offline-first sync: a local copy of the rows the signed-in user may see
  /// in the tables that sync (Studio › Database › Offline sync). Reads come
  /// from the local copy, writes apply locally at once and are queued; the
  /// queue is pushed and changes are pulled whenever the device is online.
  ///
  /// [tables] limits the copy to these tables (default: every table that
  /// syncs). [store] keeps the copy (default: in memory; use a persistent
  /// store such as `SharedPreferencesOfflineStore` in apps, one per signed-in
  /// user). [interval] is how often to sync while online
  /// ([Duration.zero] = only when you call `sync()`). [batch] is the number of
  /// rows per pull request.
  ///
  /// ```dart
  /// final offline = stitchdb.offline(tables: ['todos']);
  /// await offline.ready;
  /// await offline.table('todos').upsert({'id': uuid, 'title': 'Milk'});
  /// offline.table('todos').stream().listen(render);
  /// ```
  OfflineClient offline({
    List<String>? tables,
    OfflineStore? store,
    Duration interval = const Duration(seconds: 30),
    int batch = 500,
  }) {
    return OfflineClient(
      _syncUrl,
      _authHttpClient,
      () => headers,
      tables: tables,
      store: store,
      interval: interval,
      batch: batch,
    );
  }

  /// Get either the custom access token from [accessToken] or the stitchdb one
  /// from [_authInstance]
  Future<String?> _getAccessToken() async {
    if (accessToken != null) {
      return await accessToken!();
    }

    try {
      final session = await _authInstance!.getSession();
      return session?.accessToken;
    } on AuthException catch (error, stackTrace) {
      // Throw the error instead of making an API request with an expired token.
      _log.warning(
        'Access token is expired and refreshing failed, aborting api request',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<void> dispose() async {
    _log.fine('Dispose StitchClient');
    crashes.stop();
    await realtime.disconnect();
    await _authStateSubscription?.cancel();
    await functions.dispose();
    await rest.dispose();
    if (!_hasCustomIsolate) {
      await _isolate.dispose();
    }
    if (_httpClient == null) {
      _authHttpClient.close();
    }
    _authInstance?.dispose();
  }

  StitchAuthClient _initStitchAuthClient({
    required bool autoRefreshToken,
    required StitchAuthAsyncStorage? stitchAuthAsyncStorage,
    required AuthFlowType authFlowType,
  }) {
    final authHeaders = {...headers};
    authHeaders['apikey'] = _stitchKey;
    authHeaders['Authorization'] = 'Bearer $_stitchKey';

    return StitchAuthClient(
      url: _authUrl,
      headers: authHeaders,
      autoRefreshToken: autoRefreshToken,
      httpClient: _stitchAuthHttpClient,
      asyncStorage: stitchAuthAsyncStorage,
      flowType: authFlowType,
    );
  }

  PostgrestClient _initRestClient() {
    return PostgrestClient(
      _restUrl,
      headers: {...headers},
      schema: _postgrestOptions.schema,
      httpClient: _authHttpClient,
      isolate: _isolate,
      retryEnabled: _postgrestOptions.retryEnabled,
      retryCount: _postgrestOptions.retryCount,
      retryableStatusCodes: _postgrestOptions.retryableStatusCodes,
      requestTimeout: _postgrestOptions.requestTimeout,
    );
  }

  FunctionsClient _initFunctionsClient() {
    return FunctionsClient(
      _functionsUrl,
      {...headers},
      httpClient: _functionsHttpClient,
      isolate: _isolate,
      region: _functionsOptions.region,
    );
  }

  StitchStorageClient _initStorageClient(
    int storageRetryAttempts,
    bool useNewHostname,
  ) {
    return StitchStorageClient(
      _storageUrl,
      {...headers},
      httpClient: _authHttpClient,
      retryAttempts: storageRetryAttempts,
      useNewHostname: useNewHostname,
    );
  }

  RealtimeClient _initRealtimeClient({
    required RealtimeClientOptions options,
  }) {
    return RealtimeClient(
      _realtimeUrl,
      params: {
        'apikey': _stitchKey,
      },
      headers: {'apikey': _stitchKey, ...headers},
      logLevel: options.logLevel,
      httpClient: _authHttpClient,
      timeout: options.timeout ?? RealtimeConstants.defaultTimeout,
      connectionCloseTimeout:
          options.connectionCloseTimeout ??
          RealtimeConstants.defaultConnectionCloseTimeout,
      customAccessToken: accessToken,
      transport: options.transport,
      disconnectOnEmptyChannelsAfter: options.disconnectOnEmptyChannelsAfter,
    );
  }

  /// Requires the `auth` instance, so no custom `accessToken` is allowed.
  Map<String, String> _getAuthHeaders() {
    final authBearer = auth.currentSession?.accessToken ?? _stitchKey;
    final defaultHeaders = {
      'apikey': _stitchKey,
      'Authorization': 'Bearer $authBearer',
    };
    final mergedHeaders = {...defaultHeaders, ..._headers};
    return mergedHeaders;
  }

  void _listenForAuthEvents() {
    // ignore: invalid_use_of_internal_member
    _authStateSubscription = auth.onAuthStateChangeSync.listen(
      (data) {
        unawaited(
          _handleTokenChanged(data.event, data.session?.accessToken),
        );
      },
      onError: (error, stack) {},
    );
  }

  Future<void> _handleTokenChanged(AuthChangeEvent event, String? token) async {
    if (event == AuthChangeEvent.initialSession ||
        event == AuthChangeEvent.tokenRefreshed ||
        event == AuthChangeEvent.signedIn) {
      try {
        await realtime.setAuth(token);
      } on FormatException catch (e) {
        if (e.message.contains('InvalidJWTToken')) {
          // The exception is thrown by RealtimeClient when the token is
          // expired for example on app launch after the app has been closed
          // for a while.
        } else {
          rethrow;
        }
      }
    } else if (event == AuthChangeEvent.signedOut) {
      // Token is removed

      await realtime.setAuth(_stitchKey);
    }
  }
}
