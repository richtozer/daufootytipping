import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_settings_about.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_settings_adminfunctions.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class Profile extends StatelessWidget with WatchItMixin {
  Profile({super.key});

  @override
  Widget build(BuildContext context) {
    String selectedDAUCompDbKey =
        watch(di<DAUCompsViewModel>()).selectedDAUCompDbKey;

    return Scaffold(
      body: SingleChildScrollView(
        child: Card(
          margin: const EdgeInsets.all(8),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 50),
              Center(
                child: Column(
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/teams/daulogo.jpg',
                            fit: BoxFit.fitWidth,
                          ),
                          const SizedBox(height: 10),
                          const SizedBox(
                            width: 300,
                            child: Text(
                              'Tipper in a previous year? Select it below to revisit your tips and scores: ',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.normal),
                            ),
                          ),
                          ChangeNotifierProvider<DAUCompsViewModel>.value(
                            value: di<DAUCompsViewModel>(),
                            child: Consumer<DAUCompsViewModel>(
                              builder:
                                  (context, dauCompsViewModelConsumer, child) {
                                if (di<TippersViewModel>()
                                    .selectedTipper!
                                    .compsParticipatedIn
                                    .isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: SizedBox(
                                      width: 250,
                                      child: Text(
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                          'You are not active in any competitions. Contact a DAU Admin.'),
                                    ),
                                  );
                                } else {
                                  return DropdownButton<String>(
                                    value: selectedDAUCompDbKey,
                                    icon: const Icon(Icons.arrow_downward),
                                    onChanged: (String? newValue) {
                                      // update the current comp
                                      dauCompsViewModelConsumer
                                          .setCurrentDAUComp(newValue!);
                                    },
                                    items: di<TippersViewModel>()
                                        .selectedTipper!
                                        .compsParticipatedIn
                                        .map<DropdownMenuItem<String>>(
                                            (DAUComp comp) {
                                      return DropdownMenuItem<String>(
                                        value: comp.dbkey,
                                        child: Text(comp.name),
                                      );
                                    }).toList(),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
              di<TippersViewModel>().authenticatedTipper!.tipperRole ==
                      TipperRole.admin
                  ? const Column(children: [
                      Center(child: AdminFunctionsWidget()),
                      SizedBox(height: 20),
                    ])
                  : const SizedBox.shrink(),
              const SizedBox(
                width: 300,
                child: Text(
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.normal),
                    'Your linked account profile: '),
              ),
              SizedBox(
                height: 350,
                width: 300,
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
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
