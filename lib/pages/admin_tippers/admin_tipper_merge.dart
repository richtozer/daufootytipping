import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class AdminTipperMergeEditPage extends StatefulWidget {
  final TippersViewModel tippersViewModel;
  final Tipper? sourceTipper;

  const AdminTipperMergeEditPage(this.tippersViewModel, this.sourceTipper,
      {super.key});

  @override
  State<AdminTipperMergeEditPage> createState() =>
      _AdminTipperMergeEditPageState();
}

class _AdminTipperMergeEditPageState extends State<AdminTipperMergeEditPage> {
  Tipper? targetTipper;
  DAUCompsViewModel? compsViewModel = di<DAUCompsViewModel>();

  @override
  void initState() {
    super.initState();
  }

  Future<int> getTipsToBeMerged(
      Tipper sourceTipper, Tipper targetTipper, DAUComp comp) {
    return widget.tippersViewModel
        .mergeTipsForComp(sourceTipper, targetTipper, comp, trialMode: true);
  }

  Future<bool?> _showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Merge'),
          content: Text(
              'Are you sure you want to merge these tippers? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text('Merge'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Tipper> targetTippers = widget.tippersViewModel.tippers
        .where((tipper) => tipper.dbkey != widget.sourceTipper?.dbkey)
        .toList()
      ..sort((a, b) => a.name!.compareTo(b.name!));

    return Scaffold(
      appBar: AppBar(
        title: Text('Merge Tippers'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                'WARNING: This action will merge 2 accounts by migrating the 1) logon email and 2) tips from the source account to the target account. If this is successful the source account will be deleted. This cannot be undone.\n\nMerging a lot of tips can take some time, make sure the source account is the newer account, as that should have less tips to merge. Keep the app open to allow long merges to complete. Once the source tipper disappears from the Tipper list, the merge is complete.\n\nThe 1) Alias name, and 2) Comms email will not be merged.',
                style: TextStyle(color: Colors.red),
              ),
              SizedBox(height: 16),
              Text('Select the target tipper to merge to:'),
              SizedBox(height: 16),
              Row(
                children: [
                  Text('Source: '),
                  Text(
                    widget.sourceTipper?.name ?? 'No source tipper selected',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w300),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Text('Target: '),
                  DropdownButton<Tipper>(
                    hint: Text('Tipper to merge to'),
                    value: targetTipper,
                    onChanged: (Tipper? newValue) {
                      setState(() {
                        targetTipper = newValue;
                      });
                    },
                    items: targetTippers
                        .map<DropdownMenuItem<Tipper>>((Tipper tipper) {
                      return DropdownMenuItem<Tipper>(
                        value: tipper,
                        child: Text(tipper.name!),
                      );
                    }).toList(),
                  ),
                ],
              ),
              SizedBox(height: 16),
              if (targetTipper != null && widget.sourceTipper != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('The logon email change:'),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Flexible(
                          child: Text(
                            widget.sourceTipper!.logon ?? '',
                            softWrap: true,
                            maxLines: 2,
                          ),
                        ),
                        Icon(Icons.arrow_forward),
                        Flexible(
                          child: Stack(
                            children: [
                              Text(
                                targetTipper!.logon ?? '',
                                softWrap: true,
                                maxLines: 2,
                              ),
                              Positioned.fill(
                                child: Icon(
                                  Icons.clear,
                                  color:
                                      Colors.red.withAlpha((0.5 * 255).toInt()),
                                  size: 50,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text('The following tips (if any) will be merged:'),
                    SizedBox(height: 8),
                    for (var comp in compsViewModel!.daucomps)
                      FutureBuilder<int>(
                        future: getTipsToBeMerged(
                            widget.sourceTipper!, targetTipper!, comp),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return CircularProgressIndicator(
                                color: Colors.orange);
                          } else if (snapshot.hasError) {
                            return Text('Error: ${snapshot.error}');
                          } else if (snapshot.hasData && snapshot.data! > 0) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Text(comp.name),
                                Text('${snapshot.data} tips'),
                              ],
                            );
                          } else {
                            return Container(); // Return an empty container if tip count is 0
                          }
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        '--end of list--',
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (targetTipper != null && widget.sourceTipper != null) {
                        bool? confirmed =
                            await _showConfirmationDialog(context);
                        if (confirmed == true) {
                          widget.tippersViewModel.mergeTippers(
                              widget.sourceTipper!, targetTipper!, true, true,
                              trialMode: false);
                          // show progress of the merge
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Merging logon and tips of ${widget.sourceTipper!.name} into ${targetTipper!.name}'),
                            ),
                          );
                          // navigate back 2 pages to the tippers list
                          Navigator.pop(context);
                          Navigator.pop(context);
                        }
                      } else {
                        // Show an error message if tippers are not selected
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Please select a target tipper to merge.'),
                          ),
                        );
                      }
                    },
                    child: Text('Merge'),
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
