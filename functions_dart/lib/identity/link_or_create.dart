import 'dart:math';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/claim_moves.dart';
import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/push_id.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/identity/tipper_records.dart';
import 'package:dart_functions/identity/tipper_shapes.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `link-or-create-tipper` (DESIGN-database-rules-phase4.md, section 6f).
///
/// Ties the signed-in account to its tipper record, or creates one, and is also
/// the sign-in refresh for an account that is already linked. The caller has
/// been admitted by `runAdmitted`; [admission] carries the mode in force.
///
/// The verified login address comes only from [caller]'s token. Nothing is
/// written unless the request is unambiguous: more than one matching record, or
/// any matching record that has not been through the backfill, is refused
/// before the first write.
Future<LinkOrCreateTipperResult> linkOrCreateTipper({
  required RestDatabase database,
  required CallerToken caller,
  required LinkOrCreateTipperRequest request,
  required Admission admission,
  int Function()? nowMs,
  Checkpoint? checkpoint,
  Random? random,
}) async {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final email = _verifiedEmail(caller);
  if (!isValidRtdbKey(caller.uid)) {
    throw InvalidArgumentError('This account cannot be used.');
  }
  final context = _Context(
    database: database,
    caller: caller,
    email: email,
    admission: admission,
    clock: clock,
    checkpoint: checkpoint,
  );

  final resolution = await resolveCallerTipper(database, caller.uid);
  if (resolution is ResolvedCaller) {
    return _refresh(context, resolution.tipperId);
  }
  if (resolution is UnresolvedCaller &&
      resolution.reason != CallerFailure.noMapping) {
    // An index entry that does not check out is flagged for repair, never
    // trusted and never returned (D2).
    throw FailedPreconditionError(
      'This account needs an administrator to repair it. Please contact support.',
      reason: identityReasonNeedsAudit,
    );
  }

  final records = await loadTipperRecords(database);
  final candidates = findCandidates(records.values, email);
  if (candidates.any((record) => record.needsAudit)) {
    throw FailedPreconditionError(
      'This record is waiting to be checked by an administrator. Please contact support.',
      reason: identityReasonNeedsAudit,
    );
  }
  if (candidates.length > 1) {
    throw FailedPreconditionError(
      'More than one tipper matches this account. Please contact support.',
      reason: identityReasonAmbiguous,
    );
  }
  if (candidates.length == 1) {
    return _link(context, candidates.single);
  }
  return _create(context, request, random);
}

/// What every step needs.
class _Context {
  const _Context({
    required this.database,
    required this.caller,
    required this.email,
    required this.admission,
    required this.clock,
    required this.checkpoint,
  });

  final RestDatabase database;
  final CallerToken caller;
  final String email;
  final Admission admission;
  final int Function() clock;
  final Checkpoint? checkpoint;

  bool get legacyShape => admission.config.mode.writesLegacyPublicShape;

  Future<void> at(String step) async => checkpoint?.call(step);
}

/// The verified login address, or the refusal that explains why there is none.
String _verifiedEmail(CallerToken caller) {
  if (caller.isAnonymous) {
    throw PermissionDeniedError(
      'Anonymous accounts cannot be linked to a tipper.',
      reason: identityReasonNotLinked,
    );
  }
  final email = caller.email;
  if (email == null || !caller.emailVerified || normaliseEmail(email).isEmpty) {
    throw PermissionDeniedError(
      'Please verify your email address first.',
      reason: identityReasonUnverifiedEmail,
    );
  }
  return email;
}

FailedPreconditionError _claimed() => FailedPreconditionError(
  'This tipper is already linked to another account. Please contact support.',
  reason: identityReasonClaimed,
);

