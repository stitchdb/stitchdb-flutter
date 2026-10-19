import 'package:stitchdb/src/version.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

class Constants {
  static final Map<String, String> defaultHeaders = Map.unmodifiable({
    'X-Client-Info': buildClientInfoHeader(
      'stitchdb-dart',
      version,
      platformInfo: PlatformInfo(
        platform: conditionalPlatform,
        platformVersion: conditionalPlatformVersion,
        runtimeVersion: conditionalRuntimeVersion,
      ),
    ),
  });
}
