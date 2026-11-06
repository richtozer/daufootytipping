import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dau_shared/constants/identity_reasons.dart';

/// How long an identity handler may keep starting new steps.
///
/// Cloud Run answers the client with a 504 once a request reaches its timeout
/// ([mutatingCallableTimeout]), but it does not stop the container working on
/// it: Dart code that has been given up on keeps running. So a handler stops
/// itself, ten seconds before that, at its next step boundary. Every step
/// boundary is a point the crash tests prove is safe to stop at, and a handler
/// that stops this way releases its lease and in-flight marker like any other
/// failing handler.
///
/// The deadline is checked between steps, not inside one, so a handler can run
/// past it by the length of one step (each database request is bounded by its
/// own 15-second timeout). The tipper lease and the in-flight marker's
/// staleness allowance both cover that overrun.
const Duration handlerSoftDeadline = Duration(seconds: 50);

/// Stops a handler at the first step boundary after its time is up.
///
/// [check] has the shape of a [Checkpoint], so a handler is given it as its
/// checkpoint.
class HandlerDeadline {
  HandlerDeadline({Duration limit = handlerSoftDeadline, int Function()? nowMs})
    : _limit = limit,
      _clock = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _startedAtMs = _clock();
  }

  final Duration _limit;
  final int Function() _clock;
  late final int _startedAtMs;

  /// Whether the time is up.
  bool get expired => _clock() - _startedAtMs >= _limit.inMilliseconds;

  /// Throws once the time is up. [step] is the name of the step just finished,
  /// which is not needed here.
  Future<void> check(String step) async {
    if (expired) {
      throw UnavailableError(
        'That took too long. Please try again.',
        reason: identityReasonUnavailable,
      );
    }
  }
}