/// Link an existing record. No access exists until the account is claimed in
/// `/AuthIndex` (the commit), so every earlier state grants none.
Future<LinkOrCreateTipperResult> _link(
  _Context context,
  TipperRecord record,
) => withTipperLease(
  context.database,
  tipperId: record.id,
  operationId: context.admission.operationId,
  nowMs: context.clock,
  body: () async {
    final database = context.database;
    final uid = context.caller.uid;
    final authuidRef = database.ref(
      '${paths.tipperPrivatePath}/${record.id}/authuid',
    );
    final placeholderRef = database.ref(
      '${paths.placeholdersPath}/${record.id}',
    );
    final stored = (await placeholderRef.once()).value;
    final placeholder = stored is String && stored.isNotEmpty ? stored : null;

    // 1. Take the record's private `authuid`: it must be empty, already this
    //    account, or exactly the placeholder the audit recorded for it. Any
    //    other value, or an ownership that cannot be established, is claimed.
    final replaced = await replaceIf(
      authuidRef,
      value: uid,
      auditedPlaceholder: placeholder,
    );
    if (!replaced.holdsValue) {
      throw _claimed();
    }
    await context.at('link:private-authuid');

    // 2. The login address. It grants no access, so it is done before the
    //    commit: a conflict leaves nothing linked.
    try {
      await _settleLogon(context, record);
    } on ClaimMoveConflict {
      await _restoreAuthuid(authuidRef, uid, replaced.previous);
      throw _claimed();
    }
    await context.at('link:logon');

    // 3. The commit.
    final committed = await claim(
      database.ref('${paths.authIndexPath}/$uid'),
      record.id,
    );
    if (committed == ClaimOutcome.heldByOther) {
      await _restoreAuthuid(authuidRef, uid, replaced.previous);
      throw _claimed();
    }
    await context.at('link:committed');

    // 4. Refresh the profile. Access exists now and nothing below removes it.
    await _writeProfile(context, record);
    await context.at('link:profile');
    await _dropFinishedIntent(database, uid, record.id);
    if (placeholder != null) {
      await release(placeholderRef, placeholder);
    }
    return LinkOrCreateTipperResult(
      tipperId: record.id,
      outcome: LinkOutcome.linked,
    );
  },
);

/// Undo step 1 after a lost race, putting back what was there.
Future<void> _restoreAuthuid(
  RestDatabaseReference authuidRef,
  String uid,
  Object? previous,
) async {
  if (previous == uid) {
    return;
  }
  await authuidRef.atomicUpdate(
    (current) => current == uid ? previous : keepCurrentValue,
  );
}

/// Makes the record's login address the verified one, claiming it. Already the
/// same address: only the claim is made sure of (a claim held by someone else
/// is left to the audit rather than failing a link that is otherwise sound).
/// A different address is a contact change, so it is a journalled claim move.
Future<void> _settleLogon(_Context context, TipperRecord record) async {
  final stored = record.logon;
  final wantedKey = logonIndexKey(context.email);
  if (stored != null &&
      normaliseEmail(stored) == normaliseEmail(context.email)) {
    await claim(
      context.database.ref('${paths.logonIndexPath}/$wantedKey'),
      record.id,
    );
    return;
  }
  await performClaimMove(
    context.database,
    tipperId: record.id,
    kind: ClaimKind.logon,
    toKey: wantedKey,
    toValue: context.email,
    mode: context.admission.config,
    nowMs: context.clock(),
    checkpoint: context.checkpoint,
  );
}

/// The refresh a sign-in always does: clear `isAnonymous`, stamp the time of
/// this sign-in, fill the contact email only when it is missing or invalid,
/// and follow a changed photo. In the legacy modes the public record gets the
/// same changes the 1.4.x client would have made; in `final` it only gets the
/// photo, because the public record no longer carries private fields.
Future<void> _writeProfile(_Context context, TipperRecord record) async {
  final database = context.database;
  final stamp = stampOf(context.clock());
  final fillEmail = !isValidContactEmail(record.email);

  await database.ref('${paths.tipperPrivatePath}/${record.id}').update({
    'isAnonymous': false,
    'acctLoggedOnUTC': stamp,
    if (fillEmail) 'email': context.email,
  });

  final photo = context.caller.pictureUrl;
  final publicChanges = <String, Object?>{
    if (photo != null && photo != record.fields['photoURL']) 'photoURL': photo,
    if (context.legacyShape) ...<String, Object?>{
      'authuid': context.caller.uid,
      'isAnonymous': false,
      'acctLoggedOnUTC': stamp,
      if (fillEmail) 'email': context.email,
    },
  };
  if (publicChanges.isNotEmpty) {
    await database
        .ref('${paths.tippersPath}/${record.id}')
        .update(publicChanges);
  }
}

/// The account is already linked: validate (done) and refresh. A changed login
/// address is moved last, so a conflict there cannot stop the refresh.
Future<LinkOrCreateTipperResult> _refresh(
  _Context context,
  String tipperId,
) => withTipperLease(
  context.database,
  tipperId: tipperId,
  operationId: context.admission.operationId,
  nowMs: context.clock,
  body: () async {
    final records = await loadTipperRecords(context.database);
    final record = records[tipperId];
    if (record == null || record.needsAudit) {
      throw FailedPreconditionError(
        'This account needs an administrator to repair it. Please contact support.',
        reason: identityReasonNeedsAudit,
      );
    }
    await _writeProfile(context, record);
    await context.at('refresh:profile');
    await _dropFinishedIntent(context.database, context.caller.uid, tipperId);
    await _dropPlaceholder(context.database, tipperId);
    final stored = record.logon;
    if (stored == null ||
        normaliseEmail(stored) != normaliseEmail(context.email)) {
      try {
        await _settleLogon(context, record);
      } on ClaimMoveConflict {
        throw _claimed();
      }
    }
    return LinkOrCreateTipperResult(
      tipperId: tipperId,
      outcome: LinkOutcome.existing,
    );
  },
);

