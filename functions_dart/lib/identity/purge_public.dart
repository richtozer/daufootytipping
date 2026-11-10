import 'package:dau_shared/dau_shared.dart';

/// The two nodes, as the keys of a multi-path update from the database root
/// (without a leading slash, as the restore tool writes them).
const String _publicNode = 'AllTippers';
const String _privateNode = 'TipperPrivate';

/// Why a tipper cannot be purged yet.
class PurgeFinding {
  const PurgeFinding(this.tipperId, this.problem);

  /// The tipper's database key, an opaque id.
  final String tipperId;

  /// What is wrong, in words that name no one.
  final String problem;

  @override
  String toString() => '$tipperId: $problem';
}

/// What purging the public identity fields would write.
class PurgePlan {
  const PurgePlan({
    required this.patch,
    required this.recordsToPurge,
    required this.fieldsToRemove,
    required this.loginTimesPreserved,
    required this.placeholderNames,
    required this.blocking,
  });

  /// Paths from the database root to the value to write (`null` removes), in a
  /// fixed order. It holds no email address, login or account id: only removals,
  /// the occasional login time and placeholder name.
  final Map<String, Object?> patch;

  /// How many public records lose at least one field.
  final int recordsToPurge;

  /// How many public fields are removed.
  final int fieldsToRemove;

  /// Records whose public login time is later than the private one: the later
  /// time is written to the private record, in the same update that removes the
  /// public one, so a sign-in made by a 1.4.x client since the backfill is not
  /// lost.
  final int loginTimesPreserved;

  /// Records left with none of the public fields, which are given a placeholder
  /// name so that they do not vanish (the database keeps no empty node).
  final int placeholderNames;

  /// Records that cannot be purged yet. While any remains, nothing is written.
  final List<PurgeFinding> blocking;

  bool get isBlocked => blocking.isNotEmpty;

  /// Nothing left to purge.
  bool get isEmpty => patch.isEmpty;
}

/// Plans cutover step B (DESIGN-database-rules-phase4.md, section 8): removes the
/// private identity fields (`tipperPrivateFieldNames`) and the two legacy fields
/// (`tipperLegacyFieldNames`) from every public record, once the private record
/// holds everything the public one did.
///
/// It destroys nothing it cannot account for. For each public field it is about
/// to remove:
///
/// - the private record must hold the same value (an empty public `authuid` means
///   "no account" and equals a missing private one; two times are the same if
///   they are the same instant, whatever their text);
/// - a **later public `acctLoggedOnUTC`** is not lost: a 1.4.x client refreshes
///   it at every sign-in, so it can be ahead of the private copy. It is written
///   to the private record in the same update;
/// - any other difference, a value only the public record has, or a public record
///   with identity fields and **no private record at all** (a tipper created by a
///   1.4.x client after the backfill) is *unresolved*. The whole plan is blocked,
///   with the opaque id and the field names, until the final backfill and
///   reconcile have dealt with it.
///
/// A record left with none of the public fields is given a placeholder name. The
/// legacy fields are removed unconditionally. Running the plan on data that has
/// already been purged gives an empty plan.
///
/// [tippers] and [tipperPrivate] are the two nodes as read, `null` when absent.
PurgePlan planPublicIdentityPurge({
  required Object? tippers,
  required Object? tipperPrivate,
}) {
  final publicRecords = tippers is Map ? tippers : const <Object?, Object?>{};
  final privateRecords = tipperPrivate is Map
      ? tipperPrivate
      : const <Object?, Object?>{};

  final ids = publicRecords.keys.map((key) => key.toString()).toList()..sort();
  final patch = <String, Object?>{};
  final blocking = <PurgeFinding>[];
  var recordsToPurge = 0;
  var fieldsToRemove = 0;
  var loginTimesPreserved = 0;
  var placeholderNames = 0;

  for (final id in ids) {
    final publicRecord = publicRecords[id];
    if (publicRecord is! Map) {
      continue;
    }
    final hasIdentityFields = tipperPrivateFieldNames.any(
      (field) => publicRecord[field] != null,
    );
    final hasLegacyFields = tipperLegacyFieldNames.any(
      (field) => publicRecord[field] != null,
    );
    if (!hasIdentityFields && !hasLegacyFields) {
      continue; // already purged
    }

    final privateRecord = privateRecords[id];
    if (hasIdentityFields && privateRecord is! Map) {
      blocking.add(
        PurgeFinding(
          id,
          'has identity fields in its public record but no private record: '
          'run the final backfill pass first',
        ),
      );
      continue;
    }

    final recordPatch = <String, Object?>{};
    final problems = <String>[];
    var preservedLogin = false;
    if (privateRecord is Map) {
      for (final field in tipperPrivateFieldNames) {
        final publicValue = publicRecord[field];
        if (publicValue == null) {
          continue;
        }
        final privateValue = privateRecord[field];
        if (_sameValue(field, publicValue, privateValue)) {
          recordPatch['$_publicNode/$id/$field'] = null;
        } else if (field == 'acctLoggedOnUTC' && privateValue != null) {
          final publicTime = _time(publicValue);
          final privateTime = _time(privateValue);
          if (publicTime == null || privateTime == null) {
            problems.add('acctLoggedOnUTC cannot be compared');
            continue;
          }
          if (publicTime.isAfter(privateTime)) {
            recordPatch['$_privateNode/$id/$field'] = publicValue;
            preservedLogin = true;
          }
          recordPatch['$_publicNode/$id/$field'] = null;
        } else if (privateValue == null) {
          problems.add('$field is in the public record only');
        } else {
          problems.add('$field differs between the public and private records');
        }
      }
    }
    if (problems.isNotEmpty) {
      blocking.add(PurgeFinding(id, problems.join('; ')));
      continue;
    }
    for (final field in tipperLegacyFieldNames) {
      if (publicRecord[field] != null) {
        recordPatch['$_publicNode/$id/$field'] = null;
      }
    }

    final removed = recordPatch.keys
        .where((path) => path.startsWith('$_publicNode/'))
        .length;
    final stillPublic = tipperPublicFieldNames.any(
      (field) => publicRecord[field] != null,
    );
    if (!stillPublic) {
      recordPatch['$_publicNode/$id/name'] = placeholderTipperName(id);
      placeholderNames += 1;
    }
    patch.addAll(recordPatch);
    recordsToPurge += 1;
    fieldsToRemove += removed;
    if (preservedLogin) {
      loginTimesPreserved += 1;
    }
  }

  return PurgePlan(
    patch: patch,
    recordsToPurge: recordsToPurge,
    fieldsToRemove: fieldsToRemove,
    loginTimesPreserved: loginTimesPreserved,
    placeholderNames: placeholderNames,
    blocking: blocking,
  );
}

/// Whether the public value says what the private one does.
bool _sameValue(String field, Object publicValue, Object? privateValue) {
  if (publicValue == privateValue) {
    return true;
  }
  // The legacy shape says "no account" with an empty authuid; the private record
  // simply has none.
  if (field == 'authuid' && publicValue == '' && privateValue == null) {
    return true;
  }
  if (field == 'acctCreatedUTC' || field == 'acctLoggedOnUTC') {
    final publicTime = _time(publicValue);
    final privateTime = _time(privateValue);
    return publicTime != null &&
        privateTime != null &&
        publicTime.isAtSameMomentAs(privateTime);
  }
  return false;
}

DateTime? _time(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;
