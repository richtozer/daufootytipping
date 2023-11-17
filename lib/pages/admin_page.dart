import 'package:daufootytipping/classes/footytipping_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Provider Example'),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              const Text('Tippers'),
              Consumer<FootyTippingModel>(builder: (context, model, child) {
                return Expanded(
                  child: ListView(
                    children: [
                      ...model.tippers.map(
                        (tipper) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.abc),
                            title: Text(tipper.name),
                            subtitle: Text(tipper.tipperRole.toString()),
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
