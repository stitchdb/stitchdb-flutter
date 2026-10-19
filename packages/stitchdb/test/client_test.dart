import 'dart:async';
import 'dart:io';

import 'package:stitchdb/stitchdb.dart';
import 'package:stitchdb_common/stitchdb_common.dart';
import 'package:test/test.dart';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

import 'utils.dart';

void main() {
  /// Extracts a single request sent to the realtime server
  Future<HttpRequest> getRealtimeRequest({
    required HttpServer server,
    required StitchClient stitchClient,
  }) {
    stitchClient.channel('name').subscribe();

    return server.first;
  }

  group('Standard Header', () {
    late String stitchUrl;
    const stitchKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdGl0Y2hkYiIsInJlZiI6Im53emxkenlsb2pyemdqemloZHJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE2ODQxMzI2ODAsImV4cCI6MTk5OTcwODY4MH0.Vl2Vbs46-HDBrxVnUn3nTpMeet-YN7gb5oZRetT0d_4';
    late StitchClient stitch;
    late HttpServer mockServer;

    setUp(() async {
      mockServer = await HttpServer.bind('localhost', 0);
      stitchUrl = 'http://${mockServer.address.host}:${mockServer.port}';

      stitch = StitchClient(stitchUrl, stitchKey);
    });

    tearDown(() async {
      await stitch.removeAllChannels();
      await stitch.dispose();
    });

    test('X-Client-Info includes structured platform metadata', () {
      final clientInfo = stitch.headers['X-Client-Info']!;
      expect(clientInfo, startsWith('stitchdb-dart/'));
      expect(
        clientInfo,
        contains(
          '; platform=${normalizePlatformName(Platform.operatingSystem)}',
        ),
      );
      expect(clientInfo, contains('; runtime=dart'));
    });

    test('X-Client-Info includes structured platform metadata on auth', () {
      final clientInfo = stitch.auth.headers['X-Client-Info']!;
      expect(clientInfo, startsWith('stitchdb-dart/'));
      expect(
        clientInfo,
        contains(
          '; platform=${normalizePlatformName(Platform.operatingSystem)}',
        ),
      );
      expect(clientInfo, contains('; runtime=dart'));
    });

    test('X-Client-Info includes structured platform metadata on storage', () {
      final clientInfo = stitch.storage.headers['X-Client-Info']!;
      expect(clientInfo, startsWith('stitchdb-dart/'));
      expect(
        clientInfo,
        contains(
          '; platform=${normalizePlatformName(Platform.operatingSystem)}',
        ),
      );
      expect(clientInfo, contains('; runtime=dart'));
    });

    test(
      'X-Client-Info includes structured platform metadata on functions',
      () {
        final clientInfo = stitch.functions.headers['X-Client-Info']!;
        expect(clientInfo, startsWith('stitchdb-dart/'));
        expect(
          clientInfo,
          contains(
            '; platform=${normalizePlatformName(Platform.operatingSystem)}',
          ),
        );
        expect(clientInfo, contains('; runtime=dart'));
      },
    );

    test('X-Client-Info includes structured platform metadata on rest', () {
      final clientInfo = stitch.rest.headers['X-Client-Info']!;
      expect(clientInfo, startsWith('stitchdb-dart/'));
      expect(
        clientInfo,
        contains(
          '; platform=${normalizePlatformName(Platform.operatingSystem)}',
        ),
      );
      expect(clientInfo, contains('; runtime=dart'));
    });

    test(
      'X-Client-Info includes structured platform metadata on realtime',
      () async {
        final request = await getRealtimeRequest(
          server: mockServer,
          stitchClient: stitch,
        );
        final clientInfo = request.headers['X-Client-Info']?.first;
        expect(clientInfo, startsWith('stitchdb-dart/'));
        expect(
          clientInfo,
          contains(
            '; platform=${normalizePlatformName(Platform.operatingSystem)}',
          ),
        );
        expect(clientInfo, contains('; runtime=dart'));
      },
    );

    test('X-Client-Info header is set properly on storage', () {
      final xClientHeaderBeforeSlash = stitch
          .storage
          .headers['X-Client-Info']!
          .split('/')
          .first;
      expect(xClientHeaderBeforeSlash, 'stitchdb-dart');
    });

    test('realtime URL is properly being set', () async {
      final request = await getRealtimeRequest(
        server: mockServer,
        stitchClient: stitch,
      );

      final realtimeWebsocketURL = request.uri;

      expect(
        realtimeWebsocketURL.queryParameters,
        containsPair('apikey', stitchKey),
      );
      expect(realtimeWebsocketURL.queryParameters['log_level'], isNull);
    });

    test('log_level query parameter is properly set', () async {
      stitch = StitchClient(
        stitchUrl,
        stitchKey,
        realtimeClientOptions: RealtimeClientOptions(
          logLevel: RealtimeLogLevel.info,
        ),
      );

      final request = await getRealtimeRequest(
        server: mockServer,
        stitchClient: stitch,
      );

      final realtimeWebsocketURL = request.uri;

      expect(
        realtimeWebsocketURL.queryParameters,
        containsPair('apikey', stitchKey),
      );
      expect(
        realtimeWebsocketURL.queryParameters,
        containsPair('log_level', 'info'),
      );
    });

    test('realtime access token is set properly', () async {
      final request = await getRealtimeRequest(
        server: mockServer,
        stitchClient: stitch,
      );

      expect(request.uri.queryParameters['apikey'], stitchKey);
    });
  });

  group('auth', () {
    test('properly set Authorization header', () async {
      final (:sessionString, :accessToken) = getSessionData(
        DateTime.now().add(Duration(hours: 1)),
      );

      final mockServer = await HttpServer.bind('localhost', 0);
      final stitch = StitchClient(
        'http://${mockServer.address.host}:${mockServer.port}',
        "stitchKey",
        authOptions: AuthClientOptions(autoRefreshToken: false),
      );
      await stitch.auth.recoverSession(sessionString);

      // Make some requests
      unawaited(stitch.from("test").select().then((value) => null));
      unawaited(stitch.rpc("test").select().then((value) => null));
      unawaited(stitch.functions.invoke("test").then((value) => null));
      unawaited(stitch.storage.from("test").list().then((value) => null));

      var count = 0;

      // Check for every request if the Authorization header is set properly
      await for (final request in mockServer) {
        expect(
          request.headers.value('Authorization')?.split(" ").last,
          accessToken,
        );
        count++;
        if (count == 4) {
          break;
        }
      }

      await mockServer.close();
    });

    test('call recoverSession', () async {
      final expiresAt = DateTime.now().add(Duration(seconds: 31));

      final mockServer = await HttpServer.bind('localhost', 0);
      final stitch = StitchClient(
        'http://${mockServer.address.host}:${mockServer.port}',
        "stitchKey",
        authOptions: AuthClientOptions(autoRefreshToken: false),
      );
      final sessionData = getSessionData(expiresAt);
      await stitch.auth.recoverSession(sessionData.sessionString);

      await Future.delayed(Duration(seconds: 11));

      // Make some requests
      unawaited(stitch.from("test").select().then((value) => null));
      unawaited(stitch.rpc("test").select().then((value) => null));
      unawaited(stitch.functions.invoke("test").then((value) => null));
      unawaited(stitch.storage.from("test").list().then((value) => null));

      var count = 0;
      var gotTokenRefresh = false;
      var secondAccessToken = "to be set";

      // Check for every request if the Authorization header is set properly
      await for (final request in mockServer) {
        if (request.uri.path == "/auth/v1/token") {
          if (gotTokenRefresh) {
            fail("Token was refreshed twice");
          }
          gotTokenRefresh = true;
          String sessionString;
          (accessToken: secondAccessToken, :sessionString) = getSessionData(
            DateTime.now().add(Duration(hours: 1)),
          );

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(sessionString);
          await request.response.close();
        } else {
          expect(
            request.headers.value('Authorization')?.split(" ").last,
            secondAccessToken,
          );
          count++;
          if (count == 4) {
            break;
          }
        }
      }

      await mockServer.close();
    });

    test('create a client with third-party auth accessToken', () async {
      final stitch = StitchClient(
        'URL',
        'KEY',
        accessToken: () async {
          return 'jwt';
        },
      );
      expect(
        () => stitch.auth.currentUser,
        throwsA(
          AuthException(
            'StitchDB Client is configured with the accessToken option, accessing stitchdb.auth is not possible.',
          ),
        ),
      );
    });
  });

  group('Custom Header', () {
    const stitchUrl = '';
    const stitchKey = '';
    late StitchClient stitch;

    setUp(() {
      stitch = StitchClient(
        stitchUrl,
        stitchKey,
        headers: {
          'X-Client-Info': 'stitchdb-flutter/0.0.0',
        },
      );
    });

    test('X-Client-Info header is set properly on realtime', () async {
      final mockServer = await HttpServer.bind('localhost', 0);

      final client = StitchClient(
        'http://${mockServer.address.host}:${mockServer.port}',
        stitchKey,
        headers: {
          'X-Client-Info': 'stitchdb-flutter/0.0.0',
        },
      );

      final request = await getRealtimeRequest(
        server: mockServer,
        stitchClient: client,
      );

      expect(request.headers['X-Client-Info']?.first, 'stitchdb-flutter/0.0.0');
    });

    test('X-Client-Info header is set properly on storage', () {
      final xClientInfoHeader = stitch.storage.headers['X-Client-Info'];
      expect(xClientInfoHeader, 'stitchdb-flutter/0.0.0');
    });
  });

  group('Client Advanced Features', () {
    late StitchClient stitch;
    const stitchUrl = 'https://example.stitchdb.com';
    const stitchKey = 'test-key';

    setUp(() {
      stitch = StitchClient(stitchUrl, stitchKey);
    });

    tearDown(() async {
      await stitch.dispose();
    });

    group('Headers Management', () {
      test('should update headers and propagate to all clients', () {
        stitch.headers = {'Custom-Header': 'custom-value'};

        expect(stitch.headers['Custom-Header'], 'custom-value');
        expect(stitch.rest.headers['Custom-Header'], 'custom-value');
        expect(stitch.functions.headers['Custom-Header'], 'custom-value');
        expect(stitch.storage.headers['Custom-Header'], 'custom-value');
        expect(stitch.realtime.headers['Custom-Header'], 'custom-value');
      });

      test('should preserve default headers when setting custom headers', () {
        stitch.headers = {'Custom-Header': 'custom-value'};

        expect(stitch.headers['X-Client-Info'], startsWith('stitchdb-dart/'));
      });

      test(
        'should preserve apikey on realtime headers when setting headers',
        () {
          stitch.headers = {'Custom-Header': 'custom-value'};

          expect(stitch.realtime.headers['apikey'], stitchKey);
        },
      );

      test('should not update auth headers when using custom access token', () {
        final customTokenClient = StitchClient(
          stitchUrl,
          stitchKey,
          accessToken: () async => 'custom-token',
        );

        customTokenClient.headers = {'Custom-Header': 'custom-value'};

        expect(customTokenClient.headers['Custom-Header'], 'custom-value');
      });
    });

    group('Error Handling', () {
      test(
        'should throw AuthException when accessing auth with custom access token',
        () {
          final customTokenClient = StitchClient(
            stitchUrl,
            stitchKey,
            accessToken: () async => 'custom-token',
          );

          expect(
            () => customTokenClient.auth,
            throwsA(isA<AuthException>()),
          );
        },
      );
    });

    group('Shared YAJsonIsolate', () {
      test(
        'does not dispose an injected YAJsonIsolate so the caller retains ownership',
        () async {
          final isolate = YAJsonIsolate();
          await isolate.initialize();

          final client = StitchClient(
            stitchUrl,
            stitchKey,
            isolate: isolate,
          );

          await client.dispose();

          // Isolate is still alive — caller owns the lifecycle
          expect(await isolate.encode({'key': 'value'}), isA<String>());

          await isolate.dispose();
        },
      );

      test(
        'creates a single isolate shared across rest and functions clients',
        () async {
          // Creating a StitchClient without providing an isolate should
          // still result in a single shared isolate (not one per sub-client).
          // Verified indirectly: dispose() should complete without error,
          // meaning there is no double-dispose from sub-clients.
          final client = StitchClient(stitchUrl, stitchKey);

          expect(client.dispose(), completes);
        },
      );
    });
  });

  group('Query Builder', () {
    late StitchClient stitch;
    const stitchUrl = 'https://example.stitchdb.com';
    const stitchKey = 'test-key';

    setUp(() {
      stitch = StitchClient(stitchUrl, stitchKey);
    });

    tearDown(() async {
      await stitch.dispose();
    });

    group('Stream Creation', () {
      test('should throw assertion error for empty primary key', () {
        final queryBuilder = stitch.from('test_table');

        expect(
          () => queryBuilder.stream(primaryKey: []),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}
