import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/claim_moves.dart';
import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/linked_caller.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `update-tipper-alias`: the signed-in tipper changes their own alias.
///
/// Only the caller's own record can be changed: it is found from the verified
/// uid, never from the request. Alias uniqueness is enforced here, on the
/// server, by the claim in `/AliasIndex`, which closes the bypass that existed
/// while clients wrote `name` directly. The change is a journalled, resumable
/// claim move under the tipper's lease, so a crash at any step is completed by
/// the retry and two renames at once cannot leak a claim.
///
/// Asking for the alias the tipper already has changes nothing (and makes sure
/// the claim is held). A spelling change that keeps the same key, such as a
/// different case or spacing, only rewrites the name.
Future<UpdateTipperAliasResult> updateTipperAlias({
  required RestDatabase database,
  required CallerToken caller,
  required UpdateTipperAliasRequest request,
  required Admission admission,
  int Function()? nowMs,
  Checkpoint? checkpoint,
}) async {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final alias = request.alias.trim();
  if (!isValidAlias(alias)) {
    throw InvalidArgumentError(
      'Please choose an alias that is not blank and is at most $maxAliasLength characters.',
      reason: identityReasonInvalidAlias,
    );
  }
  final tipperId = await requireLinkedTipper(database, caller.uid);

  return withTipperLease(
    database,
    tipperId: tipperId,
    operationId: admission.operationId,
    nowMs: clock,
    body: () async {
      // Finish what a crashed earlier request left, before deciding that
      // there is nothing to do.
      await finishPendingClaimMove(
        database,
        tipperId,
        admission.config,
        checkpoint,
      );
      final current =
          (await database.ref('${paths.tippersPath}/$tipperId/name').once())
              .value;
      final toKey = aliasIndexKey(alias);
      if (current == alias) {
        // Nothing to change. Make sure the claim is held; one held by someone
        // else (a pre-existing duplicate) is left to the audit.
        await claim(database.ref('${paths.aliasIndexPath}/$toKey'), tipperId);
        return UpdateTipperAliasResult(tipperId: tipperId, alias: alias);
      }
      try {
        await performClaimMove(
          database,
          tipperId: tipperId,
          kind: ClaimKind.alias,
          toKey: toKey,
          toValue: alias,
          mode: admission.config,
          nowMs: clock(),
          checkpoint: checkpoint,
        );
      } on ClaimMoveConflict {
        throw FailedPreconditionError(
          'That alias is already taken. Please choose another.',
          reason: identityReasonAliasTaken,
        );
      }
      return UpdateTipperAliasResult(tipperId: tipperId, alias: alias);
    },
  );
}
