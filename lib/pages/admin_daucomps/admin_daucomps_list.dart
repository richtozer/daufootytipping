import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

class DAUCompsListPage extends StatelessWidget with WatchItMixin {
  const DAUCompsListPage({super.key});

  Future<void> _addDAUComp(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DAUCompsEditPage(null),
      ),
    );
  }

  Future<void> _editDAUComp(DAUComp daucomp, BuildContext context) async {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => DAUCompsEditPage(daucomp),
    ));
  }

  @override
  Widget build(BuildContext context) {
    DAUCompsViewModel daucompsViewModel = watchIt<DAUCompsViewModel>();
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text('Admin DAU Comps'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await _addDAUComp(context);
          },
          child: const Icon(Icons.add),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              Expanded(
                child: FutureBuilder<List<DAUComp>>(
                  future: daucompsViewModel.getDAUcomps(),
                  builder: (BuildContext context,
                      AsyncSnapshot<List<DAUComp>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: League.afl.colour));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('No Records');
                    } else {
                      List<DAUComp> daucomps = snapshot.data!;
                      // sort by name descending
                      daucomps.sort((a, b) => b.name.compareTo(a.name));
                      return ListView(
                        children: daucomps
                            .map(
                              (daucomp) => Card(
                                child: ListTile(
                                  dense: true,
                                  isThreeLine: true,
                                  leading: daucomp.active
                                      ? const Icon(Icons.ballot)
                                      : const Icon(Icons.ballot_outlined),
                                  trailing: const Icon(Icons.edit),
                                  title: Text(daucomp.name),
                                  subtitle: daucomp
                                              .lastFixtureUpdateTimestamp !=
                                          null
                                      ? Text(
                                          'Last fixture update:\n${DateFormat('EEE dd MMM yyyy hh:mm a').format(daucomp.lastFixtureUpdateTimestamp?.toLocal() ?? DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true))}')
                                      : const Text(''),
                                  onTap: () async {
                                    // Trigger edit functionality
                                    await _editDAUComp(daucomp, context);
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      );
                    }
                  },
                ),
              ),
            ])));
  }
}
