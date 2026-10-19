import 'dart:io';

import 'package:stitchdb/stitchdb.dart';

/// Run with:
///   STITCHDB_URL=https://<project-ref>.stitchdb.com STITCHDB_ANON_KEY=<anon-key> dart run example/main.dart
Future<void> main() async {
  final client = StitchClient(
    Platform.environment['STITCHDB_URL']!,
    Platform.environment['STITCHDB_ANON_KEY']!,
  );

  // Database
  final todos = await client.from('todos').select('id, task, is_complete').limit(10);
  print('todos: $todos');

  // Auth
  final res = await client.auth.signInWithPassword(email: 'ada@example.com', password: 'a-strong-password');
  print('signed in as ${res.user?.email}');

  // Realtime
  final channel = client.channel('room-1')
    ..onBroadcast(event: 'cursor', callback: (payload) => print('cursor: $payload'))
    ..subscribe();

  // Storage
  final files = await client.storage.from('avatars').list();
  print('files: ${files.map((f) => f.name).toList()}');

  // Edge Functions
  final fn = await client.functions.invoke('hello-world', body: {'name': 'Ada'});
  print('function: ${fn.data}');

  await client.removeChannel(channel);
  await client.dispose();
}
