import 'package:http/http.dart';
import 'package:stitchdb/stitchdb.dart';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

import 'counter.dart';

/// Used to perform [rpc] and [from] operations with a different schema than in [StitchClient].
class StitchQuerySchema {
  final Counter _counter;
  final String _restUrl;
  final Map<String, String> _headers;
  final String _schema;
  final YAJsonIsolate _isolate;
  final Client? _authHttpClient;
  final RealtimeClient _realtime;
  final PostgrestClient _rest;

  const StitchQuerySchema({
    required Counter counter,
    required String restUrl,
    required Map<String, String> headers,
    required String schema,
    required YAJsonIsolate isolate,
    required Client? authHttpClient,
    required RealtimeClient realtime,
    required PostgrestClient rest,
  }) : _counter = counter,
       _restUrl = restUrl,
       _headers = headers,
       _schema = schema,
       _isolate = isolate,
       _authHttpClient = authHttpClient,
       _realtime = realtime,
       _rest = rest;

  /// Perform a table operation.
  StitchQueryBuilder from(String table) {
    final url = '$_restUrl/$table';
    return StitchQueryBuilder(
      url,
      _realtime,
      headers: {..._rest.headers, ..._headers},
      schema: _schema,
      table: table,
      httpClient: _authHttpClient,
      incrementId: _counter.increment(),
      isolate: _isolate,
    );
  }

  /// {@macro postgrest_rpc}
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    bool get = false,
  }) {
    _rest.headers.addAll(_headers);
    return _rest.rpc(
      fn,
      params: params,
      get: get,
    );
  }

  StitchQuerySchema schema(String schema) {
    final newRest = _rest.schema(schema);
    return StitchQuerySchema(
      counter: _counter,
      restUrl: _restUrl,
      headers: _headers,
      schema: schema,
      isolate: _isolate,
      authHttpClient: _authHttpClient,
      realtime: _realtime,
      rest: newRest,
    );
  }
}
