import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitchdb_flutter/src/version.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

import 'widget_test_stubs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAppLink();
  });

  tearDown(() async {
    try {
      await Stitch.instance.dispose();
    } catch (_) {
      // Ignore dispose errors
    }
  });

  test(
    'FlutterError.onError is reported as a flutter crash and still reaches the previous handler',
    () async {
      final reports = <Map<String, dynamic>>[];
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/crashes/v1/report')) {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          reports.addAll((b['reports'] as List).cast<Map<String, dynamic>>());
        }
        return http.Response('{}', 200, request: req);
      });
      await Stitch.initialize(
        url: 'http://localhost:9999',
        anonKey: 'anon-key',
        httpClient: mock,
        debug: false,
      );

      final original = FlutterError.onError;
      final previous = <FlutterErrorDetails>[];
      void previousHandler(FlutterErrorDetails d) => previous.add(d);
      FlutterError.onError = previousHandler;
      addTearDown(() => FlutterError.onError = original);

      final crashes = Stitch.instance.client.crashes;
      await crashes.start(release: '2.0.0');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('build failed'),
          stack: StackTrace.current,
          library: 'widgets library',
        ),
      );
      expect(previous, hasLength(1));
      await crashes.flush();

      expect(reports, hasLength(1));
      final r = reports.single;
      expect(r['platform'], 'flutter');
      expect(r['release'], '2.0.0');
      expect(r['handled'], false);
      expect((r['exception'] as Map)['mechanism'], 'FlutterError.onError');
      expect((r['exception'] as Map)['type'], 'StateError');
      expect((r['context'] as Map)['library'], 'widgets library');
      final device = r['device'] as Map;
      expect(device['sdk'], 'stitchdb-flutter/$version');
      expect(device['runtime'], 'flutter');
      expect(device['locale'], isNotNull);

      crashes.stop();
      expect(FlutterError.onError, previousHandler);
    },
  );

  test(
    'SharedPreferencesCrashStore keeps values in SharedPreferences',
    () async {
      final store = SharedPreferencesCrashStore(name: 'crash-test');
      await store.set('install', 'abc');
      store.setNow('queue', '[]');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('crash-test/install'), 'abc');
      expect(prefs.getString('crash-test/queue'), '[]');
      await store.set('queue', null);
      expect(await store.get('queue'), isNull);
    },
  );
}
