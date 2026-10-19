@Deprecated('No longer used. May be removed in the future.')
class StitchRealtimeError extends Error {
  /// Creates an Unsubscribe error with the provided [message].
  StitchRealtimeError([this.message]);
  final Object? message;

  @override
  String toString() {
    if (message != null) {
      return "Unsubscribe failed: ${Error.safeToString(message)}";
    }
    return "Unsubscribe failed";
  }
}