/// Create a new record for an account nothing matched. Order (D3): a durable
/// intent so a retry reuses the same tipper id, then the alias and login
/// claims, then the records, then the `/AuthIndex` claim as the commit, then
/// the intent is dropped. A conflict rolls back everything claimed so far.
Future<LinkOrCreateTipperResult> _create(
  _Context context,
  LinkOrCreateTipperRequest request,
  Random? random,
) async {
  final database = context.database;
  final uid = context.caller.uid;

  final allowed =
      (await database
              .ref('${paths.configPathRoot}/${paths.createLinkedTipperKey}')
              .once())
          .value ==
      true;
  if (!allowed) {
    throw FailedPreconditionError(
      'New tippers cannot be created right now.',
      reason: identityReasonCreationDisabled,
    );
  }
  final alias = request.alias?.trim();
  if (alias == null || !isValidAlias(alias)) {
    throw InvalidArgumentError(
      'Please choose an alias that is not blank and is at most $maxAliasLength characters.',
      reason: identityReasonInvalidAlias,
    );
  }
  final aliasKey = aliasIndexKey(alias);
  final logonKey = logonIndexKey(context.email);
  final now = context.clock();

  final intent = await _claimIntent(
    database.ref('${paths.createIntentsPath}/$uid'),
    freshId: newPushId(now, random: random),
    nowMs: now,
    aliasKey: aliasKey,
    logonKey: logonKey,
  );
  final tipperId = intent.tipperId;

  return withTipperLease(
    database,
    tipperId: tipperId,
    operationId: context.admission.operationId,
    nowMs: context.clock,
    body: () async {
      await context.at('create:intent');

      // A retry that changed the alias or address: let go of the old claims.
      for (final stale in intent.staleAliasKeys) {
        await release(database.ref('${paths.aliasIndexPath}/$stale'), tipperId);
      }
      for (final stale in intent.staleLogonKeys) {
        await release(database.ref('${paths.logonIndexPath}/$stale'), tipperId);
      }

      final aliasRef = database.ref('${paths.aliasIndexPath}/$aliasKey');
      if (await claim(aliasRef, tipperId) == ClaimOutcome.heldByOther) {
        await _abandonCreate(context, tipperId, aliasKey: null, logonKey: null);
        final twin = await _linkedMeanwhile(context);
        if (twin != null) {
          return twin;
        }
        throw FailedPreconditionError(
          'That alias is already taken. Please choose another.',
          reason: identityReasonAliasTaken,
        );
      }
      await context.at('create:alias');

      final logonRef = database.ref('${paths.logonIndexPath}/$logonKey');
      if (await claim(logonRef, tipperId) == ClaimOutcome.heldByOther) {
        await _abandonCreate(
          context,
          tipperId,
          aliasKey: aliasKey,
          logonKey: null,
        );
        final twin = await _linkedMeanwhile(context);
        if (twin != null) {
          return twin;
        }
        throw _claimed();
      }
      await context.at('create:logon');

      await _writeNewRecords(context, tipperId, alias);
      await context.at('create:records');

      final committed = await claim(
        database.ref('${paths.authIndexPath}/$uid'),
        tipperId,
      );
      if (committed == ClaimOutcome.heldByOther) {
        await _abandonCreate(
          context,
          tipperId,
          aliasKey: aliasKey,
          logonKey: logonKey,
          removeRecords: true,
        );
        throw _claimed();
      }
      await context.at('create:committed');

      await database.ref('${paths.createIntentsPath}/$uid').remove();
      return LinkOrCreateTipperResult(
        tipperId: tipperId,
        outcome: LinkOutcome.created,
      );
    },
  );
}

/// Writes the two halves of a new record, each only if absent, so a retry after
/// a crash does not disturb what is already there.
Future<void> _writeNewRecords(
  _Context context,
  String tipperId,
  String alias,
) async {
  final database = context.database;
  final now = context.clock();
  final privateRecord = newPrivateRecord(
    authuid: context.caller.uid,
    email: context.email,
    nowMs: now,
  );
  final publicRecord = newPublicRecord(
    legacyShape: context.legacyShape,
    name: alias,
    authuid: context.caller.uid,
    email: context.email,
    nowMs: now,
    photoUrl: context.caller.pictureUrl,
  );

  final privateRef = database.ref('${paths.tipperPrivatePath}/$tipperId');
  final existingPrivate = await privateRef.atomicUpdate(
    (current) => current == null ? privateRecord : keepCurrentValue,
  );
  final stored = existingPrivate.value;
  final storedAuthuid = stored is Map ? stored['authuid'] : null;
  if (storedAuthuid != context.caller.uid) {
    throw _claimed();
  }
  await database
      .ref('${paths.tippersPath}/$tipperId')
      .atomicUpdate(
        (current) => current == null ? publicRecord : keepCurrentValue,
      );
}

