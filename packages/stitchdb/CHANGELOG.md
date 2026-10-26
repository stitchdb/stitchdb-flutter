## 1.3.0

- Deep links: `client.links` with `LinksClient.codeFrom`, `resolve` (the path and data of the short link the app was opened with), `deferred` (the link that led to an install, asked once per install and remembered in the analytics store; `force` asks again), and `create`, `list`, `get` (stats), `update` and `remove`. Types `AppLink`, `Link`, `LinkInput`, `LinkStats`, `LinkList`; errors are `LinksException` with the HTTP status (410 for an expired or turned-off link).

## 1.2.0

- Product analytics: `client.analytics` (`start`, `track`, `flush`, `stop`, `optOut`, `optIn`, `isOptedOut`, `anonymousId`), with `beforeSend`, batches sent in the background and kept in an `AnalyticsStore` (`MemoryAnalyticsStore`, `FileAnalyticsStore`; every `CrashStore` works too) while offline.
- Crash reporting no longer records the client's analytics calls as breadcrumbs.

## 1.1.0

- Crash reporting: `client.crashes` (`start`, `captureException`, `captureMessage`, `addBreadcrumb`, `flush`, `stop`, `runGuarded`) with API-call breadcrumbs, `MemoryCrashStore` and `FileCrashStore`.
- Offline sync: `StitchClient.offline()`.

## 1.0.0

- First StitchDB release.
