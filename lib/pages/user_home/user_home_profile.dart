import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_faq.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_help.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_adminfunctions.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class Profile extends StatelessWidget with WatchItMixin {
  Profile({super.key});

  @override
  Widget build(BuildContext context) {
    DAUComp? selectedDAUComp = watch(di<DAUCompsViewModel>()).selectedDAUComp;

    Tipper? authenticatedTipper = di<TippersViewModel>().authenticatedTipper;

    // create a list of comps. In the list include the comps the tipper
    // is a paid member of. if the list does not include the active comp, then
    // add it to the list
    List<DAUComp> compsForDropdown = [];
    if (authenticatedTipper != null) {
      compsForDropdown.addAll(authenticatedTipper.compsPaidFor);
      DAUComp? activeDAUComp = di<DAUCompsViewModel>().activeDAUComp;
      if (activeDAUComp != null && !compsForDropdown.contains(activeDAUComp)) {
        compsForDropdown.add(activeDAUComp);
      }
    }

    // Sort the compsForDropdown list by the name property in descending order
    compsForDropdown.sort((a, b) => b.name.compareTo(a.name));

    // Automatically show the edit tipper name modal if the tipper does not have a profile name
    if (authenticatedTipper != null && (authenticatedTipper.name.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEditNameDialog(context, authenticatedTipper);
      });
    }

    return ChangeNotifierProvider<TippersViewModel>.value(
      value: di<TippersViewModel>(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Consumer<TippersViewModel>(
              builder: (context, tippersViewModelConsumer, child) {
            Tipper profileTipper = tippersViewModelConsumer.tippers
                .firstWhere((t) => t.dbkey == authenticatedTipper!.dbkey);
            return Column(
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5.0),
                      child: avatarPic(profileTipper),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (profileTipper.name),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        letterSpacing: 5,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(5),
                                    minimumSize: Size(50, 30),
                                  ),
                                  child: const Text('Edit',
                                      textAlign: TextAlign.center),
                                  onPressed: () {
                                    _showEditNameDialog(context, profileTipper);
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(
                                  size: 20,
                                  Icons.login,
                                  color: Colors.black54,
                                ),
                                Expanded(
                                  child: Text(
                                    profileTipper.logon ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(5),
                                    minimumSize: Size(50, 30),
                                  ),
                                  child: const Text('Sign Out',
                                      textAlign: TextAlign.center),
                                  onPressed: () {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const UserAuthPage(
                                          null,
                                          isUserLoggingOut: true,
                                          createLinkedTipper: false,
                                          googleClientId: '',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Card(
                  child: Column(
                    children: [
                      profileTipper.tipperRole == TipperRole.admin
                          ? const Center(child: AdminFunctionsWidget())
                          : const SizedBox.shrink(),
                      const SizedBox(height: 20),
                      ChangeNotifierProvider<DAUCompsViewModel>.value(
                        value: di<DAUCompsViewModel>(),
                        child: Consumer<DAUCompsViewModel>(
                          builder: (context, dauCompsViewModelConsumer, child) {
                            if (dauCompsViewModelConsumer.activeDAUComp ==
                                null) {
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 250,
                                  child: Text(
                                    'There are no active competitions. Contact support: https://interview.coach/tipping.',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              );
                            } else {
                              return Column(
                                children: [
                                  SizedBox(
                                    width: 300,
                                    child: Text(
                                      'Tipper in a previous year? Select it below to revisit your tips and stats: ',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  DropdownButton<DAUComp>(
                                    value: selectedDAUComp,
                                    icon: const Icon(Icons.arrow_downward),
                                    onChanged: (DAUComp? newValue) {
                                      // update the current comp in the view model
                                      dauCompsViewModelConsumer
                                          .changeDisplayedDAUComp(
                                              newValue!, false);
                                    },
                                    items: compsForDropdown
                                        .map<DropdownMenuItem<DAUComp>>(
                                            (DAUComp comp) {
                                      return DropdownMenuItem<DAUComp>(
                                        value: comp,
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FutureBuilder<Widget>(
                            future: help(context),
                            builder: (BuildContext context,
                                AsyncSnapshot<Widget> snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.done) {
                                return snapshot.data!;
                              } else {
                                return CircularProgressIndicator(
                                    color: League.afl.colour);
                              }
                            },
                          ),
                          const SizedBox(width: 10),
                          FutureBuilder<Widget>(
                            future: faq(context),
                            builder: (BuildContext context,
                                AsyncSnapshot<Widget> snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.done) {
                                return snapshot.data!;
                              } else {
                                return CircularProgressIndicator(
                                    color: League.afl.colour);
                              }
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete),
                                Text(
                                  'Delete\nAccount',
                                  textScaler: TextScaler.linear(0.75),
                                ),
                              ],
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: Text(
                                      'Confirm Account Deletion',
                                      style:
                                          TextStyle(color: League.afl.colour),
                                    ),
                                    content: const Text(
                                        'Are you sure you want to delete your account? Any tips you have made, will be deleted. This action cannot be undone. Prior to your account be deleted, you may confirm your identity, otherwise your account will be deleted immediatedly.'),
                                    actions: [
                                      TextButton(
                                        child: const Text('Cancel'),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      TextButton(
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(
                                              color: League.afl.colour),
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const UserAuthPage(
                                                null,
                                                isUserDeletingAccount: true,
                                                createLinkedTipper: false,
                                                googleClientId: '',
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
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FutureBuilder<PackageInfo>(
                            future: PackageInfo.fromPlatform(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Loading...',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              } else if (snapshot.hasError) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: Text(
                                    'App Version: Unknown',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              } else {
                                final packageInfo = snapshot.data!;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    'App Version: ${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }
                            },
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
          Container(
            height: 25,
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, Tipper tipper) {
    final TextEditingController nameController =
        TextEditingController(text: tipper.name);
    String? errorMessage;
    bool isNewTipper = tipper.name.isEmpty;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing the dialog without saving
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: isNewTipper
                  ? const Text('Create Tipper Alias')
                  : const Text('Edit Tipper Alias'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'This is your identity as shown to others in the competition. It must be unique.'),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Alias',
                      hintText: 'Enter a name e.g. The Oracle',
                    ),
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                if (!isNewTipper)
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      if (tipper.name.isEmpty) {
                        // Prevent navigation away without saving a valid name
                        setState(() {
                          errorMessage = 'You must enter a valid tipper alias.';
                        });
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    String newName = nameController.text.trim();
                    if (newName.isEmpty) {
                      setState(() {
                        errorMessage = 'Alias cannot be empty.';
                      });
                      return;
                    }
                    if (newName.length < 2) {
                      setState(() {
                        errorMessage =
                            'Alias must be at least 2 characters long.';
                      });
                      return;
                    }
                    try {
                      // Update the tipper name in the database
                      await di<TippersViewModel>()
                          .setTipperName(tipper.dbkey!, newName);

                      // update the name on the tipper object
                      tipper.name =
                          newName; //TODO Hack -  state changes should go through database first

                      // if the tipper is new then navigate to the home page,
                      // otherwise just close the dialog
                      if (isNewTipper) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const HomePage(),
                          ),
                        );
                      } else {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      setState(() {
                        errorMessage = 'Error: $e';
                      });
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey!,
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 40,
      ),
    );
  }
}
