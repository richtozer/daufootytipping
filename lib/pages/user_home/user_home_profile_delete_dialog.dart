import 'dart:developer';

import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_auth/app_root_navigator.dart';
import 'package:daufootytipping/services/account_deletion.dart';
import 'package:daufootytipping/services/tipper_link_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// Asks the signed-in person to confirm deleting their account, then does it. It
/// cannot be dismissed while the deletion is running.
Future<void> showDeleteAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const DeleteAccountDialog(),
  );
}

/// The confirmation, and the deletion itself. If the account is not deleted (it
/// is switched off, the server is busy, the sign-in again was cancelled) the
/// reason is shown here, under the question, and the dialog stays so that the
/// person can try again or back out. Nothing leaves the screen they are on.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, this.deleteAccount, this.onDeleted});

  /// Deletes the account: null on success, otherwise what to tell the person.
  /// Defaults to [TippersViewModel.deleteAccount].
  final Future<String?> Function()? deleteAccount;

  /// Runs once the account is gone. Defaults to forgetting the tipper kept on the
  /// device and returning to the sign-in page.
  final Future<void> Function()? onDeleted;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  String? _errorMessage;
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) {
      return;
    }
    setState(() {
      _deleting = true;
      _errorMessage = null;
    });
    String? failure;
    try {
      failure =
          await (widget.deleteAccount ??
              di<TippersViewModel>().deleteAccount)();
    } on Object catch (error) {
      log('DeleteAccountDialog: deleting the account failed: $error');
      failure = AccountDeletion.deletionFailedMessage;
    }
    if (failure == null) {
      // The account is gone, and the page this dialog sits on may already have
      // been replaced, so this does not depend on the dialog still being here.
      await (widget.onDeleted ?? _forgetAndReturnToSignIn)();
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _deleting = false;
      _errorMessage = failure;
    });
  }

  Future<void> _forgetAndReturnToSignIn() async {
    if (di.isRegistered<TipperLinkService>()) {
      await di<TipperLinkService>().forget();
    }
    di<AppRootNavigator>().returnToRoot();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(
        'Confirm Account Deletion',
        style: TextStyle(color: League.afl.colour),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Are you sure you want to delete your account? Any tips you have made, will be deleted. This action cannot be undone. Prior to your account be deleted, you may confirm your identity, otherwise your account will be deleted immediately.',
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _deleting ? null : _delete,
          child: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Delete', style: TextStyle(color: League.afl.colour)),
        ),
      ],
    );
  }
}
