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

/// `admin-update-tipper`: an administrator changes another tipper's name,
/// contact email or role. The paid-competition list is not here; an
/// administrator still sets that directly.
///
/// The tipper acted on is named in the request (that is the point), so the
/// caller is checked first, by [requireAdmin]. Everything that can refuse is
/// checked before the first write, so a refusal changes nothing. Then, under
/// the tipper's lease:
///
/// 1. the **name**, the only step that can lose to another tipper's claim, goes
///    first, as the same journalled, resumable claim move a tipper's own rename
///    uses; if it loses, nothing else has been touched;
/// 2. the **email** and **role** are written together in one atomic update, to
///    the private record and, in the legacy modes, to the public copy a 1.4.x
///    client still reads.
///
/// A field already holding the requested value is left alone and is not listed
/// in the result, so asking twice changes nothing the second time and a retry
/// after a crash finishes whatever was not done.
///
/// A role change cannot leave the database with no administrator, and only an
/// administrator with a working sign-in account counts. That check
/// and the write are not one atomic step, so two administrators demoting each
/// other in the same moment could both pass it; with a handful of
/// administrators that is accepted and repaired by hand.
Future<AdminUpdateTipperResult> adminUpdateTipper({
  required RestDatabase database,
  required CallerToken caller,
  required AdminUpdateTipperRequest request,
  required Admission admission,
  required Set<String> adminUids,
  int Function()? nowMs,
  Checkpoint? checkpoint,
}) async {
  requireAdmin(caller, adminUids);

  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final tipperId = request.tipperId;
  if (!isValidRtdbKey(tipperId)) {
    throw InvalidArgumentError('That tipper cannot be used.');
  }
  final name = request.name?.trim();
  if (name != null && !isValidAlias(name)) {
    throw InvalidArgumentError(
      'Please choose a name that is not blank and is at most $maxAliasLength characters.',
      reason: identityReasonInvalidAlias,
    );
  }
  final email = request.email?.trim();
  if (email != null && !isValidContactEmail(email)) {
    throw InvalidArgumentError(
      'Please give a valid email address.',
      reason: identityReasonInvalidEmail,
    );
  }
  final role = request.role;

  return withTipperLease(
    database,
    tipperId: tipperId,
    operationId: admission.operationId,
    nowMs: clock,
    body: () async {
      await finishPendingClaimMove(
        database,
        tipperId,
        admission.config,
        checkpoint,
      );

      final records = await loadTipperRecords(database);
      final target = records[tipperId];
      if (target == null) {
        throw NotFoundError('There is no such tipper.');
      }
      if (target.needsAudit) {
        throw FailedPreconditionError(
          'This tipper needs an administrator to repair it first.',
          reason: identityReasonNeedsAudit,
        );
      }

      final currentRole = target.fields['tipperRole'];
      final demoting =
          role == TipperRole.tipper && currentRole == TipperRole.admin.name;
      if (demoting) {
        var othersAdmin = false;
        for (final record in records.values) {
          if (record.id != tipperId &&
              record.fields['tipperRole'] == TipperRole.admin.name &&
              await _hasUsableAccount(database, record.id)) {
            othersAdmin = true;
            break;
          }
        }
        if (!othersAdmin) {
          throw FailedPreconditionError(
            'That would leave no administrator.',
            reason: identityReasonLastAdmin,
          );
        }
      }

      final changed = <String>[];

      // 1. The name: the one step another tipper's claim can refuse.
      if (name != null) {
        final toKey = aliasIndexKey(name);
        if (target.name == name) {
          await claim(database.ref('${paths.aliasIndexPath}/$toKey'), tipperId);
        } else {
          try {
            await performClaimMove(
              database,
              tipperId: tipperId,
              kind: ClaimKind.alias,
              toKey: toKey,
              toValue: name,
              mode: admission.config,
              nowMs: clock(),
              checkpoint: checkpoint,
            );
          } on ClaimMoveConflict {
            throw FailedPreconditionError(
              'That name is already taken.',
              reason: identityReasonAliasTaken,
            );
          }
          changed.add('name');
        }
        await checkpoint?.call('admin:name');
      }

      // 2. The email and the role, together.
      final legacy = admission.config.mode.writesLegacyPublicShape;
      final privateBase = '${_root(paths.tipperPrivatePath)}/$tipperId';
      final publicBase = '${_root(paths.tippersPath)}/$tipperId';
      final writes = <Object?, Object?>{};
      if (email != null && target.email != email) {
        writes['$privateBase/email'] = email;
        if (legacy) {
          writes['$publicBase/email'] = email;
        }
        changed.add('email');
      }
      if (role != null && currentRole != role.name) {
        writes['$privateBase/tipperRole'] = role.name;
        if (legacy) {
          writes['$publicBase/tipperRole'] = role.name;
        }
        changed.add('role');
      }
      if (writes.isNotEmpty) {
        await database.ref('/').update(writes);
      }

      return AdminUpdateTipperResult(tipperId: tipperId, changed: changed);
    },
  );
}

/// Whether the record has a sign-in account that works: its private `authuid`
/// is a real account and `/AuthIndex` points that account back at it. A
/// historical administrator record nobody can sign in to does not count as
/// "another administrator".
Future<bool> _hasUsableAccount(RestDatabase database, String tipperId) async {
  final uid =
      (await database
              .ref('${paths.tipperPrivatePath}/$tipperId/authuid')
              .once())
          .value;
  if (uid is! String || !isValidRtdbKey(uid)) {
    return false;
  }
  final indexed =
      (await database.ref('${paths.authIndexPath}/$uid').once()).value;
  return indexed == tipperId;
}

String _root(String path) => path.substring(1);
