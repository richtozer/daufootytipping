import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_settings_about.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_settings_adminfunctions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class Profile extends StatelessWidget with WatchItMixin {
  Profile({super.key});

  @override
  Widget build(BuildContext context) {
    String selectedDAUCompDbKey =
        watch(di<DAUCompsViewModel>()).selectedDAUCompDbKey;

    // return Scaffold(
    //   body: SingleChildScrollView(
    return Column(
      children: <Widget>[
        HeaderWidget(
            text: 'P r o f i l e',
            leadingIconAvatar:
                avatarPic(di<TippersViewModel>().authenticatedTipper!)),
        Card(
          child: Column(
            children: [
              const SizedBox(height: 20),
              SizedBox(
                width: 300,
                child: Text(
                  'Tipper in a previous year? Select it below to revisit your tips and scores: ',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ChangeNotifierProvider<DAUCompsViewModel>.value(
                value: di<DAUCompsViewModel>(),
                child: Consumer<DAUCompsViewModel>(
                  builder: (context, dauCompsViewModelConsumer, child) {
                    if (di<TippersViewModel>()
                        .selectedTipper!
                        .compsParticipatedIn
                        .isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 250,
                          child: Text(
                            'You are not active in any competitions. Contact a DAU Admin.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
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
                            .map<DropdownMenuItem<String>>((DAUComp comp) {
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
              di<TippersViewModel>().authenticatedTipper!.tipperRole ==
                      TipperRole.admin
                  ? const Center(child: AdminFunctionsWidget())
                  : const SizedBox.shrink(),
              FutureBuilder<Widget>(
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
              Card(
                child: SizedBox(
                  width: 150,
                  child: OutlinedButton(
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout),
                        Text('Sign Out'),
                      ],
                    ),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => UserAuthPage(
                            di<DAUCompsViewModel>().selectedDAUCompDbKey,
                            null,
                            isUserLoggingOut: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // SizedBox(
              //   height: MediaQuery.of(context).size.height * 0.35,
              //   width: MediaQuery.of(context).size.width * 0.95,
              //   child: const ProfileScreen(

              //       //actions: [
              //       // DisplayNameChangedAction((context, oldName, newName) {
              //       //   // TODO do something with the new name
              //       //   throw UnimplementedError();
              //       // }),
              //       //],
              //       ),
              // ),
            ],
          ),
        ),
      ],
    );
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey!,
      child: circleAvatarWithFallback(
          imageUrl: tipper.photoURL, text: tipper.name, radius: 30),
    );
  }
}
