import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:stitchdb/stitchdb.dart';

import 'crash_reporting.dart';

/// An [AnalyticsStore] that keeps waiting analytics events, the anonymous id
/// and the opt-out in SharedPreferences, so events tracked while offline are
/// sent after the app is killed and launched again. `Stitch.initialize` uses
/// it by default.
///
/// Every key is prefixed with [name].
class SharedPreferencesAnalyticsStore extends SharedPreferencesCrashStore {
  SharedPreferencesAnalyticsStore({super.name = 'stitchdb-analytics'});
}

/// The 2-letter region of the device locale, e.g. `DE`.
@internal
String? flutterAnalyticsCountry() {
  try {
    final code = ui.PlatformDispatcher.instance.locale.countryCode;
    if (code != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(code)) {
      return code.toUpperCase();
    }
  } catch (_) {}
  return null;
}

class _BackgroundFlush with WidgetsBindingObserver {
  final AnalyticsClient analytics;
  _BackgroundFlush(this.analytics);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(analytics.flush());
    }
  }
}

/// Flushes [analytics] when the app goes to the background. Returns a
/// function that removes the observer.
@internal
void Function() flushInBackground(AnalyticsClient analytics) {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final observer = _BackgroundFlush(analytics);
  binding.addObserver(observer);
  return () => binding.removeObserver(observer);
}

/// Makes [client.analytics] send as a Flutter app: platform `flutter`, the
/// region of the device locale as the country (the OS comes from the Dart
/// default), a SharedPreferences store named [storeName] and a flush when the app goes to the background.
/// `Stitch.initialize` does this for its client; call it for a
/// [StitchClient] you create yourself.
void configureFlutterAnalytics(
  StitchClient client, {
  String storeName = 'stitchdb-analytics',
}) {
  client.analytics.configure(
    platform: 'flutter',
    store: SharedPreferencesAnalyticsStore(name: storeName),
    country: flutterAnalyticsCountry,
    background: flushInBackground,
  );
}
