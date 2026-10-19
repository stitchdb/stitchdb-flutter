# stitchdb_common

> [!WARNING]
> This is an **internal package**. It is an implementation detail of the
> StitchDB client packages and is not intended to be consumed directly.
> **Breaking changes can be expected** as the client packages evolve, so please
> do not depend on it directly.

Shared internal utilities used across the StitchDB Dart and Flutter client
packages (`stitchdb-auth`, `postgrest`, `stitchdb_realtime`, `stitchdb_storage`,
`stitchdb_functions`, `stitchdb`, `stitchdb_flutter`).

This package holds code that would otherwise be duplicated across those
packages: the `X-Client-Info` header builder, platform detection, a small
replay stream subject, base64url/PKCE helpers and a few other primitives.
