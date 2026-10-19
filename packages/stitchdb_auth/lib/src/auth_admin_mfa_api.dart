import 'fetch.dart';
import 'helper.dart';
import 'types/fetch_options.dart';
import 'types/mfa.dart';

class StitchAuthAdminMFAApi {
  final String _url;
  final Map<String, String> _headers;
  final StitchAuthFetch _fetch;

  const StitchAuthAdminMFAApi({
    required String url,
    required Map<String, String> headers,
    required StitchAuthFetch fetch,
  }) : _url = url,
       _headers = headers,
       _fetch = fetch;

  Future<AuthMFAAdminListFactorsResponse> listFactors({
    required String userId,
  }) async {
    validateUuid(userId);

    final data = await _fetch.request(
      '$_url/admin/users/$userId/factors',
      RequestMethodType.get,
      options: StitchAuthRequestOptions(
        headers: _headers,
      ),
    );

    return AuthMFAAdminListFactorsResponse(
      factors: (data as List).map((e) => Factor.fromJson(e)).toList(),
    );
  }

  Future<AuthMFAAdminDeleteFactorResponse> deleteFactor({
    required String userId,
    required String factorId,
  }) async {
    validateUuid(userId);
    validateUuid(factorId);

    final data = await _fetch.request(
      '$_url/admin/users/$userId/factors/$factorId',
      RequestMethodType.delete,
      options: StitchAuthRequestOptions(
        headers: _headers,
      ),
    );

    return AuthMFAAdminDeleteFactorResponse.fromJson(data);
  }
}
