import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_settings_about.dart';
import 'package:daufootytipping/pages/user_home/user_settings_adminfunctions.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class Profile extends StatelessWidget with WatchItMixin {
  Profile({super.key}) {
    // load an instance of DAUComps from the database
  }

  @override
  Widget build(BuildContext context) {
    String selectedDAUCompDbKey =
        watch(di<DAUCompsViewModel>()).selectedDAUCompDbKey;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 350,
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
            Center(
                child: Column(
              children: [
                // display a list of available comps using daucompsViewModel.getDauComps()
                FutureBuilder<List<DAUComp>>(
                  future: di<DAUCompsViewModel>().getDAUcomps(),
                  builder: (BuildContext context,
                      AsyncSnapshot<List<DAUComp>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Loading...');
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else {
                      return DropdownButton<String>(
                          value: selectedDAUCompDbKey,
                          icon: const Icon(Icons.arrow_downward),
                          onChanged: (String? newValue) {
                            // update the current comp
                            di<DAUCompsViewModel>()
                                .setCurrentDAUComp(newValue!);
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
            )),

            Center(
              child: FutureBuilder<Widget>(
                future: aboutDialog(context),
                builder:
                    (BuildContext context, AsyncSnapshot<Widget> snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return snapshot.data!;
                  } else {
                    return const CircularProgressIndicator();
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            di<TippersViewModel>().selectedTipper!.tipperRole ==
                    TipperRole.admin
                ? const Center(child: AdminFunctionsWidget())
                : const SizedBox.shrink(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
