import 'package:dart_functions/errors.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// Joins a tipper's public record with its private record into one map shaped
/// like the legacy record, which is what the backend's readers were written for.
///
/// A private field is taken only when the public record does not carry it. Until
/// the purge, a 1.4.x client can still write the public copy directly, so a field
/// that is present there is at least as fresh as the private copy. After the
/// purge the public copy is gone and the private record answers. A missing
/// private record is ordinary (before the backfill), and a private record with no
/// public record is never read, because the loaders start from the public list.
Map<String, Object?> mergeTipperRecords(
  Map<Object?, Object?> publicRecord,
  Object? privateRecord,
) {
  final merged = <String, Object?>{
    for (final entry in publicRecord.entries) entry.key.toString(): entry.value,
  };
  if (privateRecord is! Map) {
    return merged;
  }
  for (final field in tipperPrivateFieldNames) {
    if (!merged.containsKey(field) && privateRecord.containsKey(field)) {
      merged[field] = privateRecord[field];
    }
  }
  return merged;
}

/// Builds the backend's view of a tipper from a record in either shape.
///
/// Scoring and the app-badge count read `isAnonymous`, `name` and
/// `compsParticipatedIn`. The other identity fields ride along because
/// [Tipper] requires them; nothing here uses them to make a decision.
Tipper backendTipperFromRecord(String tipperId, Map<String, Object?> record) {
  final identity = TipperPrivate.fromJson(record);
  final name = record['name'];
  final photoUrl = record['photoURL'];
  return Tipper(
    dbkey: tipperId,
    authuid: identity.authuid ?? '',
    email: identity.email,
    logon: identity.logon,
    name: name is String ? name : tipperId,
    tipperRole: identity.tipperRole,
    photoURL: photoUrl is String ? photoUrl : null,
    compsPaidFor: _paidComps(record['compsParticipatedIn']),
    acctCreatedUTC: identity.acctCreatedUTC,
    acctLoggedOnUTC: identity.acctLoggedOnUTC,
    isAnonymous: identity.isAnonymous,
  );
}

/// Every tipper, public record joined with private record where one exists.
///
/// [db] is whichever handle the scoring command opened (the REST client, the
/// Admin SDK or the standalone emulator client). They share only
/// `ref(path).once()` returning a snapshot with `value`, hence `dynamic`.
Future<List<Tipper>> loadBackendTippers(dynamic db) async {
  final publicValue = (await db.ref(paths.tippersPath).once()).value;
  if (publicValue is! Map) {
    return <Tipper>[];
  }
  final privateValue = (await db.ref(paths.tipperPrivatePath).once()).value;
  final privateRecords = privateValue is Map ? privateValue : const {};

  final tippers = <Tipper>[];
  for (final entry in publicValue.entries) {
    final publicRecord = entry.value;
    if (publicRecord is! Map) {
      continue;
    }
    final tipperId = entry.key.toString();
    tippers.add(
      backendTipperFromRecord(
        tipperId,
        mergeTipperRecords(publicRecord, privateRecords[entry.key]),
      ),
    );
  }
  return tippers;
}

/// One tipper, or [NotFoundError] when there is no public record for the id.
Future<Tipper> loadBackendTipper(dynamic db, String tipperId) async {
  final publicValue =
      (await db.ref('${paths.tippersPath}/$tipperId').once()).value;
  if (publicValue is! Map) {
    throw NotFoundError('Tipper not found for key: $tipperId');
  }
  final privateValue =
      (await db.ref('${paths.tipperPrivatePath}/$tipperId').once()).value;
  return backendTipperFromRecord(
    tipperId,
    mergeTipperRecords(publicValue, privateValue),
  );
}

/// The comps a tipper has paid for. Scoring only compares comp keys, so each is
/// a bare [DAUComp] carrying just its key.
List<DAUComp> _paidComps(Object? compsParticipatedIn) {
  final Iterable<Object?> rawCompKeys;
  if (compsParticipatedIn is List) {
    rawCompKeys = compsParticipatedIn;
  } else if (compsParticipatedIn is Map) {
    rawCompKeys = compsParticipatedIn.values;
  } else {
    return const <DAUComp>[];
  }

  final comps = <DAUComp>[];
  for (final rawCompKey in rawCompKeys) {
    final compKey = rawCompKey.toString().trim();
    if (compKey.isEmpty) {
      continue;
    }
    comps.add(
      DAUComp(
        dbkey: compKey,
        name: compKey,
        aflFixtureJsonURL: Uri.parse(
          'https://example.invalid/afl-fixtures.json',
        ),
        nrlFixtureJsonURL: Uri.parse(
          'https://example.invalid/nrl-fixtures.json',
        ),
        daurounds: const [],
      ),
    );
  }
  return comps;
}
