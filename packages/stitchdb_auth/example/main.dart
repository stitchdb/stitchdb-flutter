// ignore_for_file: avoid_print

import 'package:stitchdb_auth/stitchdb_auth.dart';

/// Example to use with StitchDB Auth https://stitchdb.com/
Future<void> main() async {
  const stitchAuthUrl = 'http://localhost:9999';
  const stitchKey = '';
  final client = StitchAuthClient(
    url: stitchAuthUrl,
    headers: {
      'Authorization': 'Bearer $stitchKey',
      'apikey': stitchKey,
    },
  );

  try {
    final login = await client.signInWithPassword(
      email: 'email',
      password: '12345',
    );
    print('Logged in, user id: ${login.session!.user.id}');
  } on AuthException catch (error) {
    print('Sign in error: ${error.message}');
  }

  await client.signOut();
  print('Logged out!');
}
