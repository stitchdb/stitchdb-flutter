# StitchDB for Dart

[Guide](https://stitchdb.com/docs/sdk/flutter) · [Documentation](https://stitchdb.com/docs)


<div align="center">

[![pub package](https://img.shields.io/pub/v/stitchdb.svg)](https://pub.dev/packages/stitchdb)

</div>

> **Note**
>
> This is the Dart library for StitchDB, for server-side Dart and other non-Flutter Dart environments.
>
> If you are developing a Flutter application, use [stitchdb_flutter](https://pub.dev/packages/stitchdb_flutter) instead. `stitchdb` package is for non-Flutter Dart environments.

## What is StitchDB

[StitchDB](https://stitchdb.com) is a hosted Postgres platform: every project gets its own Postgres database with authentication, an instant REST API, realtime, file storage and Edge Functions. With this library you can:

- listen to database changes
- query your tables, including filtering, pagination, and deeply nested relationships (like GraphQL)
- create, update, and delete rows
- manage your users and their permissions
- interact with your database using a simple UI

## Offline sync

`offline()` keeps a local copy of the rows the signed-in user may see in the tables that sync (turn a table on in Studio › Database › Offline sync). Reads come from the local copy, writes apply locally at once and are queued; the queue is pushed and changes are pulled whenever the server can be reached (every 30 seconds, after each write, and when you call `sync()`).

```dart
final stitchdb = StitchClient('https://<project>.stitchdb.com', '<anon key>');

final offline = stitchdb.offline(tables: ['todos']);
await offline.ready;

final todos = offline.table('todos');
await todos.upsert({'id': 'a1', 'title': 'Milk', 'done': false}); // works offline too
print(todos.get('a1'));                     // one row by primary key
print(todos.where((t) => t['done'] == false));
todos.stream().listen((rows) => print('${rows.length} todos'));

offline.statusChanges.listen((s) => print('pending ${s.pending}, online ${s.online}'));
offline.conflicts.listen((c) => print('${c.table} ${c.pk}: kept the server row (${c.status})'));

await offline.sync();               // push queued writes, then pull
await offline.close(clear: true);   // e.g. on sign-out
```

A local write wins over pulled changes until it is pushed; if the server rejects it or it loses a conflict, the local copy takes the server row and a `ConflictEvent` is emitted. The default `MemoryOfflineStore` is lost when the process exits; implement `OfflineStore` to persist it (in Flutter, `stitchdb_flutter` ships `SharedPreferencesOfflineStore`).

## Crash reporting

`crashes` reports errors to Studio › Crashes, grouped into issues with the stack trace, your release, the device, the signed-in user and the last API calls and actions before the error ("crashed right after GET /rest/v1/orders returned 500"). Turn crash reporting on for the project in Studio › Crashes first.

```dart
void main() => stitchdb.crashes.runGuarded(() async {   // uncaught errors (sync and async)
  await stitchdb.crashes.start(release: '1.4.0');
  try {
    await checkout();
  } catch (e, s) {
    stitchdb.crashes.captureException(e, stackTrace: s, context: {'step': 'payment'});
  }
  stitchdb.crashes.addBreadcrumb(type: 'ui', message: 'tapped Checkout');
});
```

- Captured: errors you pass to `captureException` (the current stack when you pass none) or `captureMessage`, uncaught errors inside `runGuarded`, every API call of the client as a breadcrumb (method, path, query parameter names without their values, status, error code, duration; no bodies), your own breadcrumbs, the OS, its version and the locale. Passwords, tokens, keys and e-mail addresses are removed by StitchDB before anything is stored.
- Consent: nothing is captured, recorded or sent before `start()`; `stop()` ends it. `beforeSend` sees every report and can change it or return `null` to drop it, for example while the user has not agreed.
- Sending: reports are queued and sent in the background (`await crashes.flush()` to wait). Reports that cannot be sent (offline, the app exiting) are kept in the store and sent on the next `start()`; the default `MemoryCrashStore` loses them when the process exits, so pass `store: FileCrashStore('<directory>')` (dart:io) or your own `CrashStore`. Once a day `start()` also sends a session, used for the crash-free users rate.

## Analytics

`analytics` sends the events your app tracks to Studio › Analytics, linked to the signed-in user (an anonymous id kept on the device before sign-in, merged into the user when they sign in), for active users, funnels, retention and breakdowns by release, platform, OS and country. Turn analytics on for the project in Studio › Analytics first.

```dart
await stitchdb.analytics.start(release: '1.4.0', store: FileAnalyticsStore('<directory>'));
stitchdb.analytics.track('purchase', {'plan': 'pro', 'amount': 29});
await stitchdb.analytics.optOut(); // the user does not want to be tracked
```

- Events: names are letters, digits, `_ $ . : - /` and spaces, up to 64 characters; props are a JSON object of at most 8 KB (flat values are easiest to break down by). Invalid events are dropped with a log message (logger `stitchdb.analytics`). `beforeSend` sees every event and can change it or return `null` to drop it. Passwords, tokens, keys and e-mail addresses are removed by StitchDB before anything is stored.
- Sending: nothing is sent before `start()`; events tracked earlier wait in memory (up to 100). After `start()` events are sent in batches every `flushInterval` (10 s), when 20 are waiting and when the user signs in or out; `await analytics.flush()` sends now. While offline they are kept in the store (up to 1000, the oldest dropped) and sent later; the default `MemoryAnalyticsStore` loses them when the process exits, so pass `FileAnalyticsStore('<directory>')` (dart:io), any `CrashStore`, or your own `AnalyticsStore`. `stop()` stops sending; waiting events stay in the store.
- Consent: `optOut()` deletes the signed-in user's events on the server and stops tracking; it is remembered in the store (`isOptedOut`). `optIn()` tracks again. `anonymousId` is the id of this device before sign-in.
- If analytics is off for the project, the queue is cleared and nothing more is sent until the next `start()`.

## Docs

The docs can be found on the official StitchDB website.

- [Flutter and Dart guide](https://stitchdb.com/docs/sdk/flutter)
- [StitchDB docs](https://stitchdb.com/docs)

## License

This repo is licensed under MIT.

## Credits

Based on MIT-licensed open-source work; see [LICENSE](LICENSE) for the original copyright notices.
