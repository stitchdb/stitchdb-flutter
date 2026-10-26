<br />
<p align="center">
  <a href="https://stitchdb.com">
    <img alt="StitchDB Logo" width="300" src="https://raw.githubusercontent.com/stitchdb/stitchdb/master/packages/common/assets/images/logo-preview.jpg">
  </a>

  <h1 align="center">stitchdb_flutter</h1>

  <p align="center">
    Flutter client library for <a href="https://stitchdb.com">StitchDB</a>.
  </p>

  <p align="center">
    <a href="https://stitchdb.com/docs">Guides</a>
    ·
    <a href="https://stitchdb.com/docs">Reference Docs</a>
  </p>
</p>

<div align="center">

[![pub package](https://img.shields.io/pub/v/stitchdb_flutter.svg)](https://pub.dev/packages/stitchdb_flutter)

</div>

## Getting Started

Import the package:

```dart
import 'package:stitchdb_flutter/stitchdb_flutter.dart';
```

Initialize `Stitch` before using it:

```dart
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Stitch.initialize(
    url: STITCHDB_URL,
    anonKey: STITCHDB_ANON_KEY,
  );

  runApp(MyApp());
}

// It's handy to then extract the StitchDB client in a variable for later uses
final stitchdb = Stitch.instance.client;
```

## Usage example

* [Authentication](#authentication)
  * [Native Apple Sign in](#native-apple-sign-in)
  * [Native Google sign in](#native-google-sign-in)
  * [OAuth login](#oauth-login)
  * [Passkeys](#passkeys)
* [Database](#database)
* [Realtime](#realtime)
  * [Postgres Changes](#postgres-changes)
  * [Broadcast](#broadcast)
  * [Presence](#presence)
* [Storage](#storage)
* [Edge Functions](#edge-functions)
* [Deep Links](#deep-links)
* [Custom LocalStorage](#custom-localstorage)
- [Logging](#logging)


### <a id="authentication"></a>[Authentication](https://stitchdb.com/docs)

```dart
final stitchdb = Stitch.instance.client;

// Email and password sign up
await stitchdb.auth.signUp(
  email: email,
  password: password,
);

// Email and password login
await stitchdb.auth.signInWithPassword(
  email: email,
  password: password,
);

// Magic link login
await stitchdb.auth.signInWithOtp(email: 'my_email@example.com');

// Listen to auth state changes
stitchdb.auth.onAuthStateChange.listen((data) {
  final AuthChangeEvent event = data.event;
  final Session? session = data.session;
  // Do something when there is an auth event
});
```

#### <a id="native-apple-sign-in"></a>Native Apple Sign in

You can perform Apple sign in using the [sign_in_with_apple](https://pub.dev/packages/sign_in_with_apple) package on Flutter.
Follow the instructions on README of the `sign_in_with_apple` package to setup the native Apple sign in on iOS and macOS.

Once the setup is complete on the Flutter app, add the bundle ID of your app to your StitchDB dashboard under **Authentication → Sign-in methods → Apple** in order to register your app with StitchDB.

```dart
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

/// Performs Apple sign in on iOS or macOS
Future<AuthResponse> signInWithApple() async {
  final rawNonce = stitchdb.auth.generateRawNonce();
  final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

  final credential = await SignInWithApple.getAppleIDCredential(
    scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    nonce: hashedNonce,
  );

  final idToken = credential.identityToken;
  if (idToken == null) {
    throw const AuthException(
        'Could not find ID Token from generated credential.');
  }

  return signInWithIdToken(
    provider: OAuthProvider.apple,
    idToken: idToken,
    nonce: rawNonce,
  );
}
```

#### <a id="native-google-sign-in"></a>Native Google sign in

You can perform native Google sign in on Android and iOS using [google_sign_in](https://pub.dev/packages/google_sign_in).
For platform specific settings, follow the instructions on README of the package.

First, create client IDs for your app. You need to create a web client ID as well to perform Google sign-in with StitchDB.

- [Steps to obtain web client ID](https://developers.google.com/identity/sign-in/android/start-integrating#configure_a_project)
- [Steps to obtain Android client ID](https://developers.google.com/identity/sign-in/android/start-integrating#configure_a_project)
- [Steps to obtain iOS client ID](https://developers.google.com/identity/sign-in/ios/start-integrating#get_an_oauth_client_id)

Once you have registered your app and created the client IDs, add the web client ID in your StitchDB dashboard under **Authentication → Sign-in methods → Google**. Also turn on the `Skip nonce check` option, which will enable Google sign-in on iOS.

At this point you can perform native Google sign in using the following code. Be sure to replace the `webClientId` and `iosClientId` with your own.

The following example is very basic. Please refer to the [google_sign_in](https://pub.dev/packages/google_sign_in) package for the correct details.

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

...

Future<AuthResponse> _googleSignIn() async {
  /// TODO: update the Web client ID with your own.
  ///
  /// Web Client ID that you registered with Google Cloud.
  const webClientId = 'my-web.apps.googleusercontent.com';

  /// TODO: update the iOS client ID with your own.
  ///
  /// iOS Client ID that you registered with Google Cloud.
  const iosClientId = 'my-ios.apps.googleusercontent.com';

  // Google sign in on Android will work without providing the Android
  // Client ID registered on Google Cloud.

  final GoogleSignIn signIn = GoogleSignIn.instance;

  // At the start of your app, initialize the GoogleSignIn instance
  unawaited(
    signIn.initialize(clientId: iosClientId, serverClientId: webClientId));

  // Perform the sign in
  final googleAccount = await signIn.authenticate();
  final googleAuthorization = await googleAccount.authorizationClient.authorizationForScopes([]);
  final googleAuthentication = googleAccount!.authentication;
  final idToken = googleAuthentication.idToken;
  final accessToken = googleAuthorization.accessToken;

  if (idToken == null) {
    throw 'No ID Token found.';
  }

  return stitchdb.auth.signInWithIdToken(
    provider: OAuthProvider.google,
    idToken: idToken,
    accessToken: accessToken,
  );
}
...
```

#### <a id="native-facebook-sign-in"></a>Native Facebook sign in

You can use [flutter_facebook_auth](https://pub.dev/packages/flutter_facebook_auth) `^7.1.7` with `signInWithIdToken` on both iOS and Android.

- **iOS** uses Facebook's [Limited Login](https://developers.facebook.com/docs/facebook-login/limited-login/) (`LoginTracking.limited`), which returns a `LimitedToken` containing an OIDC ID token directly.
- **Android** requires `LoginBehavior.webOnly` and the `openid` permission to receive an OIDC ID token in `ClassicToken.authenticationToken`.

```dart
import 'dart:io';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

Future<AuthResponse> _facebookSignIn() async {
  late final LoginResult result;

  if (Platform.isIOS) {
    result = await FacebookAuth.instance.login(
      permissions: ['public_profile', 'email'],
      loginTracking: LoginTracking.limited,
    );
  } else {
    // Android: webOnly behavior with openid scope returns an OIDC ID token.
    result = await FacebookAuth.instance.login(
      permissions: ['public_profile', 'email', 'openid'],
      loginBehavior: LoginBehavior.webOnly,
    );
  }

  if (result.status != LoginStatus.success) {
    throw 'Facebook sign in failed: ${result.message}';
  }

  final accessToken = result.accessToken;
  final String idToken;

  if (accessToken is LimitedToken) {
    idToken = accessToken.tokenString;
  } else if (accessToken is ClassicToken) {
    final authToken = accessToken.authenticationToken;
    if (authToken == null) {
      throw 'No ID token returned. Make sure to use LoginBehavior.webOnly and include the openid scope on Android.';
    }
    idToken = authToken;
  } else {
    throw 'Unexpected Facebook token type: ${accessToken?.runtimeType}';
  }

  return Stitch.instance.client.auth.signInWithIdToken(
    provider: OAuthProvider.facebook,
    idToken: idToken,
  );
}
```

Alternatively, if you do not want to use the native Facebook SDK, you can use the web-based `signInWithOAuth()` method. This will open the device's web browser to perform the classic Facebook OAuth 2.0 login flow.

```dart
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

Future<void> _facebookSignInWeb() async {
  await Stitch.instance.client.auth.signInWithOAuth(
    OAuthProvider.facebook,
    redirectTo: 'io.stitchdb.flutterdemo://login-callback',
  );
}
```

### <a id="oauth-login"></a>OAuth login

The `signInWithIdToken()` method supports providers like Apple, Google, Facebook, Kakao, and Keycloak. For other providers, you need to use the `signInWithOAuth()` method to perform OAuth login. This will open the web browser to perform the OAuth login.

Use the `redirectTo` parameter to redirect the user to a deep link to bring the user back to the app. Learn more about setting up deep links in [Deep link config](#deep-link-config).

```dart
// Perform web based OAuth login
await stitchdb.auth.signInWithOAuth(
  OAuthProvider.github,
  redirectTo: kIsWeb ? null : 'io.stitchdb.flutter://callback',
);

// Listen to auth state changes in order to detect when the OAuth login is complete.
stitchdb.auth.onAuthStateChange.listen((data) {
  final AuthChangeEvent event = data.event;
  if(event == AuthChangeEvent.signedIn) {
    // Do something when user sign in
  }
});
```

### <a id="passkeys"></a>Passkeys

> Enable passkeys for your project in the StitchDB dashboard under **Authentication → Sign-in methods → Passkeys** before using these methods.

`stitchdb_flutter` performs the server side of the WebAuthn ceremony for you and delegates the platform prompt (FaceID/TouchID/security key) to an authenticator you supply. This keeps `stitchdb_flutter` free of a passkey plugin dependency, so apps that do not use passkeys are not forced to raise their minimum platform versions.

Add a passkey plugin to your own app and pass its authenticator in. The [`passkeys`](https://pub.dev/packages/passkeys) plugin's `PasskeyAuthenticator` implements the `PasskeyAuthenticatorInterface` these methods expect (since `passkeys` `2.21.0`), but you can pass any implementation of that interface.

```dart
import 'package:passkeys/authenticator.dart';

final authenticator = PasskeyAuthenticator();

// Sign in with a passkey. The user is prompted to pick and unlock a passkey.
await stitchdb.auth.signInWithPasskey(authenticator);

// Register a new passkey for the signed in user.
await stitchdb.auth.registerPasskey(authenticator);

// Manage the signed in user's passkeys with the server side API.
final passkeys = await stitchdb.auth.passkey.list();
await stitchdb.auth.passkey.update(passkeyId: passkeys.first.id, friendlyName: 'My phone');
await stitchdb.auth.passkey.delete(passkeyId: passkeys.first.id);
```

The platform ceremony is handled by whichever plugin you add. Refer to your plugin's documentation, for example the [`passkeys` package documentation](https://pub.dev/packages/passkeys), for its platform requirements, setup, and how to handle ceremony failures such as the user cancelling.

### <a id="database"></a>[Database](https://stitchdb.com/docs)

Database methods are used to perform basic CRUD operations using the StitchDB REST API. Full list of supported operators can be found [here](https://stitchdb.com/docs).

```dart
// Select data with filters
final data = await stitchdb
  .from('cities')
  .select()
  .eq('country_id', 1) // equals filter
  .neq('name', 'The shire'); // does not equal filter

// Insert a new row
await stitchdb
  .from('cities')
  .insert({'name': 'The Shire', 'country_id': 554});
```

### <a id="realtime"></a>[Realtime](https://stitchdb.com/docs)

#### Realtime data as `Stream`

To receive realtime updates, you have to first enable Realtime on from your StitchDB console. You can read more [here](https://stitchdb.com/docs) on how to enable it.

> **Warning**
> When using `stream()` with a `StreamBuilder`, make sure to persist the stream value as a variable in a `StatefulWidget` instead of directly constructing the stream within your widget tree, which could cause rapid rebuilds that will lead to losing realtime connection.

```dart
class MyWidget extends StatefulWidget {
  const MyWidget({Key? key}) : super(key: key);

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // Persisting the future as local variable to prevent refetching upon rebuilds.
  final stream = stitchdb.from('countries').stream(primaryKey: ['id']);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        // return your widget with the data from snapshot
      },
    );
  }
}
```

#### <a id="postgres-changes"></a>[Postgres Changes](https://stitchdb.com/docs)

You can get notified whenever there is a change in your StitchDB tables.

```dart
final myChannel = stitchdb.channel('my_channel');

myChannel
    .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'countries',
      callback: (payload) {
        // Do something fun or interesting when there is an change on the database
      },
    )
    .subscribe();
```

#### <a id="broadcast"></a>[Broadcast](https://stitchdb.com/docs)

Broadcast lets you send and receive low latency messages between connected clients by bypassing the database.

```dart
final myChannel = stitchdb.channel('my_channel');

// Subscribe to `cursor-pos` broadcast event
final myChannel = stitchdb.channel('my_channel');

myChannel
    .onBroadcast(event: 'cursor-pos', callback: (payload) {}
        // Do something fun or interesting when there is an change on the database
        )
    .subscribe();

// Send a broadcast message to other connected clients
await myChannel.sendBroadcastMessage(
  event: 'cursor-pos',
  payload: {'x': 30, 'y': 50},
);
```

### <a id="presence"></a>[Presence](https://stitchdb.com/docs)

Presence let's you easily create "I'm online" feature.

```dart
final myChannel = stitchdb.channel('my_channel');

// Subscribe to presence events
myChannel
    .onPresence(
        event: PresenceEvent.sync,
        callback: (payload) {
          final onlineUsers = myChannel.presenceState();
          // handle sync event
        })
    .onPresence(
        event: PresenceEvent.join,
        callback: (payload) {
          // New users have joined
        })
    .onPresence(
        event: PresenceEvent.leave,
        callback: (payload) {
          // Users have left
        })
    .subscribe(((status, [_]) async {
  if (status == RealtimeSubscribeStatus.subscribed) {
    // Send the current user's state upon subscribing
    final status = await myChannel
        .track({'online_at': DateTime.now().toIso8601String()});
  }
}));
```

#### <a id="realtime-app-lifecycle"></a>Realtime and the app lifecycle

`StitchDB` disconnects the realtime socket when the app is paused and reconnects it, rejoining every joined channel, when the app is resumed. Every reconnect costs a new socket and a fresh authorization of each channel.

On iOS a full-screen view such as a video ad or a system sheet reports the app as paused while it is on screen. Pass `RealtimeLifecycleOptions` to keep the socket open through pauses shorter than a grace period:

```dart
await Stitch.initialize(
  url: stitchUrl,
  anonKey: stitchAnonKey,
  realtimeLifecycleOptions: const RealtimeLifecycleOptions(
    disconnectAfterPause: Duration(minutes: 1),
  ),
);
```

Use `RealtimeLifecycleOptions.manual()` to keep the socket out of the app lifecycle entirely. The socket then stays open in the background until the operating system closes it, and the realtime client reconnects and rejoins its channels by itself once the app runs again.

### <a id="storage"></a>[Storage](https://stitchdb.com/docs)

```dart
final file = File('example.txt');
file.writeAsStringSync('File content');
await stitchdb.storage
  .from('my_bucket')
  .upload('my/path/to/files/example.txt', file);

// Use the `uploadBinary` method to upload files on Flutter web
await stitchdb.storage
  .from('my_bucket')
  .uploadBinary('my/path/to/files/example.txt', file.readAsBytesSync());
```

### <a id="edge-functions"></a>[Edge Functions](https://stitchdb.com/docs/functions)

```dart
final data = await stitchdb.functions.invoke('get_countries');
```

### <a id="crash-reporting"></a>Crash reporting

Errors are reported to Studio › Crashes, grouped into issues with the stack trace, your release, the device, the signed-in user and the last API calls and actions before the error. Turn crash reporting on for the project in Studio › Crashes, then start it once, after `Stitch.initialize`:

```dart
await Stitch.initialize(url: '...', anonKey: '...');
final stitchdb = Stitch.instance.client;

await stitchdb.crashes.start(
  release: '1.4.0',
  beforeSend: (report) => userAgreed ? report : null, // consent
);

try {
  await checkout();
} catch (e, s) {
  stitchdb.crashes.captureException(e, stackTrace: s, context: {'step': 'payment'});
}
stitchdb.crashes.addBreadcrumb(type: 'navigation', message: '/checkout');
```

- Captured: uncaught errors from `FlutterError.onError` (build, layout, paint) and `PlatformDispatcher.instance.onError` (uncaught async errors) unless `captureUnhandled: false`; handlers set before `start()` keep being called. Also errors you pass to `captureException` or `captureMessage`, every API call of the client as a breadcrumb (method, path, query parameter names without values, status, error code, duration; no bodies), your own breadcrumbs, and the OS, its version, the locale and the screen size. Passwords, tokens, keys and e-mail addresses are removed by StitchDB before anything is stored.
- Consent: nothing is captured, recorded or sent before `start()`; `stop()` ends it and removes the handlers. `beforeSend` sees every report and can change it or return `null` to drop it.
- Sending: reports are kept in SharedPreferences until they are sent, in the background. Reports from a crash, or while the device is offline, are sent on the next launch, when `start()` is called again. Once a day `start()` also sends a session, used for the crash-free users rate.

For a `StitchClient` you create yourself, call `configureFlutterCrashes(client)` before `client.crashes.start()`.

## <a id="deep-links"></a>Deep links

### Why do you need to setup deep links

You need to setup deep links if you want your native app to open when a user clicks on a link. User clicking on a link and the app opens up happens in a few scenarios when you use StitchDB auth, and in order to support those scenarios, you need to setup deep links.

### When do you need to setup deep links

- Magic link login
- Have `confirm email` enabled and are using email login
- Resetting password for email login
- Calling `.signInWithOAuth()` method

\*Currently stitchdb_flutter supports deep links on Android, iOS, Web, MacOS and Windows.

### Dashboard Deep link config

- In the StitchDB dashboard, open your project's **Authentication → URL configuration** page.
- Add your app's redirect callback under **Redirect URLs**.

The redirect callback url should have this format `[YOUR_SCHEME]://[YOUR_HOSTNAME]`. Here, `io.stitchdb.flutterdemo://login-callback` is just an example, you can choose whatever you would like for `YOUR_SCHEME` and `YOUR_HOSTNAME` as long as the scheme is unique across the user's device. For this reason, typically a reverse domain of your website is used.


### Flutter Deep link config

stitchdb_flutter uses [app_link](https://pub.dev/packages/app_links) internally to handle deep links. You can find the platform specific config to setup deep links in the following.

https://github.com/llfbandit/app_links/tree/master?tab=readme-ov-file#getting-started

### Platform specific config

Follow the guide to find additional platform specific configs for your OAuth provider.

https://stitchdb.com/docs

## <a id="custom-localstorage"></a>Custom LocalStorage

As default, `stitchdb_flutter` uses [`Shared preferences`](https://pub.dev/packages/shared_preferences) to persist the user session.

However, you can use any other methods by creating a `LocalStorage` implementation. For example, we can use [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) plugin to store the user session in a secure storage.

```dart
// Define the custom LocalStorage implementation
class MySecureStorage extends LocalStorage {

  final storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    return storage.read(key: stitchPersistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    return storage.containsKey(key: stitchPersistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    return storage.write(key: stitchPersistSessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    return storage.delete(key: stitchPersistSessionKey);
  }
}

// use it when initializing
Stitch.initialize(
  ...
  authOptions: FlutterAuthClientOptions(
    localStorage: MySecureStorage(),
  ),
);
```

You can also use `EmptyLocalStorage` to disable session persistence:

```dart
Stitch.initialize(
  // ...
  authOptions: FlutterAuthClientOptions(
    localStorage: const EmptyLocalStorage(),
  ),
);
```

### Persisting the user session from stitchdb_flutter v1

stitchdb_flutter v1 used hive to persist the user session. In the current version of stitchdb_flutter it uses shared_preferences. If you are updating your app from v1 to v2, you can use the following custom `LocalStorage` implementation to automatically migrate the user session from [hive](https://pub.dev/packages/hive) to [shared_preferences](https://pub.dev/packages/shared_preferences).

```dart
const _hiveBoxName = 'stitch_authentication';

class MigrationLocalStorage extends LocalStorage {
  final SharedPreferencesLocalStorage sharedPreferencesLocalStorage;
  late final HiveLocalStorage hiveLocalStorage;

  MigrationLocalStorage({required String persistSessionKey})
      : sharedPreferencesLocalStorage =
            SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);

  @override
  Future<void> initialize() async {
    await Hive.initFlutter('auth');
    hiveLocalStorage = const HiveLocalStorage();
    await sharedPreferencesLocalStorage.initialize();
    try {
      await migrate();
    } on TimeoutException {
      // Ignore TimeoutException thrown by Hive methods
      // https://github.com/stitchdb/stitchdb-flutter
    }
  }

  @visibleForTesting
  Future<void> migrate() async {
    // Migrate from Hive to SharedPreferences
    if (await Hive.boxExists(_hiveBoxName)) {
      await hiveLocalStorage.initialize();

      final hasHive = await hiveLocalStorage.hasAccessToken();
      if (hasHive) {
        final accessToken = await hiveLocalStorage.accessToken();
        final session =
            Session.fromJson(jsonDecode(accessToken!)['currentSession']);
        if (session == null) {
          return;
        }
        await sharedPreferencesLocalStorage
            .persistSession(jsonEncode(session.toJson()));
        await hiveLocalStorage.removePersistedSession();
      }
      if (Hive.box(_hiveBoxName).isEmpty) {
        final boxPath = Hive.box(_hiveBoxName).path;
        await Hive.deleteBoxFromDisk(_hiveBoxName);

        //Delete `auth` folder if it's empty
        if (!kIsWeb && boxPath != null) {
          final boxDir = File(boxPath).parent;
          final dirIsEmpty = await boxDir.list().length == 0;
          if (dirIsEmpty) {
            await boxDir.delete();
          }
        }
      }
    }
  }

  @override
  Future<String?> accessToken() {
    return sharedPreferencesLocalStorage.accessToken();
  }

  @override
  Future<bool> hasAccessToken() {
    return sharedPreferencesLocalStorage.hasAccessToken();
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return sharedPreferencesLocalStorage.persistSession(persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return sharedPreferencesLocalStorage.removePersistedSession();
  }
}

/// A [LocalStorage] implementation that implements Hive as the
/// storage method.
class HiveLocalStorage extends LocalStorage {
  /// Creates a LocalStorage instance that implements the Hive Database
  const HiveLocalStorage();

  /// The encryption key used by Hive. If null, the box is not encrypted
  ///
  /// This value should not be redefined in runtime, otherwise the user may
  /// not be fetched correctly
  ///
  /// See also:
  ///
  ///   * <https://docs.hivedb.dev/#/advanced/encrypted_box?id=encrypted-box>
  static String? encryptionKey;

  @override
  Future<void> initialize() async {
    HiveCipher? encryptionCipher;
    if (encryptionKey != null) {
      encryptionCipher = HiveAesCipher(base64Url.decode(encryptionKey!));
    }
    await Hive.initFlutter('auth');
    await Hive.openBox(_hiveBoxName, encryptionCipher: encryptionCipher)
        .timeout(const Duration(seconds: 1));
  }

  @override
  Future<bool> hasAccessToken() {
    return Future.value(
      Hive.box(_hiveBoxName).containsKey(
        stitchPersistSessionKey,
      ),
    );
  }

  @override
  Future<String?> accessToken() {
    return Future.value(
      Hive.box(_hiveBoxName).get(stitchPersistSessionKey) as String?,
    );
  }

  @override
  Future<void> removePersistedSession() {
    return Hive.box(_hiveBoxName).delete(stitchPersistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    // Flush after X amount of writes
    return Hive.box(_hiveBoxName)
        .put(stitchPersistSessionKey, persistSessionString);
  }
}
```

You can then initialize StitchDB with `MigrationLocalStorage` and it will automatically migrate the session from Hive to SharedPreferences.

```dart
Stitch.initialize(
  // ...
  authOptions: FlutterAuthClientOptions(
    localStorage: const MigrationLocalStorage(
      persistSessionKey:
              "stitchdb-${Uri.parse(url).host.split(".").first}-auth-token",
    ),
  ),
);
```

## Logging

All StitchDB packages use the [logging](https://pub.dev/packages/logging) package to log information. Each sub-package has its own logger instance. You can listen to logs and set custom log levels for each logger.

In debug mode, or depending on the value for `debug` from `Stitch.initialize()`, records with `Level.INFO` and above are printed to the console.

Records containing sensitive data like access tokens and which requests are made are logged with `Level.FINEST`, so you can handle them accordingly.

### Listen to all StitchDB logs

```dart
import 'package:logging/logging.dart';

final stitchLogger = Logger('stitchdb');
stitchLogger.level = Level.ALL; // custom log level filtering, default is Level.INFO
stitchLogger.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
});
```

### Sub-package loggers

- `stitchdb_flutter`: `Logger('stitchdb.stitchdb_flutter')`
- `stitchdb`: `Logger('stitchdb.stitchdb')`
- `postgrest`: `Logger('stitchdb.postgrest')`
- `stitchdb-auth`: `Logger('stitchdb.auth')`
- `stitchdb_realtime`: `Logger('stitchdb.realtime')`
- `stitchdb_storage`: `Logger('stitchdb.storage')`
- `stitchdb_functions`: `Logger('stitchdb.functions')`

---

## Migrating Guide

You can find the migration guide to migrate from v1 to v2 here:
https://stitchdb.com/docs

## Contributing

- Fork the repo on [GitHub](https://github.com/stitchdb/stitchdb-flutter)
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull request so that we can review your changes and merge

## License

This repo is licensed under MIT.

## Resources

- [Quickstart: Flutter](https://stitchdb.com/docs)
