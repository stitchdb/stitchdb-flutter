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

## Docs

The docs can be found on the official StitchDB website.

- [Flutter and Dart guide](https://stitchdb.com/docs/sdk/flutter)
- [StitchDB docs](https://stitchdb.com/docs)

## License

This repo is licensed under MIT.

## Credits

Based on MIT-licensed open-source work; see [LICENSE](LICENSE) for the original copyright notices.
