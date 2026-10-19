<br />
<p align="center">
  <a href="https://stitchdb.com">
    <img alt="StitchDB Logo" width="300" src="https://raw.githubusercontent.com/stitchdb/stitchdb/master/packages/common/assets/images/logo-preview.jpg">
  </a>

  <h1 align="center">stitchdb_realtime</h1>

  <p align="center">
    Dart client library for <a href="https://stitchdb.com/docs">StitchDB Realtime</a>, to listen to changes in a PostgreSQL database over websockets.
  </p>

  <p align="center">
    <a href="https://stitchdb.com/docs">Guides</a>
    ·
    <a href="https://stitchdb.com/docs">Reference Docs</a>
  </p>
</p>

<div align="center">

[![pub package](https://img.shields.io/pub/v/stitchdb_realtime.svg)](https://pub.dev/packages/stitchdb_realtime)

</div>

## Docs

The docs can be found on the official StitchDB website.

- [Dart reference](https://stitchdb.com/docs)
- [Realtime guide](https://stitchdb.com/docs)

## Testing

The unit tests run without any external services:

```bash
dart test -x integration
```

The integration tests in `test/realtime_integration_test.dart` run against a
real StitchDB Realtime server. Start the local StitchDB stack with the CLI first
(from the repository root), then run the full suite (it exercises both protocol
versions, `1.0.0` and `2.0.0`):

```bash
stitchdb start
dart test
stitchdb stop
```

## License

This repo is licensed under MIT.

## Credits

- https://github.com/stitchdb - ported from realtime-js library
