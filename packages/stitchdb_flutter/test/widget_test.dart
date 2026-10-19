import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitchdb_flutter/stitchdb_flutter.dart';

import 'widget_test_stubs.dart';

void main() {
  const stitchUrl = '';
  const stitchKey = '';

  setUpAll(() {
    mockAppLink();
  });

  testWidgets('Signing out triggers AuthChangeEvent.signedOut event', (
    tester,
  ) async {
    // Initialize the StitchDB singleton
    await Stitch.initialize(
      url: stitchUrl,
      anonKey: stitchKey,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: const MockLocalStorage(),
        pkceAsyncStorage: MockAsyncStorage(),
      ),
    );
    Stitch.instance.client.auth.stopAutoRefresh();
    await tester.pumpWidget(const MaterialApp(home: MockWidget()));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('You have signed out'), findsOneWidget);
  });
}
