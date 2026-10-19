import 'package:stitchdb_functions/src/version.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

class Constants {
  static final defaultHeaders = {
    'X-Client-Info': buildClientInfoHeader('functions-dart', version),
  };
}
