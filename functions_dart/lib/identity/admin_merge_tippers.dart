import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admin_gate.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/claim_moves.dart';
import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/identity/tipper_records.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `admin-merge-tippers`: merges the `original` tipper record into the `target`
/// and removes the original, as the admin screen's merge has always done (see
/// [AdminMergeTippersRequest] for the options).
///
/// The record is changed in an order that makes the **same request, run again,
/// finish a merge that was cut short**, with no journal: everything the later
/// steps need is read from records that still exist until the very last step,
/// and every step checks what is already done.
///
/// Under the leases of **both** tippers (taken in id order, so two merges cannot
/// deadlock):
///
/// 1. the original's **tips** move to the target, one atomic update per
///    competition (the target's tips for those games, then the original's node
///    removed). Where both tipped a game the original's tip wins, as before;
/// 2. the original's **push tokens** move to the target, and their ownership in
///    `/TokenOwners` with them;
/// 3. the **login address** (if asked): the original's claim is released, then
///    the target claims it through the usual claim move;
/// 4. the **sign-in account**, if the original has one: the target's own account
///    stops having access first, then the target's `authuid` takes the
///    original's, then `/AuthIndex` is pointed at the target (the commit);
/// 5. **claims** are tidied: the original's alias and login claims released and
///    the target made sure of its own (a duplicate pair can share a key, and the
///    claim move does not claim a key that has not changed), placeholder,
///    stale journal and create intent dropped;
/// 6. only then are the original's two records **removed**, together.
///
/// A dry run reads and validates and writes nothing. The result counts what this
/// call did, so a retry reports only the work that was left.
Future<AdminMergeTippersResult> adminMergeTippers({
  required RestDatabase database,
  required CallerToken caller,
  required AdminMergeTippersRequest request,
  required Admission admission,
  required Set<String> adminUids,
  int Function()? nowMs,
  Checkpoint? checkpoint,
}) async {
  requireAdmin(caller, adminUids);

  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final originalId = request.originalId;
  final targetId = request.targetId;
  if (!isValidRtdbKey(originalId) || !isValidRtdbKey(targetId)) {
    throw InvalidArgumentError('That tipper cannot be used.');
  }
  if (originalId == targetId) {
    throw InvalidArgumentError('Choose two different tippers to merge.');
  }

  if (request.dryRun) {
    final pair = await _loadPair(database, originalId, targetId);
    await _refuseKnownConflicts(database, request, pair.original);
    final tips = await _tipsToMove(database, originalId, targetId);
    return AdminMergeTippersResult(
      targetId: targetId,
      tipsMoved: request.mergeTips ? tips.moved : 0,
      tipsReplaced: request.mergeTips ? tips.replaced : 0,
      loginMoved: request.mergeLogon && _hasLogon(pair.original),
      accountMoved: await _accountOf(database, pair.original) != null,
      dryRun: true,
    );
  }

  final ids = <String>[originalId, targetId]..sort();
  Future<AdminMergeTippersResult> merge() =>
      _merge(database, request, admission, clock, checkpoint);
  return withTipperLease(
    database,
    tipperId: ids.first,
    operationId: admission.operationId,
    nowMs: clock,
    body: () => withTipperLease(
      database,
      tipperId: ids.last,
      operationId: admission.operationId,
      nowMs: clock,
      body: merge,
    ),
  );
}