/// Rolls back a create that lost a race: the claims it made, optionally the
/// records it wrote, and the intent.
Future<void> _abandonCreate(
  _Context context,
  String tipperId, {
  required String? aliasKey,
  required String? logonKey,
  bool removeRecords = false,
}) async {
  final database = context.database;
  if (aliasKey != null) {
    await release(database.ref('${paths.aliasIndexPath}/$aliasKey'), tipperId);
  }
  if (logonKey != null) {
    await release(database.ref('${paths.logonIndexPath}/$logonKey'), tipperId);
  }
  if (removeRecords) {
    await database.ref('${paths.tipperPrivatePath}/$tipperId').remove();
    await database.ref('${paths.tippersPath}/$tipperId').remove();
  }
  await database
      .ref('${paths.createIntentsPath}/${context.caller.uid}')
      .remove();
}

/// The create intent for this account: the tipper id to use, and any claims an
/// earlier attempt made under a different alias or address that must now go.
class _Intent {
  const _Intent({
    required this.tipperId,
    required this.staleAliasKeys,
    required this.staleLogonKeys,
  });

  final String tipperId;
  final List<String> staleAliasKeys;
  final List<String> staleLogonKeys;
}

/// Claims `/CreateIntents/{uid}` for this account, or reuses the one an earlier
/// attempt left, so a retry or a double-tap makes exactly one record. The
/// stored intent names the alias and login keys, so a retry with different ones
/// can release the old claims instead of leaking them.
Future<_Intent> _claimIntent(
  RestDatabaseReference ref, {
  required String freshId,
  required int nowMs,
  required String aliasKey,
  required String logonKey,
}) async {
  var tipperId = freshId;
  final staleAlias = <String>[];
  final staleLogon = <String>[];
  await ref.atomicUpdate((current) {
    staleAlias.clear();
    staleLogon.clear();
    if (current is Map && current['tipperId'] is String) {
      tipperId = current['tipperId'] as String;
      final storedAlias = current['aliasKey'];
      final storedLogon = current['logonKey'];
      if (storedAlias is String && storedAlias != aliasKey) {
        staleAlias.add(storedAlias);
      }
      if (storedLogon is String && storedLogon != logonKey) {
        staleLogon.add(storedLogon);
      }
      if (staleAlias.isEmpty && staleLogon.isEmpty) {
        return keepCurrentValue;
      }
      return <String, Object?>{
        ...Map<String, Object?>.from(current),
        'aliasKey': aliasKey,
        'logonKey': logonKey,
      };
    }
    tipperId = freshId;
    return <String, Object?>{
      'tipperId': freshId,
      'createdAtMs': nowMs,
      'aliasKey': aliasKey,
      'logonKey': logonKey,
    };
  });
  return _Intent(
    tipperId: tipperId,
    staleAliasKeys: List<String>.of(staleAlias),
    staleLogonKeys: List<String>.of(staleLogon),
  );
}

/// A create that crashed after its commit leaves its intent behind. Once the
/// account resolves to that tipper the intent has done its job, so drop it; an
/// intent for a different tipper is not ours to touch.
Future<void> _dropFinishedIntent(
  RestDatabase database,
  String uid,
  String tipperId,
) async {
  await database
      .ref('${paths.createIntentsPath}/$uid')
      .atomicUpdate(
        (current) => current is Map && current['tipperId'] == tipperId
            ? null
            : keepCurrentValue,
      );
}

/// A link that crashed after its commit but before dropping the placeholder
/// audit entry. The record belongs to an account now, so the entry no longer
/// describes anything.
Future<void> _dropPlaceholder(RestDatabase database, String tipperId) async {
  await database.ref('${paths.placeholdersPath}/$tipperId').remove();
}

/// If this account was linked while the call was working (a double tap whose
/// twin committed first), the call has not failed: the account is linked.
/// Returns that result, or null if the account is still unlinked.
Future<LinkOrCreateTipperResult?> _linkedMeanwhile(_Context context) async {
  final resolution = await resolveCallerTipper(
    context.database,
    context.caller.uid,
  );
  if (resolution is! ResolvedCaller) {
    return null;
  }
  return LinkOrCreateTipperResult(
    tipperId: resolution.tipperId,
    outcome: LinkOutcome.existing,
  );
}
