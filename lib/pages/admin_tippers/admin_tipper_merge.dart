import 'package:dau_shared/dau_shared.dart' show AdminMergeTippersResult;
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_failure_message.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// Merges one tipper (the source, which is deleted) into another (the target):
/// the tips and the login move across. The server does the merge, one step at a
/// time, and a merge that is cut short is finished by running it again.
class AdminTipperMergeEditPage extends StatefulWidget {
  final TippersViewModel tippersViewModel;
  final Tipper? sourceTipper;

  const AdminTipperMergeEditPage(
    this.tippersViewModel,
    this.sourceTipper, {
    super.key,
  });

  static const Key previewKey = ValueKey('merge-preview');
  static const Key mergeButtonKey = ValueKey('merge-button');

  @override
  State<AdminTipperMergeEditPage> createState() =>
      _AdminTipperMergeEditPageState();
}

class _AdminTipperMergeEditPageState extends State<AdminTipperMergeEditPage> {
  Tipper? targetTipper;
  Future<AdminMergeTippersResult>? _preview;
  bool _canMerge = false;
  bool _merging = false;

  Future<AdminMergeTippersResult> _callMerge(
    Tipper source,
    Tipper target, {
    required bool dryRun,
  }) {
    final String? sourceKey = source.dbkey;
    final String? targetKey = target.dbkey;
    if (sourceKey == null || targetKey == null) {
      return Future<AdminMergeTippersResult>.error(
        StateError('both tippers need a record key to be merged'),
      );
    }
    return di<IdentityService>().adminMergeTippers(
      originalId: sourceKey,
      targetId: targetKey,
      mergeTips: true,
      mergeLogon: true,
      dryRun: dryRun,
    );
  }

  /// Asks the server what merging would do, without doing it.
  void _chooseTarget(Tipper? target) {
    final Tipper? source = widget.sourceTipper;
    final Future<AdminMergeTippersResult>? preview =
        source == null || target == null
        ? null
        : _callMerge(source, target, dryRun: true).then((
            AdminMergeTippersResult result,
          ) {
            if (mounted && identical(targetTipper, target)) {
              setState(() => _canMerge = true);
            }
            return result;
          });
    // A refusal is shown by the preview below, once the page has built; until
    // then it must not count as an unhandled error.
    preview?.ignore();
    setState(() {
      targetTipper = target;
      _canMerge = false;
      _preview = preview;
    });
  }

  Future<bool?> _showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Merge'),
          content: const Text(
            'Are you sure you want to merge these tippers? This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Merge'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _merge(BuildContext context) async {
    final Tipper? source = widget.sourceTipper;
    final Tipper? target = targetTipper;
    if (source == null || target == null) {
      return;
    }
    final bool? confirmed = await _showConfirmationDialog(context);
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _merging = true);
    try {
      final AdminMergeTippersResult result = await _callMerge(
        source,
        target,
        dryRun: false,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Merged ${source.name} into ${target.name}: '
            '${result.tipsMoved} tips moved.',
          ),
        ),
      );
      // back to the tippers list: the source tipper is gone
      Navigator.pop(context);
      Navigator.pop(context);
    } on IdentityFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _merging = false);
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Merge not completed'),
          content: Text(
            '${adminFailureMessage(failure)}\n\nIf the merge was cut short, '
            'running it again finishes it.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _previewFor(Tipper source, Tipper target) {
    return FutureBuilder<AdminMergeTippersResult>(
      key: AdminTipperMergeEditPage.previewKey,
      future: _preview,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<AdminMergeTippersResult> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.orange),
              );
            }
            final Object? error = snapshot.error;
            if (error != null) {
              return Text(
                error is IdentityFailure
                    ? adminFailureMessage(error)
                    : 'Could not check the merge: $error',
                style: const TextStyle(color: Colors.red),
              );
            }
            final AdminMergeTippersResult? result = snapshot.data;
            if (result == null) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Merging would:'),
                const SizedBox(height: 8),
                Text('• move ${result.tipsMoved} tips to ${target.name}'),
                if (result.tipsReplaced > 0)
                  Text(
                    '• replace ${result.tipsReplaced} tips ${target.name} already '
                    'has for the same games',
                  ),
                Text(
                  result.loginMoved
                      ? '• move the login to ${target.name}'
                      : '• leave the login as it is',
                ),
                Text(
                  result.accountMoved
                      ? '• move the sign-in account to ${target.name}'
                      : '• leave the sign-in account as it is',
                ),
                Text('• delete ${source.name}'),
              ],
            );
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Tipper? source = widget.sourceTipper;
    final Tipper? target = targetTipper;
    final List<Tipper> targetTippers =
        widget.tippersViewModel.tippers
            .where((tipper) => tipper.dbkey != source?.dbkey)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return AppAdminPage(
      title: 'Merge Tippers',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'WARNING: This action will merge 2 accounts by migrating the 1) logon email and 2) tips from the source account to the target account. If this is successful the source account will be deleted. This cannot be undone.\n\nThe server does the merge in steps. If it is cut short, run the same merge again and it will finish.\n\nThe 1) Alias name, and 2) Comms email will not be merged.',
                style: TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              const Text('Select the target tipper to merge to:'),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Source: '),
                  Text(
                    source?.name ?? 'No source tipper selected',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Target: '),
                  DropdownButton<Tipper>(
                    hint: const Text('Tipper to merge to'),
                    value: target,
                    onChanged: _merging ? null : _chooseTarget,
                    items: targetTippers.map<DropdownMenuItem<Tipper>>((
                      Tipper tipper,
                    ) {
                      return DropdownMenuItem<Tipper>(
                        value: tipper,
                        child: Text(tipper.name),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (target != null && source != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('The logon email change:'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Flexible(
                          child: Text(
                            source.logon ?? '',
                            softWrap: true,
                            maxLines: 2,
                          ),
                        ),
                        const Icon(Icons.arrow_forward),
                        Flexible(
                          child: Stack(
                            children: [
                              Text(
                                target.logon ?? '',
                                softWrap: true,
                                maxLines: 2,
                              ),
                              Positioned.fill(
                                child: Icon(
                                  Icons.clear,
                                  color: Colors.red.withAlpha(
                                    (0.5 * 255).toInt(),
                                  ),
                                  size: 50,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _previewFor(source, target),
                    const SizedBox(height: 16),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _merging
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    key: AdminTipperMergeEditPage.mergeButtonKey,
                    onPressed: _canMerge && !_merging
                        ? () => _merge(context)
                        : null,
                    child: _merging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Merge'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