Future<AdminMergeTippersResult> _merge(
  RestDatabase database,
  AdminMergeTippersRequest request,
  Admission admission,
  int Function() clock,
  Checkpoint? checkpoint,
) async {
  final originalId = request.originalId;
  final targetId = request.targetId;
  final mode = admission.config;
  final legacy = mode.mode.writesLegacyPublicShape;

  // What an earlier, interrupted request on either record left half done.
  await finishPendingClaimMove(database, originalId, mode, checkpoint);
  await finishPendingClaimMove(database, targetId, mode, checkpoint);

  final pair = await _loadPair(database, originalId, targetId);
  final original = pair.original;
  final target = pair.target;

  // A clash that can be seen now is refused now, before any tip has moved.
  await _refuseKnownConflicts(database, request, original);

  // 1. Tips.
  var tipsMoved = 0;
  var tipsReplaced = 0;
  if (request.mergeTips) {
    final tips = await _tipsToMove(database, originalId, targetId);
    for (final entry in tips.byComp.entries) {
      await database.ref('/').update(<Object?, Object?>{
        for (final tip in entry.value.entries)
          '${_root(paths.tipsPathRoot)}/${entry.key}/$targetId/${tip.key}':
              tip.value,
        '${_root(paths.tipsPathRoot)}/${entry.key}/$originalId': null,
      });
    }
    tipsMoved = tips.moved;
    tipsReplaced = tips.replaced;
    await checkpoint?.call('merge:tips');
  }

  // 2. Push tokens, and who owns them.
  await _moveTokens(database, originalId, targetId);
  await checkpoint?.call('merge:tokens');

  // 3. The login address.
  final originalLogon = original.logon;
  var loginMoved = false;
  if (request.mergeLogon && _hasLogon(original)) {
    final key = logonIndexKey(originalLogon!);
    await release(database.ref('${paths.logonIndexPath}/$key'), originalId);
    try {
      await performClaimMove(
        database,
        tipperId: targetId,
        kind: ClaimKind.logon,
        toKey: key,
        toValue: originalLogon,
        mode: mode,
        nowMs: clock(),
        checkpoint: checkpoint,
      );
    } on ClaimMoveConflict {
      throw _claimed();
    }
    loginMoved = true;
    await checkpoint?.call('merge:logon');
  }

  // 4. The sign-in account.
  final originalUid = await _accountOf(database, original);
  var accountMoved = false;
  if (originalUid != null) {
    final targetUid = await _accountOf(database, target);
    // The target's own account stops having access first.
    if (targetUid != null && targetUid != originalUid) {
      await release(
        database.ref('${paths.authIndexPath}/$targetUid'),
        targetId,
      );
    }
    await checkpoint?.call('merge:old-account');

    final targetAuthuid = database.ref(
      '${paths.tipperPrivatePath}/$targetId/authuid',
    );
    final expected = (await targetAuthuid.once()).value;
    final taken = await targetAuthuid.atomicUpdate(
      (current) => current == originalUid
          ? keepCurrentValue
          : current == expected
          ? originalUid
          : keepCurrentValue,
    );
    if (!taken.applied && taken.value != originalUid) {
      throw _claimed();
    }
    if (legacy) {
      await database
          .ref('${paths.tippersPath}/$targetId/authuid')
          .atomicUpdate(
            (current) =>
                current == originalUid ? keepCurrentValue : originalUid,
          );
    }
    await checkpoint?.call('merge:authuid');

    final index = database.ref('${paths.authIndexPath}/$originalUid');
    final committed = await index.atomicUpdate(
      (current) => current == null || current == originalId
          ? targetId
          : keepCurrentValue,
    );
    if (!committed.applied && committed.value != targetId) {
      throw _claimed();
    }
    accountMoved = true;
    await checkpoint?.call('merge:index');
  }

  // 5. Claims and leftovers.
  final originalName = original.name;
  if (originalName != null && isValidAlias(originalName)) {
    await release(
      database.ref('${paths.aliasIndexPath}/${aliasIndexKey(originalName)}'),
      originalId,
    );
  }
  final targetName = target.name;
  if (targetName != null && isValidAlias(targetName)) {
    await claim(
      database.ref('${paths.aliasIndexPath}/${aliasIndexKey(targetName)}'),
      targetId,
    );
  }
  if (_hasLogon(original)) {
    await release(
      database.ref('${paths.logonIndexPath}/${logonIndexKey(originalLogon!)}'),
      originalId,
    );
  }
  final targetLogon = loginMoved ? originalLogon : target.logon;
  if (targetLogon != null && normaliseEmail(targetLogon).isNotEmpty) {
    await claim(
      database.ref('${paths.logonIndexPath}/${logonIndexKey(targetLogon)}'),
      targetId,
    );
  }
  await database.ref('${paths.placeholdersPath}/$originalId').remove();
  await database.ref('${paths.claimMovesPath}/$originalId').remove();
  if (originalUid != null) {
    final intent = database.ref('${paths.createIntentsPath}/$originalUid');
    await intent.atomicUpdate(
      (current) => current is Map && current['tipperId'] == originalId
          ? null
          : keepCurrentValue,
    );
  }
  await checkpoint?.call('merge:claims');

  // 6. The commit: the original's two records go together.
  await database.ref('/').update(<Object?, Object?>{
    '${_root(paths.tippersPath)}/$originalId': null,
    '${_root(paths.tipperPrivatePath)}/$originalId': null,
  });

  return AdminMergeTippersResult(
    targetId: targetId,
    tipsMoved: tipsMoved,
    tipsReplaced: tipsReplaced,
    loginMoved: loginMoved,
    accountMoved: accountMoved,
    dryRun: false,
  );
}

/// Refuses, before anything has moved, a merge that would clash with a third
/// tipper: the original's login address (when it is being moved) or its
/// sign-in account is already held by a record that is neither the original nor
/// the target. The preview and the merge share this, so a preview that says yes
/// does not turn into a refusal after the history has already changed. The
/// steps still guard against a clash that appears in the meantime.
Future<void> _refuseKnownConflicts(
  RestDatabase database,
  AdminMergeTippersRequest request,
  TipperRecord original,
) async {
  bool heldByThird(Object? holder) =>
      holder != null &&
      holder != request.originalId &&
      holder != request.targetId;

  if (request.mergeLogon && _hasLogon(original)) {
    final key = logonIndexKey(original.logon!);
    final holder =
        (await database.ref('${paths.logonIndexPath}/$key').once()).value;
    if (heldByThird(holder)) {
      throw _clash();
    }
  }
  final uid = await _accountOf(database, original);
  if (uid != null) {
    final holder =
        (await database.ref('${paths.authIndexPath}/$uid').once()).value;
    if (heldByThird(holder)) {
      throw _clash();
    }
  }
}

