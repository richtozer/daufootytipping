import 'package:daufootytipping/classes/footytipping_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TippersAdminPage extends StatelessWidget {
  const TippersAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {},
          ),
          title: const Text('Tippers Administration'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              Consumer<FootyTippingModel>(builder: (context, model, child) {
                return Expanded(
                  child: ListView(
                    children: [
                      ...model.tippers.map(
                        (tipper) => Card(
                          child: ListTile(
                            leading: tipper.active
                                ? const Icon(Icons.person)
                                : const Icon(Icons.person_off),
                            title: Text(tipper.name),
                            subtitle: Text(
                                '${tipper.tipperRole.name} | ${tipper.email}'),
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
