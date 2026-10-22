/// A step boundary inside an identity operation. A test passes one to make the
/// operation "crash" after a chosen step; production passes none.
typedef Checkpoint = Future<void> Function(String step);

/// Thrown by a test's [Checkpoint] to stand in for the process dying. The code
/// under test must behave as it would after a real crash: in particular it
/// must not tidy up (a lease is left to expire, a journal is left for the
/// retry). Never thrown in production.
class SimulatedCrash implements Exception {
  const SimulatedCrash(this.step);

  final String step;

  @override
  String toString() => 'SimulatedCrash after $step';
}