FailedPreconditionError _clash() => FailedPreconditionError(
  'This merge would clash with another tipper: the login address or the '
  'account is already held by someone else. Nothing was changed.',
  reason: identityReasonClaimed,
);

class _Pair {
  const _Pair(this.original, this.target);

  final TipperRecord original;
  final TipperRecord target;
}

/// Both records, joined, or the reason the merge cannot go ahead.
Future<_Pair> _loadPair(
  RestDatabase database,
  String originalId,
  String targetId,
) async {
  final records = await loadTipperRecords(database);
  final original = records[originalId];
  final target = records[targetId];
  if (original == null) {
    throw NotFoundError('The tipper to merge from does not exist.');
  }
  if (target == null) {
    throw NotFoundError('The tipper to merge into does not exist.');
  }
  for (final record in <TipperRecord>[original, target]) {
    if (record.needsAudit) {
      throw FailedPreconditionError(
        'A tipper in this merge needs an administrator to repair it first.',
        reason: identityReasonNeedsAudit,
      );
    }
  }
  return _Pair(original, target);
}

bool _hasLogon(TipperRecord record) {
  final logon = record.logon;
  return logon != null && normaliseEmail(logon).isNotEmpty;
}

/// The sign-in account the record is linked to, or null if it has none: no
/// `authuid`, or only the placeholder the audit recorded for it.
Future<String?> _accountOf(RestDatabase database, TipperRecord record) async {
  final uid =
      (await database
              .ref('${paths.tipperPrivatePath}/${record.id}/authuid')
              .once())
          .value;
  if (uid is! String || uid.isEmpty) {
    return null;
  }
  final placeholder =
      (await database.ref('${paths.placeholdersPath}/${record.id}').once())
          .value;
  if (placeholder == uid || !isValidRtdbKey(uid)) {
    return null;
  }
  return uid;
}

class _TipsToMove {
  const _TipsToMove(this.byComp, this.moved, this.replaced);

  /// For each competition, the original's tips by game.
  final Map<String, Map<Object?, Object?>> byComp;
  final int moved;
  final int replaced;
}

Future<_TipsToMove> _tipsToMove(
  RestDatabase database,
  String originalId,
  String targetId,
) async {
  final comps = (await database.ref(paths.daucompsPath).once()).value;
  final byComp = <String, Map<Object?, Object?>>{};
  var moved = 0;
  var replaced = 0;
  if (comps is Map) {
    for (final comp
        in comps.keys.map((key) => key.toString()).toList()..sort()) {
      final originalTips =
          (await database.ref('${paths.tipsPathRoot}/$comp/$originalId').once())
              .value;
      if (originalTips is! Map || originalTips.isEmpty) {
        continue;
      }
      final targetTips =
          (await database.ref('${paths.tipsPathRoot}/$comp/$targetId').once())
              .value;
      byComp[comp] = Map<Object?, Object?>.from(originalTips);
      moved += originalTips.length;
      if (targetTips is Map) {
        replaced += originalTips.keys.where(targetTips.containsKey).length;
      }
    }
  }
  return _TipsToMove(byComp, moved, replaced);
}

/// Moves the original's push tokens to the target (keeping a token the target
/// already has) and hands their ownership in `/TokenOwners` over with them.
Future<void> _moveTokens(
  RestDatabase database,
  String originalId,
  String targetId,
) async {
  final tokens =
      (await database.ref('${paths.tokensPath}/$originalId').once()).value;
  if (tokens is! Map || tokens.isEmpty) {
    return;
  }
  final held =
      (await database.ref('${paths.tokensPath}/$targetId').once()).value;
  await database.ref('/').update(<Object?, Object?>{
    for (final token in tokens.entries)
      if (held is! Map || !held.containsKey(token.key))
        '${_root(paths.tokensPath)}/$targetId/${token.key}': token.value,
    '${_root(paths.tokensPath)}/$originalId': null,
  });
  for (final token in tokens.keys) {
    await database
        .ref('${paths.tokenOwnersPath}/$token')
        .atomicUpdate(
          (current) => current is Map && current['owner'] == originalId
              ? <String, Object?>{
                  ...Map<String, Object?>.from(current),
                  'owner': targetId,
                }
              : keepCurrentValue,
        );
  }
}

FailedPreconditionError _claimed() => FailedPreconditionError(
  'Part of this merge is already held by another account. Nothing more was changed.',
  reason: identityReasonClaimed,
);

String _root(String path) => path.substring(1);
