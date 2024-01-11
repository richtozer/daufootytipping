import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'admin_tippers_viewmodel.dart';

class TippersAdminPage extends StatelessWidget {
  const TippersAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TippersViewModel>(
        create: (_) => TippersViewModel(),
        child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              title: const Text('Admin Tippers'),
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
                  Consumer<TippersViewModel>(
                      builder: (context, tipperViewModel, child) {
                    return Expanded(
                        child: FutureBuilder<List<Tipper>>(
                      future: tipperViewModel.getTippers(),
                      builder: (BuildContext context,
                          AsyncSnapshot<List<Tipper>> snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const CircularProgressIndicator(); // Show a loading spinner while waiting
                        } else if (snapshot.hasError) {
                          return Text(
                              'Error: ${snapshot.error}'); // Show error message if something went wrong
                        } else {
                          return ListView(
                            children: snapshot.data!
                                .map((tipper) => Card(
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
                                          Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      TipperAdminEditPage(
                                                          tipperViewModel,
                                                          tipper)));
                                        },
                                      ),
                                    ))
                                .toList(),
                          );
                        }
                      },
                    ));
                  }),
                ]))));
  }
}
