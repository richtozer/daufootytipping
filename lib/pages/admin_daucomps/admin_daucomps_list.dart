import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

class DAUCompsListPage extends StatelessWidget with WatchItMixin {
  const DAUCompsListPage({super.key});

  Future<void> _addDAUComp(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const DAUCompsEditPage(null)),
    );
  }

  Future<void> _editDAUComp(DAUComp daucomp, BuildContext context) async {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => DAUCompsEditPage(daucomp)));
  }

  @override
  Widget build(BuildContext context) {
    DAUCompsViewModel daucompsViewModel = watchIt<DAUCompsViewModel>();
    return AppAdminPage(
      title: 'Admin DAU Comps',
      actions: [
        AppGlassAction(
          icon: Icons.add,
          label: 'Add DAU comp',
          onPressed: () => _addDAUComp(context),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: FutureBuilder<List<DAUComp>>(
          future: daucompsViewModel.getDAUcomps(),
          builder: (BuildContext context, AsyncSnapshot<List<DAUComp>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: League.nrl.colour),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Text('No Records');
            }
            List<DAUComp> daucomps = snapshot.data!;
            // sort by name descending
            daucomps.sort((a, b) => b.name.compareTo(a.name));
            // Rows sit at the bottom, within thumb reach.
            return AppBottomAlignedScroll(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    for (final daucomp in daucomps)
                      Card(
                        child: ListTile(
                          dense: true,
                          isThreeLine: true,
                          trailing: const Icon(Icons.arrow_forward),
                          title: Text(daucomp.name),
                          subtitle:
                              daucomp.lastFixtureUpdateTimestampUTC != null
                              ? Text(
                                  'Last fixture update:\n${DateFormat('EEE dd MMM yyyy hh:mm a').format(daucomp.lastFixtureUpdateTimestampUTC?.toLocal() ?? DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true))}',
                                )
                              : const Text(''),
                          onTap: () async {
                            // Trigger edit functionality
                            await _editDAUComp(daucomp, context);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
