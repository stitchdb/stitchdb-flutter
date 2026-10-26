## 1.2.0

- Product analytics: `client.analytics` (`start`, `track`, `flush`, `stop`, `optOut`, `optIn`, `isOptedOut`, `anonymousId`), with `beforeSend`, batches sent in the background and kept in an `AnalyticsStore` (`MemoryAnalyticsStore`, `FileAnalyticsStore`; every `CrashStore` works too) while offline.
- Crash reporting no longer records the client's analytics calls as breadcrumbs.

## 1.1.0

- Crash reporting: `client.crashes` (`start`, `captureException`, `captureMessage`, `addBreadcrumb`, `flush`, `stop`, `runGuarded`) with API-call breadcrumbs, `MemoryCrashStore` and `FileCrashStore`.
- Offline sync: `StitchClient.offline()`.

## 1.0.0

- First StitchDB release.
