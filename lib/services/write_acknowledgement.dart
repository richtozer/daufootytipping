import 'dart:async';

/// How long a screen waits for the Realtime Database to acknowledge a write
/// before it stops showing a busy indicator and tells the user the change is
/// queued.
const Duration defaultWriteAcknowledgementLimit = Duration(seconds: 15);

/// How a database write stood once [awaitAcknowledgement] stopped waiting.
enum WriteAcknowledgement {
  /// The server accepted the write.
  confirmed,

  /// No answer within the limit. The write is still queued on the device and is
  /// sent when the connection recovers (or by the next process, if this one
  /// stops first), so it may still succeed or still be rejected.
  stillPending,
}

/// A write was handed to the Realtime Database but not acknowledged in time.
///
/// It is not a failure: the SDK keeps the write. Screens catch it to say so
/// instead of leaving the user on an endless busy indicator.
class WriteNotConfirmedException implements Exception {
  const WriteNotConfirmedException(this.description);

  /// What was being written, for logs (never the data itself).
  final String description;

  @override
  String toString() =>
      'WriteNotConfirmedException: $description was not confirmed in time';
}

/// Waits up to [limit] for [write] to complete.
///
/// A write that fails inside the limit rethrows its error, because a rejection
/// is a real answer. A write that is still running at the limit is reported as
/// [WriteAcknowledgement.stillPending] and keeps running; if it later fails,
/// [onLateError] hears about it, so the error is never lost or left unhandled.
Future<WriteAcknowledgement> awaitAcknowledgement(
  Future<void> write, {
  Duration limit = defaultWriteAcknowledgementLimit,
  void Function(Object error, StackTrace stackTrace)? onLateError,
}) {
  final Completer<WriteAcknowledgement> outcome =
      Completer<WriteAcknowledgement>();
  final Timer limitTimer = Timer(limit, () {
    if (!outcome.isCompleted) {
      outcome.complete(WriteAcknowledgement.stillPending);
    }
  });
  write.then<void>(
    (_) {
      limitTimer.cancel();
      if (!outcome.isCompleted) {
        outcome.complete(WriteAcknowledgement.confirmed);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      limitTimer.cancel();
      if (!outcome.isCompleted) {
        outcome.completeError(error, stackTrace);
      } else {
        onLateError?.call(error, stackTrace);
      }
    },
  );
  return outcome.future;
}
