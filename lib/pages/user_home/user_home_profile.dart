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
    if (authenticatedTipper != null &&
        (authenticatedTipper.name == null ||
            authenticatedTipper.name!.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEditNameDialog(context, authenticatedTipper);
      });
    }

    return ChangeNotifierProvider<TippersViewModel>.value(
      value: di<TippersViewModel>(),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Consumer<TippersViewModel>(
                  builder: (context, tippersViewModelConsumer, child) {
                return HeaderWidget(
                  // use the authenticatedTipper name and add a space between each letter
                  text:
                      (tippersViewModelConsumer.authenticatedTipper!.name ?? '')
                          .split('')
                          .join(' '),
                  leadingIconAvatar:
                      avatarPic(tippersViewModelConsumer.authenticatedTipper!),
                );
              }),
              // add a clickable edit icon to the right of the name
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  _showEditNameDialog(context, authenticatedTipper!);
                },
              ),
            ],
          ),
          Card(
            child: Column(
              children: [
                const SizedBox(height: 20),
                ChangeNotifierProvider<DAUCompsViewModel>.value(
                  value: di<DAUCompsViewModel>(),
                  child: Consumer<TippersViewModel>(
                    builder: (context, tippersViewModelConsumer, child) {
                      return Consumer<DAUCompsViewModel>(
                        builder: (context, dauCompsViewModelConsumer, child) {
                          if (dauCompsViewModelConsumer.activeDAUComp == null) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: SizedBox(
                                width: 250,
                                child: Text(
                                  'There are no active competitions. Contact daufootytipping@gmail.com.',
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
                                    'Tipper in a previous year? Select it below to revisit your tips and scores: ',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                DropdownButton<String>(
                                  value: selectedDAUCompDbKey,
                                  icon: const Icon(Icons.arrow_downward),
                                  onChanged: (String? newValue) {
                                    // update the current comp
                                    dauCompsViewModelConsumer
                                        .changeSelectedDAUComp(
                                            newValue!, false);
                                  },
                                  items: compsForDropdown
                                      .map<DropdownMenuItem<String>>(
                                          (DAUComp comp) {
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
                      );
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
                      return CircularProgressIndicator(
                          color: League.afl.colour);
                    }
                  },
                ),
                FutureBuilder<Widget>(
                  future: help(context),
                  builder:
                      (BuildContext context, AsyncSnapshot<Widget> snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return snapshot.data!;
                    } else {
                      return CircularProgressIndicator(
                          color: League.afl.colour);
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
                      return CircularProgressIndicator(
                          color: League.afl.colour);
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
                              builder: (context) => const UserAuthPage(
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
                                    'Are you sure you want to delete your account? This action cannot be undone. You may be asked to log in again to confirm your identity.'),
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
                                          builder: (context) =>
                                              const UserAuthPage(
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, Tipper tipper) {
    final TextEditingController nameController =
        TextEditingController(text: tipper.name);
    String? errorMessage;
    bool isNewTipper = tipper.name == null || tipper.name!.isEmpty;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing the dialog without saving
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: isNewTipper
                  ? const Text('Create Profile Name')
                  : const Text('Edit Profile Name'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'This is your identity to others in the competition. It must be unique.'),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Enter a name e.g. nickname',
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
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    if (tipper.name == null || tipper.name!.isEmpty) {
                      // Prevent navigation away without saving a valid name
                      setState(() {
                        errorMessage = 'You must enter a valid name.';
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
                        errorMessage = 'Name cannot be empty.';
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
        radius: 30,
      ),
    );
  }
}
