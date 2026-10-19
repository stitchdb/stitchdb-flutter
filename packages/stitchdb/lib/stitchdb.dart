/// A dart client for StitchDB. It supports database query, authenticate users
/// and listen for realtime changes. This client makes it simple for developers
/// to build secure and scalable products.
library;

export 'package:stitchdb_functions/stitchdb_functions.dart';
export 'package:stitchdb_auth/stitchdb_auth.dart';
export 'package:stitchdb_postgrest/stitchdb_postgrest.dart' hide HttpMethod;
export 'package:stitchdb_realtime/stitchdb_realtime.dart';
export 'package:stitchdb_storage/stitchdb_storage.dart';

export 'src/auth_user.dart';
export 'src/realtime_client_options.dart';
export 'src/remove_subscription_result.dart';
export 'src/stitch_client.dart';
export 'src/stitch_client_options.dart';
export 'src/stitch_event_types.dart';
export 'src/stitch_query_builder.dart';
export 'src/stitch_query_schema.dart';
export 'src/stitch_realtime_error.dart';
export 'src/stitch_stream_builder.dart';
export 'src/trace_propagation.dart';
