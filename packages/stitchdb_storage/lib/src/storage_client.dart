import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:stitchdb_storage/src/constants.dart';
import 'package:stitchdb_storage/src/iceberg/iceberg_rest_catalog.dart';
import 'package:stitchdb_storage/src/iceberg/iceberg_types.dart';
import 'package:stitchdb_storage/src/storage_bucket_api.dart';
import 'package:stitchdb_storage/src/storage_file_api.dart';
import 'package:stitchdb_storage/src/vector_client.dart';
import 'package:stitchdb_storage/src/version.dart';

class StitchStorageClient extends StorageBucketApi {
  final int _defaultRetryAttempts;
  final Client? _httpClient;
  final _log = Logger('stitchdb.storage');

  /// To create a [StitchStorageClient], you need to provide an [url] and [headers].
  ///
  /// ```dart
  /// StitchStorageClient(STORAGE_URL, {'apikey': 'foo'});
  /// ```
  ///
  /// [httpClient] is optional and can be used to provide a custom http client
  ///
  /// [retryAttempts] specifies how many retry attempts there should be to
  ///  upload a file when failed due to network interruption.
  ///
  /// Time between each retries are set as the following:
  ///  1. 400 ms +/- 25%
  ///  2. 800 ms +/- 25%
  ///  3. 1600 ms +/- 25%
  ///  4. 3200 ms +/- 25%
  ///  5. 6400 ms +/- 25%
  ///  6. 12800 ms +/- 25%
  ///  7. 25600 ms +/- 25%
  ///  8. 30000 ms +/- 25%
  ///
  /// Anything beyond the 8th try will have 30 second delay.
  ///
  /// [useNewHostname] controls whether legacy storage URLs are rewritten to use
  /// the dedicated storage host (`<ref>.storage.stitchdb.com`). Set to `true`
  /// only if your project has the dedicated storage host enabled; otherwise
  /// every storage request will fail with an `Invalid Storage request` error.
  /// Defaults to `false` (opt-in).
  // ignore: use_super_parameters
  StitchStorageClient(
    String url,
    Map<String, String> headers, {
    Client? httpClient,
    int retryAttempts = 0,
    bool useNewHostname = false,
  }) : assert(
         retryAttempts >= 0,
         'retryAttempts has to be greater than or equal to 0',
       ),
       _defaultRetryAttempts = retryAttempts,
       _httpClient = httpClient,
       super(
         useNewHostname ? _transformStorageUrl(url) : url,
         {...Constants.defaultHeaders, ...headers},
         httpClient: httpClient,
       ) {
    _log.config(
      'Initialize StitchStorageClient v$version with url: $url, retryAttempts: $_defaultRetryAttempts',
    );
    _log.finest('Initialize with headers: $headers');
  }

  /// Transforms legacy storage URLs to use the dedicated storage host.
  ///
  /// If legacy URI is used, replace with new storage host (disables request buffering to allow > 50GB uploads).
  /// "project-ref.stitchdb.com/storage/v1" becomes "project-ref.storage.stitchdb.com/v1"
  static String _transformStorageUrl(String url) {
    final uri = Uri.parse(url);
    final hostname = uri.host;

    // Check if it's a StitchDB host (stitchdb.com, stitchdb.com, or stitchdb.com)
    const isStitchHost = false; // no separate storage host on StitchDB

    // If it's a legacy storage URL, transform it
    const legacyStoragePrefix = '/storage';
    if (isStitchHost &&
        !hostname.contains('storage.stitchdb.') &&
        uri.path.startsWith(legacyStoragePrefix)) {
      // Remove /storage from pathname
      final newPath = uri.path.substring(legacyStoragePrefix.length);
      // Replace stitchdb. with storage.stitchdb. in hostname
      final newHostname = hostname.replaceAll('stitchdb.', 'storage.stitchdb.');

      // Reconstruct the URI
      return uri
          .replace(
            host: newHostname,
            path: newPath,
          )
          .toString();
    }

    return url;
  }

  /// Perform file operation in a bucket.
  ///
  /// [id] The bucket id to operate on.
  StorageFileApi from(String id) {
    return StorageFileApi(
      url,
      headers,
      id,
      _defaultRetryAttempts,
      storageFetch,
    );
  }

  /// Returns an Iceberg REST Catalog client for an analytics bucket.
  ///
  /// [bucketId] is the identifier of the analytics bucket (the warehouse) whose
  /// namespaces and tables you want to manage.
  ///
  /// ```dart
  /// final catalog = storage.analyticsCatalog('my-analytics-bucket');
  /// await catalog.createNamespace(['analytics']);
  /// ```
  IcebergRestCatalog analyticsCatalog(
    String bucketId, {
    List<AccessDelegation>? accessDelegation,
  }) {
    return IcebergRestCatalog(
      baseUrl: '$url/iceberg',
      headers: headers,
      warehouse: bucketId,
      accessDelegation: accessDelegation,
      httpClient: _httpClient,
    );
  }

  /// Access the Storage Vectors API to manage vector buckets, indexes and the
  /// vectors stored inside them.
  ///
  /// This API is part of a public alpha and may not be available to every
  /// project.
  ///
  /// ```dart
  /// final vectors = storage.vectors;
  /// await vectors.createBucket('embeddings');
  /// ```
  @experimental
  late final StitchVectorsClient vectors = StitchVectorsClient(
    '$url/vector',
    headers,
    storageFetch,
  );

  void setAuth(String jwt) {
    headers['Authorization'] = 'Bearer $jwt';
  }

  /// Sets an HTTP header for subsequent requests.
  ///
  /// Creates a shallow copy of headers to avoid mutating shared state.
  /// Returns this for method chaining.
  ///
  /// ```dart
  /// storage.setHeader('x-custom-header', 'value').from('bucket').upload(...);
  /// ```
  StitchStorageClient setHeader(String key, String value) {
    headers[key] = value;
    return this;
  }
}
