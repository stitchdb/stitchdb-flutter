# StitchDB for Dart and Flutter

Official Dart and Flutter clients for [StitchDB](https://stitchdb.com): Postgres database, auth, storage, realtime and Edge Functions.

| Package | Use |
|---|---|
| [`stitchdb_flutter`](packages/stitchdb_flutter) | Flutter apps (sessions persisted, deep links, OAuth, app lifecycle) |
| [`stitchdb`](packages/stitchdb) | Dart (servers, CLIs, scripts) |
| `stitchdb_auth`, `stitchdb_postgrest`, `stitchdb_realtime`, `stitchdb_storage`, `stitchdb_functions` | The individual clients, used by the two above |

## Flutter

Add it from this repository in `pubspec.yaml` (the overrides point its own packages here too):

```yaml
dependencies:
  stitchdb_flutter:
    git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_flutter }

dependency_overrides:
  stitchdb:           { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb } }
  stitchdb_auth:      { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_auth } }
  stitchdb_common:    { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_common } }
  stitchdb_functions: { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_functions } }
  stitchdb_postgrest: { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_postgrest } }
  stitchdb_realtime:  { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_realtime } }
  stitchdb_storage:   { git: { url: https://github.com/stitchdb/stitchdb-flutter, path: packages/stitchdb_storage } }
```

```dart
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

Future<void> main() async {
  await Stitch.initialize(url: 'https://<project-ref>.p.stitchdb.com', anonKey: '<anon-key>');
  runApp(const MyApp());
}

final stitchdb = Stitch.instance.client;

final todos = await stitchdb.from('todos').select().limit(10);
await stitchdb.auth.signInWithPassword(email: 'ada@example.com', password: 'a-strong-password');
```

## Dart

Same as above with `stitchdb` (path `packages/stitchdb`) under `dependencies`, and the overrides without `stitchdb`.

```dart
import 'package:stitchdb/stitchdb.dart';

final client = StitchClient('https://<project-ref>.p.stitchdb.com', '<anon-key>');
```

Find the project URL and anon key in the dashboard under **Settings → API keys**.

Documentation: https://stitchdb.com/docs/sdk/flutter

## Development

```bash
flutter pub get          # resolves the whole workspace
dart analyze packages
(cd packages/stitchdb && dart test)
(cd packages/stitchdb_flutter && flutter test)
```

## License

MIT. See [LICENSE](LICENSE).
