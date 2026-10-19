import 'package:stitchdb_realtime/stitchdb_realtime.dart';

/// Example to use with StitchDB Realtime https://stitchdb.com/
Future<void> main() async {
  final socket = RealtimeClient(
    'ws://STITCHDB_API_ENDPOINT/realtime/v1',
    params: {'apikey': 'STITCHDB_API_KEY'},
    // ignore: avoid_print
    logger: (kind, msg, data) {
      print('$kind $msg $data');
    },
  );

  final channel = socket.channel('realtime:public');
  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'column',
      value: 'value',
    ),
    callback: (payload) {},
  );
  channel.onPostgresChanges(
    event: PostgresChangeEvent.delete,
    schema: 'public',
    callback: (payload) {
      print('channel delete payload: ${payload.toString()}');
    },
  );
  channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    callback: (payload) {
      print('channel insert payload: ${payload.toString()}');
    },
  );

  socket.onMessage((message) => print('MESSAGE $message'));

  // on connect and subscribe
  await socket.connect();
  channel.subscribe((a, [_]) => print('SUBSCRIBED'));

  // delay 20s to receive events from server
  await Future.delayed(const Duration(seconds: 20));

  // on unsubscribe and disconnect
  await channel.unsubscribe();
  await socket.disconnect();
}
