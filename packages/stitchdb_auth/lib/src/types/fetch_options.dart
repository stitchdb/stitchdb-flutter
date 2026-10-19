import 'package:stitchdb_common/stitchdb_common.dart';

export 'package:stitchdb_common/stitchdb_common.dart' show FetchOptions;

class StitchAuthRequestOptions extends FetchOptions {
  final String? jwt;
  final String? redirectTo;
  final Map<String, dynamic>? body;
  final Map<String, String>? query;

  StitchAuthRequestOptions({
    this.jwt,
    this.redirectTo,
    this.body,
    this.query,
    required Map<String, String> headers,
    bool? noResolveJson,
  }) : super(headers, noResolveJson: noResolveJson);
}
