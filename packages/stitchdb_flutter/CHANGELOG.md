## 1.1.0

- Crash reporting for Flutter apps: `FlutterError.onError` and `PlatformDispatcher.onError` are reported once `Stitch.instance.client.crashes.start()` is called; unsent reports are kept in SharedPreferences (`SharedPreferencesCrashStore`).
- `SharedPreferencesOfflineStore` for offline sync.

## 1.0.0

- First StitchDB release.
