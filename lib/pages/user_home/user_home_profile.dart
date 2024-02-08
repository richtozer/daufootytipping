import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_settings_about.dart';
import 'package:daufootytipping/pages/user_home/user_settings_adminfunctions.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Profile extends StatelessWidget {
  Profile(this.currentTipper, {super.key}) {
    // load an instance of DAUComps from the database
  }

  final Tipper currentTipper;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: <Widget>[
          SizedBox(
            height: 400,
            child: ProfileScreen(
              actions: [
                DisplayNameChangedAction((context, oldName, newName) {
                  // TODO do something with the new name
                  throw UnimplementedError();
                }),
              ],
            ),
          ),
          // Display the current DAUComp
          const SizedBox(height: 20),
          Center(child: Consumer<DAUCompsViewModel>(
              builder: (context, daucompsViewModel, child) {
            return Column(
              children: [
                // display a list of available comps using daucompsViewModel.getDauComps()
                const Text('Use this DAU Comp:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                FutureBuilder<List<DAUComp>>(
                  future: daucompsViewModel.getDAUcomps(),
                  builder: (BuildContext context,
                      AsyncSnapshot<List<DAUComp>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Loading...');
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else {
                      //List<DAUComp> comps = snapshot.data!;
                      return DropdownButton<String>(
                          value: daucompsViewModel.currentDAUComp,
                          icon: const Icon(Icons.arrow_downward),
                          onChanged: (String? newValue) {
                            // update the current comp
                            daucompsViewModel.setCurrentDAUComp(newValue!);
                          },
                          items: snapshot.data!
                              .map<DropdownMenuItem<String>>((DAUComp comp) {
                            return DropdownMenuItem<String>(
                              value: comp.dbkey,
                              child: Text(comp.name),
                            );
                          }).toList());
                    }
                  },
                ),
              ],
            );
          })),

          Center(
            child: FutureBuilder<Widget>(
              future: aboutDialog(context),
              builder: (BuildContext context, AsyncSnapshot<Widget> snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return snapshot.data!;
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          ),
          Consumer<TippersViewModel>(
              builder: (_, TippersViewModel viewModel, __) {
            if (currentTipper.tipperRole == TipperRole.admin) {
              return Center(child: adminFunctions(context));
            } else {
              // we cannot identify their role at this time, do not display admin functionality
              return const Center(child: Text("No Admin Access"));
            }
          })
        ],
      ),
    );
  }
}
