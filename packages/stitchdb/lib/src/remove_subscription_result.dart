import 'package:stitchdb/src/stitch_realtime_error.dart';

@Deprecated("No longer used. May be removed in the future.")
class RemoveSubscriptionResult {
  const RemoveSubscriptionResult({required this.openSubscriptions, this.error});
  final int openSubscriptions;
  final StitchRealtimeError? error;

  @override
  String toString() =>
      'RemoveSubscriptionResult(openSubscriptions: $openSubscriptions, error: $error)';
}
