import 'package:stitchdb_postgrest/src/version.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

final defaultHeaders = {
  'X-Client-Info': buildClientInfoHeader('postgrest-dart', version),
};
