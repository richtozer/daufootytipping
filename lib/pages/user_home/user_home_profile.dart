import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_settings_about.dart';
import 'package:daufootytipping/pages/user_home/user_settings_adminfunctions.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Profile extends StatelessWidget {
  const Profile(this.currentTipper, {super.key});

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
