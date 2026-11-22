import 'package:dart_functions/rtdb/rest_database.dart';

/// What happened to a [claim].
enum ClaimOutcome {
  /// The location was empty and now holds the owner.
  claimed,

  /// The location already held this owner, so a retry changed nothing.
  alreadyOwned,

  /// The location holds something else. It was not touched.
  heldByOther,
}

/// What [replaceIf] found and left behind.
class ReplaceIfResult {
  const ReplaceIfResult({required this.holdsValue, required this.previous});

  /// True when the location now holds the requested value, whether this call
  /// wrote it or it was already there.
  final bool holdsValue;

  /// What the location held before this call. A caller that has to undo the
  /// replacement restores this value (null means the location was empty).
  final Object? previous;
}

/// Claims [ref] for [owner]: succeeds only when the location is empty, and is
/// idempotent for the same owner. A single-location compare-and-set, so of any
/// number of racing owners exactly one wins.
Future<ClaimOutcome> claim(RestDatabaseReference ref, String owner) async {
  _requireText(owner, 'owner');
  final result = await ref.atomicUpdate(
    (current) => current == null ? owner : keepCurrentValue,
  );
  if (result.applied) {
    return ClaimOutcome.claimed;
  }
  return result.value == owner
      ? ClaimOutcome.alreadyOwned
      : ClaimOutcome.heldByOther;
}

/// Releases [ref] if, and only if, it is held by [owner]. Returns whether it
/// released anything.
Future<bool> release(RestDatabaseReference ref, String owner) async {
  _requireText(owner, 'owner');
  final result = await ref.atomicUpdate(
    (current) => current == owner ? null : keepCurrentValue,
  );
  return result.applied;
}

/// Sets [ref] to [value] only if it is empty, already [value], or holds
/// exactly [auditedPlaceholder] (the string the rollout audit recorded for this
/// record). Any other current value, including a real uid, is left alone, so a
/// claimed record can never be taken over.
Future<ReplaceIfResult> replaceIf(
  RestDatabaseReference ref, {
  required String value,
  String? auditedPlaceholder,
}) async {
  _requireText(value, 'value');
  if (auditedPlaceholder != null) {
    _requireText(auditedPlaceholder, 'auditedPlaceholder');
  }
  Object? previous;
  final result = await ref.atomicUpdate((current) {
    previous = current;
    final replaceable =
        current == null ||
        (auditedPlaceholder != null && current == auditedPlaceholder);
    return replaceable ? value : keepCurrentValue;
  });
  return ReplaceIfResult(
    holdsValue: result.applied || result.value == value,
    previous: previous,
  );
}

void _requireText(String text, String name) {
  if (text.isEmpty) {
    throw ArgumentError.value(text, name, 'must not be empty');
  }
}
