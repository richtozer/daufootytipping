import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'admin_tippers_viewmodel.dart';

class TippersAdminPage extends StatelessWidget {
  static const String route = '/AdminTippers';
  const TippersAdminPage({super.key});

  Future<void> _addTipper(BuildContext context) async {
    await Navigator.of(context).pushNamed(TipperAdminEditPage.route);
  }

  Future<void> _editTipper(Tipper tipper, BuildContext context) async {
    await Navigator.of(context)
        .pushNamed(TipperAdminEditPage.route, arguments: tipper);
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
          title: const Text('Admin Tippers'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await _addTipper(context);
          },
          child: const Icon(Icons.add),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              const Wrap(spacing: 6.0, runSpacing: 6.0, children: [
                Chip(label: Text('Tipper')),
                Chip(label: Text('Admin')),
                Chip(label: Text('Active')),
                Chip(label: Text('Disabled')),
              ]),
              Consumer<TipperViewModel>(
                  builder: (context, tipperViewModel, child) {
                return Expanded(
                  child: ListView(
                    children: [
                      ...tipperViewModel.tippers.map(
                        (tipper) => Card(
                          child: ListTile(
                            dense: true,
                            isThreeLine: true,
                            leading: tipper.active
                                ? const Icon(Icons.person)
                                : const Icon(Icons.person_off),
                            title: Text(tipper.name),
                            subtitle: Text(
                                '${tipper.tipperRole.name}\n${tipper.email}'),
                            onTap: () async {
                              // Trigger edit functionality
                              await _editTipper(tipper, context);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ])));
  }
}
