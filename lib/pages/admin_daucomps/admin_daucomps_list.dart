import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DAUCompsListPage extends StatelessWidget {
  const DAUCompsListPage({super.key});

  Future<void> _addDAUComp(
      DAUCompsViewModel daucompsViewModel, BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DAUCompsEditPage(null, daucompsViewModel),
      ),
    );
  }

  Future<void> _editDAUComp(DAUComp daucomp,
      DAUCompsViewModel daucompsViewModel, BuildContext context) async {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DAUCompsEditPage(daucomp, daucompsViewModel),
        ));
  }

  @override
  Widget build(BuildContext context) {
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
            DAUCompsViewModel daucompsViewModel =
                Provider.of<DAUCompsViewModel>(context, listen: false);
            await _addDAUComp(daucompsViewModel, context);
          },
          child: const Icon(Icons.add),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              Consumer<DAUCompsViewModel>(
                  builder: (context, daucompsViewModel, child) {
                return Expanded(
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
                                          await _editDAUComp(daucomp,
                                              daucompsViewModel, context);
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
                );
              }),
            ])));
  }
}
