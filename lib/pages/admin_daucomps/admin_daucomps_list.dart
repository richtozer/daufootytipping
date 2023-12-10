import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_add.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DAUCompsListPage extends StatelessWidget {
  const DAUCompsListPage({super.key});

  Future<void> _addDAUComp(
      DAUCompsViewModel daucompsViewModel, BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DAUCompsAdminEditPage(null, daucompsViewModel),
      ),
    );
  }

  Future<void> _editDAUComp(DAUComp daucomp,
      DAUCompsViewModel daucompsViewModel, BuildContext context) async {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DAUCompsAdminEditPage(daucomp, daucompsViewModel),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DAUCompsViewModel>(
        create: (_) => DAUCompsViewModel(),
        child: Scaffold(
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
                //await _addDAUComp(daucompsViewModel, context); TODO fix this
              },
              child: const Icon(Icons.add),
            ),
            body: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(children: [
                  Consumer<DAUCompsViewModel>(
                      builder: (context, daucompsViewModel, child) {
                    return Expanded(
                      child: ListView(
                        children: [
                          ...daucompsViewModel.daucomps.map(
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
                                  await _editDAUComp(
                                      daucomp, daucompsViewModel, context);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ]))));
  }
}
