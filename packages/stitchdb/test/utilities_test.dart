// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:stitchdb/src/auth_http_client.dart';
import 'package:stitchdb/src/constants.dart';
import 'package:stitchdb/src/counter.dart';
import 'package:stitchdb/src/stitch_event_types.dart';
import 'package:stitchdb_common/stitchdb_common.dart';
import 'package:test/test.dart';

const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');

void main() {
  group('Counter', () {
    late Counter counter;

    setUp(() {
      counter = Counter();
    });

    test('should start with value 0', () {
      expect(counter.value, 0);
    });

    test('should increment and return previous value', () {
      expect(counter.increment(), 0);
      expect(counter.value, 1);
    });

    test('should increment multiple times correctly', () {
      expect(counter.increment(), 0);
      expect(counter.increment(), 1);
      expect(counter.increment(), 2);
      expect(counter.value, 3);
    });
  });

  group('Constants', () {
    test('should have default headers with X-Client-Info', () {
      expect(
        Constants.defaultHeaders,
        containsPair('X-Client-Info', startsWith('stitchdb-dart/')),
      );
    });

    test(
      'should include structured platform metadata in X-Client-Info when not on web',
      () {
        if (!kIsWeb) {
          final clientInfo = Constants.defaultHeaders['X-Client-Info']!;
          expect(clientInfo, contains('; platform='));
          expect(clientInfo, contains('; platform-version='));
          expect(clientInfo, contains('; runtime=dart'));
          expect(clientInfo, contains('; runtime-version='));
        }
      },
    );

    test('should have platform getter', () {
      if (kIsWeb) {
        expect(conditionalPlatform, isNull);
      } else {
        expect(conditionalPlatform, isNotNull);
        expect(conditionalPlatform, isA<String>());
      }
    });

    test('should have platformVersion getter', () {
      if (kIsWeb) {
        expect(conditionalPlatformVersion, isNull);
      } else {
        expect(conditionalPlatformVersion, isNotNull);
        expect(conditionalPlatformVersion, isA<String>());
      }
    });

    test('should have runtimeVersion getter', () {
      if (kIsWeb) {
        expect(conditionalRuntimeVersion, isNull);
      } else {
        expect(conditionalRuntimeVersion, isNotNull);
        expect(conditionalRuntimeVersion, isA<String>());
        // Version should be a semver-like string (e.g. "3.7.2")
        expect(conditionalRuntimeVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
      }
    });
  });

  group('AuthHttpClient', () {
    late HttpServer mockServer;
    late AuthHttpClient authClient;
    const stitchKey = 'test-stitchdb-key';

    setUp(() async {
      mockServer = await HttpServer.bind('localhost', 0);
      mockServer.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"success": true}');
        unawaited(request.response.close());
      });

      authClient = AuthHttpClient(
        stitchKey,
        http.Client(),
        () async => 'test-access-token',
      );
    });

    tearDown(() async {
      await mockServer.close();
    });

    test('should add Authorization header with access token', () async {
      final uri = Uri.parse(
        'http://${mockServer.address.host}:${mockServer.port}/test',
      );
      final request = http.Request('GET', uri);

      await authClient.send(request);

      expect(request.headers['Authorization'], 'Bearer test-access-token');
    });

    test('should add apikey header', () async {
      final uri = Uri.parse(
        'http://${mockServer.address.host}:${mockServer.port}/test',
      );
      final request = http.Request('GET', uri);

      await authClient.send(request);

      expect(request.headers['apikey'], stitchKey);
    });

    test('should use stitchdb key when access token is null', () async {
      final authClientNoToken = AuthHttpClient(
        stitchKey,
        http.Client(),
        () async => null,
      );

      final uri = Uri.parse(
        'http://${mockServer.address.host}:${mockServer.port}/test',
      );
      final request = http.Request('GET', uri);

      await authClientNoToken.send(request);

      expect(request.headers['Authorization'], 'Bearer $stitchKey');
    });

    test('should not override existing Authorization header', () async {
      final uri = Uri.parse(
        'http://${mockServer.address.host}:${mockServer.port}/test',
      );
      final request = http.Request('GET', uri);
      request.headers['Authorization'] = 'Bearer existing-token';

      await authClient.send(request);

      expect(request.headers['Authorization'], 'Bearer existing-token');
    });

    test('should not override existing apikey header', () async {
      final uri = Uri.parse(
        'http://${mockServer.address.host}:${mockServer.port}/test',
      );
      final request = http.Request('GET', uri);
      request.headers['apikey'] = 'existing-key';

      await authClient.send(request);

      expect(request.headers['apikey'], 'existing-key');
    });
  });

  group('StitchEventTypes', () {
    test('should return correct name for each event type', () {
      expect(StitchEventTypes.insert.name(), 'INSERT');
      expect(StitchEventTypes.update.name(), 'UPDATE');
      expect(StitchEventTypes.delete.name(), 'DELETE');
      expect(StitchEventTypes.all.name(), '*');
      expect(StitchEventTypes.broadcast.name(), 'BROADCAST');
      expect(StitchEventTypes.presence.name(), 'PRESENCE');
    });
  });
}
