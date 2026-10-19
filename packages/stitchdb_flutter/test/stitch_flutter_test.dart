import 'package:flutter_test/flutter_test.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

import 'widget_test_stubs.dart';

void main() {
  const stitchUrl = '';
  const stitchKey = '';
  tearDown(() async => await Stitch.instance.dispose());

  group("Initialize", () {
    setUp(() async {
      mockAppLink();
      // Initialize the StitchDB singleton
      await Stitch.initialize(
        url: stitchUrl,
        anonKey: stitchKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: const MockLocalStorage(),
          pkceAsyncStorage: MockAsyncStorage(),
        ),
      );
    });

    test('can access StitchDB singleton', () {
      final stitch = Stitch.instance.client;

      expect(stitch, same(Stitch.instance.client));
    });

    test('can re-initialize client', () async {
      final stitch = Stitch.instance.client;
      await Stitch.instance.dispose();
      await Stitch.initialize(
        url: stitchUrl,
        anonKey: stitchKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: const MockLocalStorage(),
          pkceAsyncStorage: MockAsyncStorage(),
        ),
      );

      final newClient = Stitch.instance.client;
      expect(stitch, isNot(newClient));
    });
  });

  test('with custom access token', () async {
    final stitch = await Stitch.initialize(
      url: stitchUrl,
      anonKey: stitchUrl,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: const MockLocalStorage(),
        pkceAsyncStorage: MockAsyncStorage(),
      ),
      accessToken: () async => 'my-access-token',
    );

    expect(() => stitch.client.auth, throwsA(isA<AuthException>()));
  });

  group("Expired session", () {
    setUp(() async {
      mockAppLink();
      await Stitch.initialize(
        url: stitchUrl,
        anonKey: stitchKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: const MockExpiredStorage(),
          pkceAsyncStorage: MockAsyncStorage(),
          autoRefreshToken: false,
        ),
      );
    });

    test('emits exception when no auto refresh', () async {
      // Give it a delay to wait for recoverSession to throw
      await Future.delayed(const Duration(milliseconds: 100));

      await expectLater(
        Stitch.instance.client.auth.onAuthStateChange,
        emitsError(isA<AuthException>()),
      );
    });
  });

  group("No session", () {
    setUp(() async {
      mockAppLink();
      await Stitch.initialize(
        url: stitchUrl,
        anonKey: stitchKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: const MockEmptyLocalStorage(),
          pkceAsyncStorage: MockAsyncStorage(),
        ),
      );
    });

    test('initial session contains the error', () async {
      final event = await Stitch.instance.client.auth.onAuthStateChange.first;
      expect(event.event, AuthChangeEvent.initialSession);
      expect(event.session, isNull);
    });
  });

  group('EmptyLocalStorage', () {
    late EmptyLocalStorage localStorage;

    setUp(() async {
      mockAppLink();

      localStorage = const EmptyLocalStorage();
      // Initialize the StitchDB singleton
      await Stitch.initialize(
        url: stitchUrl,
        anonKey: stitchKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: localStorage,
          pkceAsyncStorage: MockAsyncStorage(),
        ),
      );
    });

    test('all methods work together in a typical flow', () async {
      // Initialize the storage
      await localStorage.initialize();

      // Check if there's a token (should be false)
      final hasToken = await localStorage.hasAccessToken();
      expect(hasToken, isFalse);

      // Get the token (should be null)
      final token = await localStorage.accessToken();
      expect(token, isNull);

      // Try to persist a session
      await localStorage.persistSession('test-session-data');

      // Check if there's a token after persisting (should still be false)
      final hasTokenAfterPersist = await localStorage.hasAccessToken();
      expect(hasTokenAfterPersist, isFalse);

      // Get the token after persisting (should still be null)
      final tokenAfterPersist = await localStorage.accessToken();
      expect(tokenAfterPersist, isNull);

      // Try to remove the session
      await localStorage.removePersistedSession();

      // Check if there's a token after removing (should still be false)
      final hasTokenAfterRemove = await localStorage.hasAccessToken();
      expect(hasTokenAfterRemove, isFalse);
    });
  });
}
