import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
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
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('No Records');
                    } else {
                      return ListView(
                        children: snapshot.data
                                ?.map(
                                  (daucomp) => Card(
                                    child: ListTile(
                                      dense: true,
                                      isThreeLine: true,
                                      leading: daucomp.active
                                          ? const Icon(Icons.ballot)
                                          : const Icon(Icons.ballot_outlined),
                                      trailing: const Icon(Icons.edit),
                                      title: Text(daucomp.name),
                                      subtitle: Text(
                                          '${daucomp.aflFixtureJsonURL.toString()}\n${daucomp.nrlFixtureJsonURL.toString()}'),
                                      onTap: () async {
                                        // Trigger edit functionality
                                        await _editDAUComp(daucomp, context);
                                      },
                                    ),
                                  ),
                                )
                                .toList() ??
                            <Widget>[],
                      );
                    }
                  },
                ),
              ),
            ])));
  }
}
