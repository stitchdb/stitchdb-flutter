## 1.2.0

- Product analytics for Flutter apps: `Stitch.instance.client.analytics` sends as platform `flutter` with the OS and the region of the device locale, keeps waiting events in SharedPreferences (`SharedPreferencesAnalyticsStore`) and flushes when the app goes to the background; `configureFlutterAnalytics` for own clients.
- Requires `stitchdb` 1.2.0.

## 1.1.0

- Crash reporting for Flutter apps: `FlutterError.onError` and `PlatformDispatcher.onError` are reported once `Stitch.instance.client.crashes.start()` is called; unsent reports are kept in SharedPreferences (`SharedPreferencesCrashStore`).
- `SharedPreferencesOfflineStore` for offline sync.

## 1.0.0

- First StitchDB release.
