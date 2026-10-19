import 'package:http/http.dart';
import 'package:stitchdb/src/api_key.dart';

class AuthHttpClient extends BaseClient {
  final Client _inner;

  final String _stitchKey;
  final Future<String?> Function() _getAccessToken;

  /// When `true`, a new-format API key (`sdb_publishable_...` / `sdb_secret_...`)
  /// is never sent as an `Authorization: Bearer` token. A genuine session
  /// access token is still sent normally.
  final bool _omitNewApiKeyAsBearer;

  AuthHttpClient(
    this._stitchKey,
    this._inner,
    this._getAccessToken, {
    bool omitNewApiKeyAsBearer = false,
  }) : _omitNewApiKeyAsBearer = omitNewApiKeyAsBearer;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final accessToken = await _getAccessToken();

    if (accessToken != null) {
      request.headers.putIfAbsent("Authorization", () => 'Bearer $accessToken');
    } else if (!(_omitNewApiKeyAsBearer && isNewApiKey(_stitchKey))) {
      request.headers.putIfAbsent(
        "Authorization",
        () => 'Bearer $_stitchKey',
      );
    }
    request.headers.putIfAbsent("apikey", () => _stitchKey);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
