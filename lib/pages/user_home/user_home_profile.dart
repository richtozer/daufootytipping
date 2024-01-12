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
        body: CustomScrollView(slivers: <Widget>[
      SliverToBoxAdapter(
          child: SizedBox(
              height: 600,
              child: ProfileScreen(
                actions: [
                  DisplayNameChangedAction((context, oldName, newName) {
                    // TODO do something with the new name
                    throw UnimplementedError();
                  }),
                ],
              ))),
      SliverToBoxAdapter(
          child: Center(
              child: FutureBuilder<Widget>(
        future: aboutDialog(context),
        builder: (BuildContext context, AsyncSnapshot<Widget> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return snapshot.data!;
          } else {
            return CircularProgressIndicator();
          }
        },
      ))),
      Consumer<TippersViewModel>(builder: (_, TippersViewModel viewModel, __) {
        //if (viewModel.getcurrentTipper().then((tipperRole) => tipperRole) ==
        if (currentTipper.tipperRole == TipperRole.admin) {
          return SliverToBoxAdapter(
              child: Center(child: adminFunctions(context)));
        } else {
          // we cannot identify their role at this time, do not display admin functionality
          return const SliverToBoxAdapter(
              child: Center(child: Text("No Admin Access")));
        }
      })
    ]));
  }
}
