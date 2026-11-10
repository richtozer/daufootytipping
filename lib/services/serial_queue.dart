import 'dart:async';

/// Runs actions one at a time, in the order they were asked for.
///
/// For work that reads, changes and writes something shared, where two
/// overlapping runs would each start from the same state and overwrite one
/// another's changes, or where the server expects one client's calls in order.
/// An action that fails reports its failure to its own caller only; the actions
/// after it still run.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// Runs [action] after every action asked for before it has finished.
  Future<T> run<T>(Future<T> Function() action) {
    final Completer<T> result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
