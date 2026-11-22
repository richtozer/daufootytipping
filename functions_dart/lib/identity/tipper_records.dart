import 'package:dart_functions/identity/backend_tippers.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// One tipper as the link logic sees it: the public record and the private
/// record joined (a field the public record carries wins, as in the backend
/// readers), and which of the two exist.
class TipperRecord {
  const TipperRecord({
    required this.id,
    required this.fields,
    required this.hasPublic,
    required this.hasPrivate,
  });

  final String id;
  final Map<String, Object?> fields;
  final bool hasPublic;
  final bool hasPrivate;

  /// A record that is missing either half has not been through the backfill (a
  /// 1.4.x client created it after the last pass) or is damaged. Nothing can
  /// safely be linked to it, and it must not be mistaken for "no account".
  bool get needsAudit => !hasPublic || !hasPrivate;

  String? get logon => _text(fields['logon']);
  String? get email => _text(fields['email']);
  String? get name => _text(fields['name']);
  String? get authuid => _text(fields['authuid']);

  /// Whether this record's login or contact email is [normalisedEmail].
  bool matchesEmail(String normalisedEmail) =>
      _normalised(logon) == normalisedEmail ||
      _normalised(email) == normalisedEmail;
}

String? _text(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

String? _normalised(String? email) =>
    email == null ? null : normaliseEmail(email);

/// Every tipper, public and private halves joined. Two reads of about 200 small
/// records, made only on the first-link path.
Future<Map<String, TipperRecord>> loadTipperRecords(
  RestDatabase database,
) async {
  final publicValue = (await database.ref(paths.tippersPath).once()).value;
  final privateValue =
      (await database.ref(paths.tipperPrivatePath).once()).value;
  final publicRecords = publicValue is Map ? publicValue : const {};
  final privateRecords = privateValue is Map ? privateValue : const {};

  final ids = <String>{
    for (final key in publicRecords.keys) key.toString(),
    for (final key in privateRecords.keys) key.toString(),
  };
  return <String, TipperRecord>{
    for (final id in ids.toList()..sort())
      id: _record(id, publicRecords[id], privateRecords[id]),
  };
}

TipperRecord _record(String id, Object? publicRaw, Object? privateRaw) {
  final hasPublic = publicRaw is Map;
  final hasPrivate = privateRaw is Map;
  return TipperRecord(
    id: id,
    fields: mergeTipperRecords(hasPublic ? publicRaw : const {}, privateRaw),
    hasPublic: hasPublic,
    hasPrivate: hasPrivate,
  );
}

/// The records whose login or contact email is [email] (normalised). The union
/// of the two fields: a person arriving with an address matches every record
/// that holds it in either place, so one record's login equal to another's
/// contact email is an ambiguity, not a first-match-wins.
List<TipperRecord> findCandidates(
  Iterable<TipperRecord> records,
  String email,
) {
  final wanted = normaliseEmail(email);
  return <TipperRecord>[
    for (final record in records)
      if (record.matchesEmail(wanted)) record,
  ];
}
