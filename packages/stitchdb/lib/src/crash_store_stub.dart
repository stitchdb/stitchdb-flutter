import 'analytics.dart';
import 'crashes.dart';

/// A [CrashStore] that keeps its data as files. Files are not available on
/// this platform (web): use [MemoryCrashStore] or your own [CrashStore].
class FileCrashStore implements CrashStore {
  /// The directory that would hold the files.
  final String directory;

  FileCrashStore(this.directory) {
    throw UnsupportedError('FileCrashStore needs dart:io');
  }

  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String? value) async {}

  @override
  void setNow(String key, String? value) {}
}

/// The locale of the device; unknown without dart:io.
String? crashLocale() => null;

/// An [AnalyticsStore] that keeps its data as files. Files are not available
/// on this platform (web): use [MemoryAnalyticsStore] or your own
/// [AnalyticsStore].
class FileAnalyticsStore extends FileCrashStore {
  FileAnalyticsStore(super.directory);
}
