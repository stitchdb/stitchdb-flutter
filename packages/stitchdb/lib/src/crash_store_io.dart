import 'dart:io';

import 'crashes.dart';

/// A [CrashStore] that keeps queued reports, the install id and the last
/// session day as files in [directory], so reports from a crash are sent on
/// the next start. Writes made while the app crashes are synchronous.
///
/// ```dart
/// await stitchdb.crashes.start(
///   release: '1.4.0',
///   store: FileCrashStore('${Directory.systemTemp.path}/my-app-crashes'),
/// );
/// ```
class FileCrashStore implements CrashStore {
  /// The directory that holds the files; created when needed.
  final String directory;

  FileCrashStore(this.directory);

  File _file(String key) => File('$directory/$key.json');

  @override
  Future<String?> get(String key) async {
    try {
      final f = _file(key);
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> set(String key, String? value) async {
    try {
      final f = _file(key);
      if (value == null) {
        if (await f.exists()) await f.delete();
        return;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(value, flush: true);
    } catch (_) {
      // read-only or full disk: the report is lost
    }
  }

  @override
  void setNow(String key, String? value) {
    try {
      final f = _file(key);
      if (value == null) {
        if (f.existsSync()) f.deleteSync();
        return;
      }
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(value, flush: true);
    } catch (_) {
      // read-only or full disk: the report is lost
    }
  }
}

/// The locale of the device, e.g. `de_DE`.
String? crashLocale() {
  try {
    return Platform.localeName;
  } catch (_) {
    return null;
  }
}
