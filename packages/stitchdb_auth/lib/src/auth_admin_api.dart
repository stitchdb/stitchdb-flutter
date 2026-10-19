import 'package:stitchdb_auth/stitchdb_auth.dart';
import 'package:stitchdb_auth/src/fetch.dart';
import 'package:stitchdb_auth/src/types/fetch_options.dart';
import 'package:http/http.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

import 'package:meta/meta.dart';

import 'auth_admin_custom_providers_api.dart';
import 'auth_admin_mfa_api.dart';
import 'auth_admin_oauth_api.dart';

class StitchAuthAdminApi {
  final String _url;
  final Map<String, String> _headers;

  final Client? _httpClient;
  late final StitchAuthFetch _fetch = StitchAuthFetch(_httpClient);
  late final StitchAuthAdminMFAApi mfa;

  /// Contains all OAuth client administration methods.
  /// Only relevant when the OAuth 2.1 server is enabled in StitchDB Auth.
  late final StitchAuthAdminOAuthApi oauth;

  /// Contains all custom OIDC/OAuth provider administration methods.
  late final StitchAuthAdminCustomProvidersApi customProviders;

  /// Contains all passkey administration methods.
  /// Only relevant when passkeys are enabled in StitchDB Auth.
  @experimental
  late final StitchAuthAdminPasskeyApi passkey;

  StitchAuthAdminApi(
    this._url, {
    Map<String, String>? headers,
    Client? httpClient,
  }) : _headers = headers ?? {},
       _httpClient = httpClient {
    mfa = StitchAuthAdminMFAApi(
      url: _url,
      headers: _headers,
      fetch: _fetch,
    );
    oauth = StitchAuthAdminOAuthApi(
      url: _url,
      headers: _headers,
      fetch: _fetch,
    );
    customProviders = StitchAuthAdminCustomProvidersApi(
      url: _url,
      headers: _headers,
      fetch: _fetch,
    );
    passkey = StitchAuthAdminPasskeyApi(
      url: _url,
      headers: _headers,
      fetch: _fetch,
    );
  }

  /// Removes a logged-in session.
  Future<void> signOut(
    String jwt, {
    SignOutScope scope = SignOutScope.global,
  }) async {
    final options = StitchAuthRequestOptions(
      headers: _headers,
      noResolveJson: true,
      jwt: jwt,
      query: {'scope': scope.name},
    );

    await _fetch.request(
      '$_url/logout',
      RequestMethodType.post,
      options: options,
    );
  }

  /// Creates a new user.
  ///
  /// This function should only be called on a server. Never expose your `secret` key on the client.
  ///
  /// Requires either an email or phone
  Future<UserResponse> createUser(AdminUserAttributes attributes) async {
    final options = StitchAuthRequestOptions(
      headers: _headers,
      body: attributes.toJson(),
    );
    final response = await _fetch.request(
      '$_url/admin/users',
      RequestMethodType.post,
      options: options,
    );
    return UserResponse.fromJson(response);
  }

  /// Delete a user. Requires a `secret` key.
  ///
  ///  [id] is the user id of the user you want to remove.
  ///
  /// When [shouldSoftDelete] is `true` the user is soft deleted, keeping their
  /// record and any associated data while marking the user as deleted. It
  /// defaults to `false`, which permanently removes the user.
  ///
  /// This function should only be called on a server. Never expose your `secret` key on the client.
  Future<void> deleteUser(String id, {bool shouldSoftDelete = false}) async {
    validateUuid(id);
    final options = StitchAuthRequestOptions(
      headers: _headers,
      body: {'should_soft_delete': shouldSoftDelete},
    );
    await _fetch.request(
      '$_url/admin/users/$id',
      RequestMethodType.delete,
      options: options,
    );
  }

  /// Get a list of users.
  ///
  /// This function should only be called on a server. Never expose your `secret` key on the client.
  ///
  /// The result is paginated. Use the [page] and [perPage] parameters to paginate the result.
  Future<List<User>> listUsers({int? page, int? perPage}) async {
    final options = StitchAuthRequestOptions(
      headers: _headers,
      query: {
        'page': ?page?.toString(),
        'per_page': ?perPage?.toString(),
      },
    );
    final response = await _fetch.request(
      '$_url/admin/users',
      RequestMethodType.get,
      options: options,
    );
    return (response['users'] as List).map((e) => User.fromJson(e)!).toList();
  }

  /// Sends an invite link to an email address.
  Future<UserResponse> inviteUserByEmail(
    String email, {
    String? redirectTo,
    Map<String, dynamic>? data,
  }) async {
    final body = {
      'email': email,
      'data': ?data,
    };
    final fetchOptions = StitchAuthRequestOptions(
      headers: _headers,
      body: body,
      redirectTo: redirectTo,
    );

    final response = await _fetch.request(
      '$_url/invite',
      RequestMethodType.post,
      options: fetchOptions,
    );
    return UserResponse.fromJson(response);
  }

  /// Generates links to be sent via email or other.
  ///
  /// [password] is required for [GenerateLinkType.signup]
  ///
  /// [newEmail] is required for [GenerateLinkType.emailChangeCurrent]
  /// and [GenerateLinkType.emailChangeNew]
  ///
  /// [data] may be used to store the user's metadata.
  /// This maps to the `auth.users.user_metadata` column.
  /// Applicable for [GenerateLinkType.signup], [GenerateLinkType.invite],
  /// [GenerateLinkType.magiclink]
  Future<GenerateLinkResponse> generateLink({
    required GenerateLinkType type,
    required String email,
    String? newEmail,
    String? password,
    Map<String, dynamic>? data,
    String? redirectTo,
  }) async {
    assert(
      !(type == GenerateLinkType.emailChangeCurrent ||
              type == GenerateLinkType.emailChangeNew) ||
          newEmail != null,
      'newEmail is required for emailChangeCurrent and emailChangeNew',
    );
    assert(
      type != GenerateLinkType.signup || password != null,
      'password is required for signup',
    );
    final body = {
      'email': email,
      'type': type.snakeCase,
      'data': ?data,
      'redirect_to': ?redirectTo,
      'password': ?password,
      'new_email': ?newEmail,
    };

    final fetchOptions = StitchAuthRequestOptions(headers: _headers, body: body);

    final response = await _fetch.request(
      '$_url/admin/generate_link',
      RequestMethodType.post,
      options: fetchOptions,
    );
    return GenerateLinkResponse.fromJson(response);
  }

  /// Gets the user by their id.
  Future<UserResponse> getUserById(String uid) async {
    validateUuid(uid);
    final options = StitchAuthRequestOptions(headers: _headers);
    final response = await _fetch.request(
      '$_url/admin/users/$uid',
      RequestMethodType.get,
      options: options,
    );
    return UserResponse.fromJson(response);
  }

  /// Updates the user data.
  Future<UserResponse> updateUserById(
    String uid, {
    required AdminUserAttributes attributes,
  }) async {
    validateUuid(uid);
    final body = attributes.toJson();
    final options = StitchAuthRequestOptions(headers: _headers, body: body);
    final response = await _fetch.request(
      '$_url/admin/users/$uid',
      RequestMethodType.put,
      options: options,
    );
    return UserResponse.fromJson(response);
  }
}
