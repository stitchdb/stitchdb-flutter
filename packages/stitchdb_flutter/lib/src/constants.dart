import 'package:stitchdb_common/stitchdb_common.dart';
import 'package:stitchdb_flutter/src/version.dart';

class Constants {
  static final Map<String, String> defaultHeaders = Map.unmodifiable({
    'X-Client-Info': buildClientInfoHeader(
      'stitchdb-flutter',
      version,
      platformInfo: PlatformInfo(
        platform: conditionalPlatform,
        platformVersion: conditionalPlatformVersion,
        runtimeVersion: conditionalRuntimeVersion,
      ),
    ),
  });
}
