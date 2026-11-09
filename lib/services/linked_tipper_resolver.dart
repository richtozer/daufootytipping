import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/models/identity_callables.dart';

/// The signed-in account, as far as linking needs to know it.
class LinkAccount {
  const LinkAccount({
    required this.uid,
    required this.isAnonymous,
    this.photoUrl,
  });

  final String uid;

  /// A guest browsing without an account. A guest is never linked or saved.
  final bool isAnonymous;

  final String? photoUrl;
}

/// The reads the link depends on: the caller's own `AuthIndex` entry, the private
/// record that entry names, and the public record. Each throws when the read
/// fails (a refusal or no connection); a successful read of nothing returns null,
/// and that is the only thing that means "not there".
abstract interface class IdentityReads {
  Future<String?> authIndexEntry(String uid);

  Future<Map<String, dynamic>?> privateRecord(String tipperId);

  Future<Map<String, dynamic>?> publicRecord(String tipperId);
}

/// [IdentityReads] over the configured Realtime Database.
class DatabaseIdentityReads implements IdentityReads {
  Future<Object?> _value(String path) async =>
      (await configuredDatabaseRef(path).get()).value;

  Map<String, dynamic>? _record(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  @override
  Future<String?> authIndexEntry(String uid) async {
    final value = await _value('${paths.authIndexPath}/$uid');
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<Map<String, dynamic>?> privateRecord(String tipperId) async =>
      _record(await _value('${paths.tipperPrivatePath}/$tipperId'));

  @override
  Future<Map<String, dynamic>?> publicRecord(String tipperId) async =>
      _record(await _value('${paths.tippersPath}/$tipperId'));
}

/// How linking ended.
enum LinkStatus {
  /// The account is linked to a tipper record: [LinkResolution.tipper] is it.
  linked,

  /// A guest: [LinkResolution.tipper] is a local, unsaved tipper.
  guest,

  /// No record matches this account, and creating one needs an alias.
  needsAlias,

  /// Not now: the server or the connection is not available. Trying again shortly
  /// may work; nothing about the account has been decided.
  unavailable,

  /// The server refused, and [LinkResolution.message] says why. [reason] is the
  /// machine-readable one.
  refused,
}

class LinkResolution {
  const LinkResolution._(
    this.status, {
    this.tipper,
    this.outcome,
    this.message,
    this.reason,
  });

  const LinkResolution.linked(Tipper tipper, {LinkOutcome? outcome})
    : this._(LinkStatus.linked, tipper: tipper, outcome: outcome);

  const LinkResolution.guest(Tipper tipper)
    : this._(LinkStatus.guest, tipper: tipper);

  const LinkResolution.needsAlias() : this._(LinkStatus.needsAlias);

  const LinkResolution.unavailable(String message)
    : this._(LinkStatus.unavailable, message: message);

  const LinkResolution.refused(String message, {String? reason})
    : this._(LinkStatus.refused, message: message, reason: reason);

  final LinkStatus status;
  final Tipper? tipper;

  /// Set when the server was asked: whether the account was already linked,
  /// linked to an existing record, or had a record created.
  final LinkOutcome? outcome;

  final String? message;
  final String? reason;
}

/// Finds the tipper the signed-in account belongs to (DESIGN-database-rules-phase4.md,
/// P3), without scanning the tipper list.
///
/// 1. A guest has no record and needs no server.
/// 2. Read my own `AuthIndex` entry and the private record it names. If that record
///    names me too, the link is valid and nothing else is asked of the server.
/// 3. Otherwise ask `link-or-create-tipper`, which links by verified email or, given an
///    alias, creates a record. Called without an alias when nothing matches, it
///    answers `invalid_alias`: that is [LinkStatus.needsAlias].
///
/// **A failed read is never "missing".** A refusal or a lost connection is retried
/// with a short back-off and then reported as [LinkStatus.unavailable]; only a
/// successful read of nothing sends the account to the server to be linked.
class LinkedTipperResolver {
  LinkedTipperResolver({
    required IdentityReads reads,
    required IdentityService identity,
    required Future<List<DAUComp>> Function(List compKeys) resolveComps,
    List<Duration> retryDelays = const <Duration>[
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
    this.readTimeout = const Duration(seconds: 10),
    this.compsTimeout = const Duration(seconds: 15),
    Future<void> Function(Duration)? delay,
  }) : _reads = reads,
       _identity = identity,
       _resolveComps = resolveComps,
       _retryDelays = retryDelays,
       _delay = delay ?? ((Duration d) => Future<void>.delayed(d));

  final IdentityReads _reads;
  final IdentityService _identity;
  final Future<List<DAUComp>> Function(List compKeys) _resolveComps;
  final List<Duration> _retryDelays;
  final Duration readTimeout;

  /// How long to wait for the competitions to load before carrying on without the
  /// tipper's paid ones. The public tipper list brings them in a moment later (the
  /// same as for a tipper opened from the kept copy), so waiting forever would only
  /// trade a brief gap for a sign-in that never finishes.
  final Duration compsTimeout;
  final Future<void> Function(Duration) _delay;

  Future<LinkResolution> resolve(LinkAccount account, {String? alias}) async {
    if (account.isAnonymous) {
      return LinkResolution.guest(_guestTipper(account));
    }
    try {
      final String? known = await _read(
        () => _reads.authIndexEntry(account.uid),
      );
      if (known != null) {
        final (privateRecord, publicRecord) = await _readRecords(known);
        if (privateRecord != null && privateRecord['authuid'] == account.uid) {
          return await _linked(
            account,
            known,
            privateRecord,
            publicRecord,
            null,
          );
        }
        // An entry the record does not back is not trusted, and not repaired here:
        // the server validates it, and links or refuses.
        log(
          'LinkedTipperResolver: the index entry is not backed by its record',
        );
      }
      return await _ask(account, alias);
    } on _ReadFailed catch (failure) {
      log('LinkedTipperResolver: a read failed: ${failure.cause}');
      return const LinkResolution.unavailable(
        'Could not reach the server. Please check your connection and try again.',
      );
    }
  }

  Future<LinkResolution> _ask(LinkAccount account, String? alias) async {
    final LinkOrCreateTipperResult result;
    try {
      result = await _identity.linkOrCreateTipper(alias: alias);
    } on IdentityFailure catch (failure) {
      return _fromFailure(failure, hadAlias: alias != null);
    }
    final (privateRecord, publicRecord) = await _readRecords(result.tipperId);
    return _linked(
      account,
      result.tipperId,
      privateRecord,
      publicRecord,
      result.outcome,
    );
  }

  /// The private and public records of [tipperId], read together: neither depends on
  /// the other, so one round trip does for both.
  Future<(Map<String, dynamic>?, Map<String, dynamic>?)> _readRecords(
    String tipperId,
  ) async {
    final records = await Future.wait<Map<String, dynamic>?>(
      <Future<Map<String, dynamic>?>>[
        _read(() => _reads.privateRecord(tipperId)),
        _read(() => _reads.publicRecord(tipperId)),
      ],
    );
    return (records[0], records[1]);
  }

  Future<LinkResolution> _linked(
    LinkAccount account,
    String tipperId,
    Map<String, dynamic>? privateRecord,
    Map<String, dynamic>? publicRecord,
    LinkOutcome? outcome,
  ) async {
    if (publicRecord == null || privateRecord == null) {
      // The server has just said this account is linked, so its records exist; not
      // seeing them yet is a delay, not an answer.
      return const LinkResolution.unavailable(
        'Your account is not ready yet. Please try again in a moment.',
      );
    }
    final tipper = Tipper.fromRecords(
      key: tipperId,
      authuid: account.uid,
      publicRecord: publicRecord,
      privateRecord: privateRecord,
    );
    try {
      await tipper
          .loadCompsPaidFor(publicRecord['compsParticipatedIn'], _resolveComps)
          .timeout(compsTimeout);
    } on TimeoutException {
      log(
        'LinkedTipperResolver: the competitions have not loaded; carrying on without the paid ones',
      );
    }
    return LinkResolution.linked(tipper, outcome: outcome);
  }

  LinkResolution _fromFailure(
    IdentityFailure failure, {
    required bool hadAlias,
  }) {
    final reason = failure.reason;
    if (reason == reasons.identityReasonInvalidAlias && !hadAlias) {
      return const LinkResolution.needsAlias();
    }
    if (failure.isRetryable || failure.isNotAvailable) {
      return LinkResolution.unavailable(
        failure.isBusy
            ? 'Your account is being updated. Please try again in a moment.'
            : "We can't sign you in right now. Please try again shortly. If it keeps happening, tap Get help.",
      );
    }
    switch (failure.kind) {
      case IdentityFailureKind.unauthenticated:
        return LinkResolution.refused(
          'Please sign out and sign in again.',
          reason: reason,
        );
      case IdentityFailureKind.refused:
        return LinkResolution.refused(failure.message, reason: reason);
      case IdentityFailureKind.transient:
      case IdentityFailureKind.unexpected:
        return LinkResolution.refused(
          'Something went wrong signing you in. Please try again. If it keeps happening, tap Get help.',
          reason: reason,
        );
    }
  }

  Tipper _guestTipper(LinkAccount account) => Tipper(
    name: account.uid.length > 5 ? account.uid.substring(0, 5) : account.uid,
    email: null,
    authuid: account.uid,
    photoURL: account.photoUrl,
    tipperRole: TipperRole.tipper,
    isAnonymous: true,
    compsPaidFor: <DAUComp>[],
  );

  Future<T> _read<T>(Future<T> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation().timeout(readTimeout);
      } on Object catch (error) {
        if (attempt >= _retryDelays.length) {
          throw _ReadFailed(error);
        }
        await _delay(_retryDelays[attempt]);
      }
    }
  }
}

class _ReadFailed implements Exception {
  const _ReadFailed(this.cause);

  final Object cause;
}
