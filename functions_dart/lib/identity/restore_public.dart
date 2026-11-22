import 'package:dau_shared/dau_shared.dart';

/// Why a tipper could not be restored.
class RestoreFinding {
  const RestoreFinding(this.tipperId, this.problem);

  /// The tipper's database key, an opaque id.
  final String tipperId;

  /// What is wrong, in words that name no one.
  final String problem;

  @override
  String toString() => '$tipperId: $problem';
}

/// What restoring the public identity fields would write.
class RestorePlan {
  const RestorePlan({
    required this.patch,
    required this.recordsToRestore,
    required this.blocking,
    required this.differing,
    required this.placeholderNames,
  });

  /// `AllTippers/{id}/{field}` to the value to write, in a fixed order.
  final Map<String, Object?> patch;

  /// How many public records get at least one field back.
  final int recordsToRestore;

  /// Records that cannot be restored. While any remains, nothing is written.
  final List<RestoreFinding> blocking;

  /// Fields present in both places with different values. The public copy is
  /// kept, because a 1.4.x client can have written it more recently.
  final int differing;

  /// Records that carry the purge's placeholder name. Informational: the real
  /// name was never stored, so the placeholder stays.
  final int placeholderNames;

  bool get isBlocked => blocking.isNotEmpty;

  /// Nothing left to restore.
  bool get isEmpty => patch.isEmpty;

  int get fieldsToRestore => patch.length;
}

/// Plans the rollback after the purge (DESIGN-database-rules-phase4.md,
/// section 9): copies the purged fields of every tipper back from
/// `/TipperPrivate` to the public record, so that R1-compat and the 1.4.x
/// clients it serves find the shape they read.
///
/// - Only a field the public record lacks is written; one that is there stays
///   (it is at least as fresh, see `mergeTipperRecords`).
/// - `authuid` is written as `''` for a tipper whose private record has none (an
///   unlinked historical tipper): that is how the legacy shape says "no
///   account", and 1.4.x reads the field as text.
/// - The legacy fields in [tipperLegacyFieldNames] are not brought back; the
///   purge deleted them on purpose.
/// - A tipper with no `tipperRole`, or with no public record at all, cannot be
///   restored and blocks the plan. So does a public record that has no private
///   copy to restore from *and* lacks `authuid` or `tipperRole` (the fields the
///   legacy shape requires): it was purged, and nothing can put it back. Both
///   sets of ids are checked, not only the private ones.
///
/// [tippers] and [tipperPrivate] are the two nodes as read, `null` when absent.
/// Running the plan on data that has already been restored gives an empty plan.
RestorePlan planPublicIdentityRestore({
  required Object? tippers,
  required Object? tipperPrivate,
}) {
  final publicRecords = tippers is Map ? tippers : const <Object?, Object?>{};
  final privateRecords = tipperPrivate is Map
      ? tipperPrivate
      : const <Object?, Object?>{};

  final ids = <String>{
    ...privateRecords.keys.map((key) => key.toString()),
    ...publicRecords.keys.map((key) => key.toString()),
  }.toList()..sort();
  final patch = <String, Object?>{};
  final blocking = <RestoreFinding>[];
  var recordsToRestore = 0;
  var differing = 0;

  for (final id in ids) {
    final privateRecord = privateRecords[id];
    final publicRecord = publicRecords[id];
    if (privateRecord is! Map) {
      // Nothing to restore from. Fine if the public record already has what the
      // legacy shape requires (it was never purged); otherwise it cannot be put right.
      if (publicRecord is Map) {
        final lacks = <String>[
          if (publicRecord['authuid'] is! String) 'authuid',
          if (publicRecord['tipperRole'] is! String ||
              (publicRecord['tipperRole'] as String).isEmpty)
            'tipperRole',
        ];
        if (lacks.isNotEmpty) {
          blocking.add(
            RestoreFinding(
              id,
              'has a public record but no private one to restore ${lacks.join(' and ')} from',
            ),
          );
        }
      }
      continue;
    }
    if (publicRecord is! Map) {
      blocking.add(
        RestoreFinding(id, 'has a private record but no public one'),
      );
      continue;
    }

    final fromRecord = <String, Object?>{};
    for (final field in tipperPrivateFieldNames) {
      final privateValue = privateRecord[field];
      if (privateValue == null) {
        continue;
      }
      final publicValue = publicRecord[field];
      if (publicValue == null) {
        fromRecord[field] = privateValue;
      } else if (publicValue != privateValue) {
        differing += 1;
      }
    }
    // The legacy shape says "no account" with an empty authuid, not a missing one.
    if (publicRecord['authuid'] == null && !fromRecord.containsKey('authuid')) {
      fromRecord['authuid'] = '';
    }

    final role = publicRecord['tipperRole'] ?? fromRecord['tipperRole'];
    if (role is! String || role.isEmpty) {
      blocking.add(RestoreFinding(id, 'has no tipperRole to restore'));
      continue;
    }

    if (fromRecord.isNotEmpty) {
      recordsToRestore += 1;
      for (final entry in fromRecord.entries) {
        patch['$tippersRestorePath/$id/${entry.key}'] = entry.value;
      }
    }
  }

  var placeholderNames = 0;
  for (final entry in publicRecords.entries) {
    final name = entry.value is Map ? (entry.value as Map)['name'] : null;
    if (name is String && name == placeholderTipperName(entry.key.toString())) {
      placeholderNames += 1;
    }
  }

  return RestorePlan(
    patch: patch,
    recordsToRestore: recordsToRestore,
    blocking: blocking,
    differing: differing,
    placeholderNames: placeholderNames,
  );
}

/// The patch's path prefix, without a leading slash: a root-level update.
const String tippersRestorePath = 'AllTippers';
