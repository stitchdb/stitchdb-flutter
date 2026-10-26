import 'dart:convert';

import 'package:http/http.dart';
import 'package:meta/meta.dart';

import 'crashes.dart';

/// Records every request the client makes as an `api` breadcrumb while crash
/// reporting is started: method, path, query keys (no values), status, the
/// error code of a failed call and the duration. No bodies, no hosts.
@internal
class CrashRecordingClient extends BaseClient {
  final Client _inner;

  /// Set by [CrashesClient.start], cleared by [CrashesClient.stop].
  void Function(Breadcrumb crumb)? sink;

  CrashRecordingClient(this._inner);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final record = sink;
    final url = crashUrl(request.url);
    if (record == null || url.contains('/crashes/v1/')) {
      return _inner.send(request);
    }
    final t0 = DateTime.now();
    final method = request.method.toUpperCase();
    final StreamedResponse res;
    try {
      res = await _inner.send(request);
    } catch (e) {
      record(
        Breadcrumb(
          type: 'api',
          at: t0.toUtc().toIso8601String(),
          level: 'error',
          message: '$method $url failed',
          data: {'method': method, 'url': url, 'status': 0, 'error': '$e'},
        ),
      );
      rethrow;
    }
    var out = res;
    String? code;
    if (res.statusCode >= 400) {
      // Read the body to find the error code, then hand on a copy of it.
      final bytes = await res.stream.toBytes();
      out = StreamedResponse(
        Stream.value(bytes),
        res.statusCode,
        contentLength: bytes.length,
        request: res.request,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
      try {
        final j = jsonDecode(utf8.decode(bytes));
        if (j is Map) {
          final c = j['code'] ?? j['error_code'] ?? j['error'];
          if (c != null) code = '$c';
        }
      } catch (_) {
        // not JSON
      }
    }
    final status = res.statusCode;
    record(
      Breadcrumb(
        type: 'api',
        at: t0.toUtc().toIso8601String(),
        level: status >= 400 ? 'error' : 'info',
        message: '$method $url $status',
        data: {
          'method': method,
          'url': url,
          'status': status,
          'error_code': ?code,
          'ms': DateTime.now().difference(t0).inMilliseconds,
        },
      ),
    );
    return out;
  }

  @override
  void close() => _inner.close();
}

/// The path of [uri] and the names of its query parameters, without values.
@internal
String crashUrl(Uri uri) {
  final keys = uri.query.isEmpty
      ? const <String>[]
      : [
          for (final part in uri.query.split('&'))
            if (part.isNotEmpty)
              Uri.decodeQueryComponent(part.split('=').first),
        ];
  return keys.isEmpty ? uri.path : '${uri.path}?${keys.join('&')}';
}
