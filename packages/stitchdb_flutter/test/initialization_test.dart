import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

import 'widget_test_stubs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const stitchUrl = '';
  const stitchKey = '';

  setUpAll(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  group('StitchDB initialization', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockAppLink();
    });

    tearDown(() async {
      try {
        await Stitch.instance.dispose();
      } catch (_) {
        // Ignore dispose errors
      }
    });

    group('Basic initialization', () {
      test('initialize successfully with default options', () {
        expect(
          Stitch.initialize(
            url: stitchUrl,
            anonKey: stitchKey,
            debug: false,
          ),
          completes,
        );
      });
    });

    group('Custom storage initialization', () {
      test('initialize successfully with custom localStorage', () {
        const localStorage = MockLocalStorage();
        expect(
          Stitch.initialize(
            url: stitchUrl,
            anonKey: stitchKey,
            debug: false,
            authOptions: const FlutterAuthClientOptions(
              localStorage: localStorage,
            ),
          ),
          completes,
        );
      });

      test('handles initialization with expired session in storage', () async {
        await Stitch.initialize(
          url: stitchUrl,
          anonKey: stitchKey,
          debug: true,
          authOptions: FlutterAuthClientOptions(
            localStorage: const MockExpiredStorage(),
            pkceAsyncStorage: MockAsyncStorage(),
          ),
        );

        // Should handle expired session gracefully
        expect(Stitch.instance.client.auth.currentSession, isNotNull);
      });
    });

    group('Auth options initialization', () {
      test('initialize successfully with PKCE auth flow', () {
        expect(
          Stitch.initialize(
            url: stitchUrl,
            anonKey: stitchKey,
            debug: false,
            authOptions: const FlutterAuthClientOptions(
              authFlowType: AuthFlowType.pkce,
            ),
          ),
          completes,
        );
      });
    });

    group('Custom client initialization', () {
      test('initialize successfully with custom HTTP client', () {
        final httpClient = PkceHttpClient();
        expect(
          Stitch.initialize(
            url: stitchUrl,
            anonKey: stitchKey,
            debug: false,
            httpClient: httpClient,
          ),
          completes,
        );
      });

      test('initialize successfully with custom access token', () async {
        await Stitch.initialize(
          url: stitchUrl,
          anonKey: stitchKey,
          debug: false,
          accessToken: () async => 'custom-access-token',
        );

        // Should throw AuthException when trying to access auth
        expect(
          () => Stitch.instance.client.auth,
          throwsA(isA<AuthException>()),
        );
      });
    });

    group('Multiple initialization and disposal', () {
      test('dispose and reinitialize works', () async {
        // First initialization
        await Stitch.initialize(
          url: stitchUrl,
          anonKey: stitchKey,
          debug: false,
        );

        // Dispose
        await Stitch.instance.dispose();

        // Need to run the event loop to let the dispose complete
        await Future.delayed(Duration.zero);

        // Re-initialize should work without errors
        await Stitch.initialize(
          url: stitchUrl,
          anonKey: stitchKey,
          debug: false,
        );
      });

      test('handles multiple initializations correctly', () async {
        await Stitch.initialize(
          url: stitchUrl,
          anonKey: stitchKey,
          debug: false,
          authOptions: FlutterAuthClientOptions(
            localStorage: const MockLocalStorage(),
            pkceAsyncStorage: MockAsyncStorage(),
          ),
        );

        // Store first instance to verify it's different after re-initialization
        final firstInstance = Stitch.instance.client;

        // Dispose first instance before re-initializing
        await Stitch.instance.dispose();

        await Stitch.initialize(
          url: stitchUrl,
          anonKey: stitchKey,
          debug: true,
          authOptions: FlutterAuthClientOptions(
            localStorage: const MockEmptyLocalStorage(),
            pkceAsyncStorage: MockAsyncStorage(),
          ),
        );

        final secondInstance = Stitch.instance.client;
        expect(identical(firstInstance, secondInstance), isFalse);
      });
    });
  });
}
