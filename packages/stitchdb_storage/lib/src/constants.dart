import 'package:stitchdb_storage/src/version.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

class Constants {
  static final Map<String, String> defaultHeaders = {
    'X-Client-Info': buildClientInfoHeader('storage-dart', version),
  };
}
