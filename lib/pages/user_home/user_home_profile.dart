import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_faq.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_about.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_adminfunctions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class Profile extends StatelessWidget with WatchItMixin {
  Profile({super.key});

  @override
  Widget build(BuildContext context) {
    DAUComp? selectedDAUComp = watch(di<DAUCompsViewModel>()).selectedDAUComp;
    String? selectedDAUCompDbKey;
    if (selectedDAUComp != null) {
      selectedDAUCompDbKey = selectedDAUComp.dbkey;
    }

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
                            'You are not active in any competition. Contact daufootytipping@gmail.com.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          SizedBox(
                            width: 300,
                            child: Text(
                              'Tipper in a previous year? Select it below to revisit your tips and scores: ',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          DropdownButton<String>(
                            value: selectedDAUCompDbKey,
                            icon: const Icon(Icons.arrow_downward),
                            onChanged: (String? newValue) {
                              // update the current comp
                              dauCompsViewModelConsumer
                                  .changeCurrentDAUComp(newValue!);
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
                          ),
                        ],
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
                    return CircularProgressIndicator(color: League.afl.colour);
                  }
                },
              ),
              FutureBuilder<Widget>(
                future: faq(context),
                builder:
                    (BuildContext context, AsyncSnapshot<Widget> snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return snapshot.data!;
                  } else {
                    return CircularProgressIndicator(color: League.afl.colour);
                  }
                },
              ),
              SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      OutlinedButton(
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
                                di<DAUCompsViewModel>().selectedDAUComp!.dbkey!,
                                null,
                                isUserLoggingOut: true,
                              ),
                            ),
                          );
                        },
                      ),
                      OutlinedButton(
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete),
                            Text('Delete Account'),
                          ],
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('Confirm Account Deletion'),
                                content: const Text(
                                    'Are you sure you want to delete your account? This action cannot be undone. You may be asked to log in again to confirm your identiy.'),
                                actions: [
                                  TextButton(
                                    child: const Text('Cancel'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  TextButton(
                                    child: const Text('Delete'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) => UserAuthPage(
                                            di<DAUCompsViewModel>()
                                                .selectedDAUComp!
                                                .dbkey!,
                                            null,
                                            isUserDeletingAccount: true,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  )),
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
