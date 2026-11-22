import 'package:dau_shared/dau_shared.dart';

/// How the callables write the time: the form `DateTime.toString()` gives for a
/// UTC time, which is how every existing tipper record stores it
/// (`2026-03-01 04:05:06.000Z`), so old and new records read alike.
String stampOf(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
      isUtc: true,
    ).toString();

/// The private record of a new tipper (`/TipperPrivate/{id}`).
Map<String, Object?> newPrivateRecord({
  required String authuid,
  required String email,
  required int nowMs,
}) => <String, Object?>{
  'authuid': authuid,
  'tipperRole': TipperRole.tipper.name,
  'email': email,
  'logon': email,
  'isAnonymous': false,
  'acctCreatedUTC': stampOf(nowMs),
  'acctLoggedOnUTC': stampOf(nowMs),
};

/// The public record of a new tipper (`/AllTippers/{id}`).
///
/// With [legacyShape] (modes `pilot` and `coexist`) it carries every field the
/// 1.4.x client writes, so that client still finds the tipper by scanning the
/// public list. Without it (mode `final`) only the public fields.
Map<String, Object?> newPublicRecord({
  required bool legacyShape,
  required String name,
  required String authuid,
  required String email,
  required int nowMs,
  String? photoUrl,
}) => <String, Object?>{
  'name': name,
  'photoURL': ?photoUrl,
  if (legacyShape) ...<String, Object?>{
    'authuid': authuid,
    'email': email,
    'logon': email,
    'tipperRole': TipperRole.tipper.name,
    'isAnonymous': false,
    'acctCreatedUTC': stampOf(nowMs),
    'acctLoggedOnUTC': stampOf(nowMs),
  },
};
