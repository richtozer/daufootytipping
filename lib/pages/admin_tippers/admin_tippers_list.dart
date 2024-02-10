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
        create: (_) => TippersViewModel(
            null), //todo this is already is the tree - consider removing
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
                child: Column(
                  children: [
                    Consumer<TippersViewModel>(
                      builder: (context, tipperViewModel, child) {
                        return OutlinedButton(
                          onPressed: () async {
                            if (tipperViewModel.isLegacySyncing) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text(
                                          'Legacy Tipper sync already in progress')));
                              return;
                            }
                            try {
                              await tipperViewModel.syncTippers();
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.red,
                                  content: Text('An error occurred: $e'),
                                  duration: const Duration(seconds: 10),
                                ),
                              );
                            }
                          },
                          child: Text(!tipperViewModel.isLegacySyncing
                              ? 'Sync Tippers'
                              : 'Sync processing...'),
                        );
                      },
                    ),
                    Expanded(
                      child: Consumer<TippersViewModel>(
                        builder: (context, tipperViewModel, child) {
                          return FutureBuilder<List<Tipper>>(
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
                                return Column(
                                  children: [
                                    Expanded(
                                      child: ListView(
                                        children: snapshot.data!
                                            .map((tipper) => Card(
                                                  child: ListTile(
                                                    dense: true,
                                                    isThreeLine: true,
                                                    leading: tipper.active
                                                        ? const Icon(
                                                            Icons.person)
                                                        : const Icon(
                                                            Icons.person_off),
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
                                      ),
                                    )
                                  ],
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ))));
  }
}
