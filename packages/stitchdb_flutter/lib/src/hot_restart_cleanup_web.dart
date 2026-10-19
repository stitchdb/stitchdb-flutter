import 'dart:async';
import 'dart:js_interop';

import 'package:stitchdb_flutter/stitchdb_flutter.dart';

@JS()
external JSFunction? stitchFlutterClientToDispose;

/// Store a function to properly dispose the previous [StitchClient] in
/// the js context.
///
/// WebSocket connections and [BroadcastChannel] are not closed when Flutter is hot-restarted on web.
///
/// This causes old dart code that is still associated with those
/// connections to be still running and causes unexpected behavior like type
/// errors and the fact that the events of the old connection may still be
/// logged.
void markClientToDispose(StitchClient client) {
  void dispose() {
    unawaited(
      client.realtime.disconnect(
        code: 1000,
        reason: 'Closed due to Flutter Web hot-restart',
      ),
    );
    unawaited(client.dispose());
  }

  stitchFlutterClientToDispose = dispose.toJS;
}

/// Disconnect the previous [StitchClient] if it exists.
///
/// This is done by calling the function stored by
/// [markClientToDispose] from the js context
void disposePreviousClient() {
  if (stitchFlutterClientToDispose != null) {
    stitchFlutterClientToDispose!.callAsFunction();
    stitchFlutterClientToDispose = null;
  }
}
