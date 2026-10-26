import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

import 'version.dart';

/// A [CrashStore] that keeps unsent crash reports, the install id and the
/// last session day in SharedPreferences, so reports from a crash are sent on
/// the next launch. `Stitch.initialize` uses it by default.
///
/// Every key is prefixed with [name].
class SharedPreferencesCrashStore implements CrashStore {
  /// Prefix of every key this store writes.
  final String name;

  Future<SharedPreferences>? _prefs;
  SharedPreferences? _loaded;

  SharedPreferencesCrashStore({this.name = 'stitchdb-crashes'});

  Future<SharedPreferences> get _p => _prefs ??= () async {
    WidgetsFlutterBinding.ensureInitialized();
    return _loaded = await SharedPreferences.getInstance();
  }();

  String get _prefix => '$name/';

  @override
  Future<String?> get(String key) async => (await _p).getString(_prefix + key);

  @override
  Future<void> set(String key, String? value) async {
    final p = await _p;
    if (value == null) {
      await p.remove(_prefix + key);
    } else {
      await p.setString(_prefix + key, value);
    }
  }

  @override
  void setNow(String key, String? value) {
    // SharedPreferences updates its cache at once and hands the write to the
    // platform right away; it cannot block until the write is on disk.
    final p = _loaded;
    if (p == null) {
      unawaited(set(key, value));
    } else if (value == null) {
      unawaited(p.remove(_prefix + key));
    } else {
      unawaited(p.setString(_prefix + key, value));
    }
  }
}

/// Device info sent with crash reports from Flutter apps (no plugins needed).
@internal
Map<String, dynamic> flutterCrashDevice() {
  final dispatcher = ui.PlatformDispatcher.instance;
  final d = <String, dynamic>{
    'os': kIsWeb ? 'web' : (conditionalPlatform ?? defaultTargetPlatform.name),
    'os_version': ?conditionalPlatformVersion,
    'runtime': 'flutter',
    'dart_version': ?conditionalRuntimeVersion,
    'build_mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
  };
  try {
    d['locale'] = dispatcher.locale.toLanguageTag();
  } catch (_) {}
  try {
    final view = dispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    d['screen'] = '${size.width.round()}x${size.height.round()}';
  } catch (_) {}
  return d;
}

/// Reports errors from `FlutterError.onError` (build, layout, paint) and
/// `PlatformDispatcher.instance.onError` (uncaught async errors) as crashes,
/// then hands them on to the handlers that were set before. Returns a
/// function that puts those handlers back.
@internal
void Function() hookFlutterErrors(CrashesClient crashes) {
  final previousFlutterError = FlutterError.onError;
  void onFlutterError(FlutterErrorDetails details) {
    crashes.captureException(
      details.exception,
      stackTrace: details.stack ?? StackTrace.empty,
      handled: false,
      mechanism: 'FlutterError.onError',
      context: {
        'library': ?details.library,
        if (details.context != null) 'during': details.context.toString(),
      },
    );
    previousFlutterError?.call(details);
  }

  FlutterError.onError = onFlutterError;

  final dispatcher = ui.PlatformDispatcher.instance;
  final previousOnError = dispatcher.onError;
  bool onPlatformError(Object error, StackTrace stackTrace) {
    crashes.captureException(
      error,
      stackTrace: stackTrace,
      handled: false,
      mechanism: 'PlatformDispatcher.onError',
    );
    return previousOnError?.call(error, stackTrace) ?? false;
  }

  dispatcher.onError = onPlatformError;

  return () {
    if (FlutterError.onError == onFlutterError) {
      FlutterError.onError = previousFlutterError;
    }
    if (dispatcher.onError == onPlatformError) {
      dispatcher.onError = previousOnError;
    }
  };
}

/// Makes [client.crashes] report as a Flutter app: platform `flutter`, device
/// info, a SharedPreferences store named [storeName] and, with
/// `start(captureUnhandled: true)`, the Flutter error handlers.
/// `Stitch.initialize` does this for its client; call it for a
/// [StitchClient] you create yourself.
void configureFlutterCrashes(
  StitchClient client, {
  String storeName = 'stitchdb-crashes',
}) {
  client.crashes.configure(
    platform: 'flutter',
    sdk: 'stitchdb-flutter/$version',
    store: SharedPreferencesCrashStore(name: storeName),
    device: flutterCrashDevice,
    unhandled: hookFlutterErrors,
  );
}
