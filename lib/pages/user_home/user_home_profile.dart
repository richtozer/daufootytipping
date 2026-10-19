import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_faq.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_help.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_adminfunctions.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_alias_dialog.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
import 'package:daufootytipping/widgets/app_panel_card.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class Profile extends StatelessWidget with WatchItMixin {
  const Profile({super.key});

  static final Future<PackageInfo> _packageInfoFuture =
      di<PackageInfoService>().packageInfo;

  @override
  Widget build(BuildContext context) {
    DAUComp? selectedDAUComp = watch(di<DAUCompsViewModel>()).selectedDAUComp;

    return ChangeNotifierProvider<TippersViewModel>.value(
      value: di<TippersViewModel>(),
      // A short display with the admin panel open runs past the bottom, so the
      // page scrolls rather than overflowing.
      // Bottom aligned so the content stays within thumb reach, and still
      // scrollable where a short display cannot fit it. A plain scroll view
      // leaves the column unbounded, which ignores the alignment.
      child: AppBottomAlignedScroll(
        // The same readable width as the Stats page. The cards inside fill it,
        // so no panel is narrower than the one around it.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kFormContentWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Consumer<TippersViewModel>(
                builder: (context, tippersViewModelConsumer, child) {
                  Tipper? authenticatedTipper =
                      tippersViewModelConsumer.authenticatedTipper;

                  // Use the tipper from the tippers list (always fresh from
                  // the Firebase stream with populated compsPaidFor) rather
                  // than authenticatedTipper which may be a stale cached copy.
                  Tipper? profileTipper = authenticatedTipper != null
                      ? tippersViewModelConsumer.tippers.firstWhereOrNull(
                          (t) => t.dbkey == authenticatedTipper.dbkey,
                        )
                      : null;
                  profileTipper ??= authenticatedTipper;

                  List<DAUComp> compsForDropdown = [];
                  if (profileTipper != null) {
                    compsForDropdown.addAll(profileTipper.compsPaidFor);
                    DAUComp? activeDAUComp =
                        di<DAUCompsViewModel>().activeDAUComp;
                    if (activeDAUComp != null &&
                        !compsForDropdown.contains(activeDAUComp)) {
                      compsForDropdown.add(activeDAUComp);
                    }
                  }
                  compsForDropdown.sort((a, b) => b.name.compareTo(a.name));

                  if (profileTipper == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Local non-nullable reference for use in closures
                  // (Dart can't promote the nullable profileTipper across
                  // closure boundaries).
                  final Tipper tipper = profileTipper;

                  if (tipper.name.isEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      showEditAliasDialog(context, tipper);
                    });
                  }
                  return Column(
                    // The header and the card fill the page's width.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(5.0),
                            child: avatarPic(tipper),
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
                                          (tipper.name),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            letterSpacing: 5,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.all(5),
                                          minimumSize: Size(50, 30),
                                        ),
                                        onPressed: tipper.isAnonymous
                                            ? null
                                            : () {
                                                showEditAliasDialog(
                                                  context,
                                                  tipper,
                                                );
                                              },
                                        child: const Text(
                                          'Edit',
                                          textAlign: TextAlign.center,
                                        ),
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
                                          tipper.logon ?? '',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.all(5),
                                          minimumSize: Size(50, 30),
                                        ),
                                        child: const Text(
                                          'Sign Out',
                                          textAlign: TextAlign.center,
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pushReplacement(
                                            appPageRoute(
                                              (context) => const UserAuthPage(
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
                      // Two cards sitting directly on the backdrop: the admin
                      // functions, for admins, and everything else.
                      if (tipper.tipperRole == TipperRole.admin)
                        const AdminFunctionsWidget(),
                      AppPanelCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              ChangeNotifierProvider<DAUCompsViewModel>.value(
                                value: di<DAUCompsViewModel>(),
                                child: Consumer<DAUCompsViewModel>(
                                  builder:
                                      (
                                        context,
                                        dauCompsViewModelConsumer,
                                        child,
                                      ) {
                                        if (dauCompsViewModelConsumer
                                                .activeDAUComp ==
                                            null) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              'There are no active competitions. Contact support: https://interview.coach/tipping.',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          );
                                        } else {
                                          return Column(
                                            children: [
                                              Text(
                                                'Tipper in a previous year? Select it below to revisit your tips and stats: ',
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              DropdownButton<DAUComp>(
                                                value: selectedDAUComp,
                                                icon: const Icon(
                                                  Icons.arrow_downward,
                                                ),
                                                onChanged: (DAUComp? newValue) {
                                                  // update the current comp in the view model
                                                  dauCompsViewModelConsumer
                                                      .changeDisplayedDAUComp(
                                                        newValue!,
                                                        false,
                                                      );
                                                },
                                                items: compsForDropdown
                                                    .map<
                                                      DropdownMenuItem<DAUComp>
                                                    >((DAUComp comp) {
                                                      return DropdownMenuItem<
                                                        DAUComp
                                                      >(
                                                        value: comp,
                                                        child: Text(comp.name),
                                                      );
                                                    })
                                                    .toList(),
                                              ),
                                            ],
                                          );
                                        }
                                      },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AppPanelCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              // Inline where there is width, stacked where not.
                              Wrap(
                                alignment: WrapAlignment.center,
                                runAlignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  helpButton(),
                                  faqButton(),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
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
                                              style: TextStyle(
                                                color: League.afl.colour,
                                              ),
                                            ),
                                            content: const Text(
                                              'Are you sure you want to delete your account? Any tips you have made, will be deleted. This action cannot be undone. Prior to your account be deleted, you may confirm your identity, otherwise your account will be deleted immediately.',
                                            ),
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
                                                    color: League.afl.colour,
                                                  ),
                                                ),
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  Navigator.of(
                                                    context,
                                                  ).pushReplacement(
                                                    appPageRoute(
                                                      (
                                                        context,
                                                      ) => const UserAuthPage(
                                                        null,
                                                        isUserDeletingAccount:
                                                            true,
                                                        createLinkedTipper:
                                                            false,
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
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FutureBuilder<PackageInfo>(
                                    future: _packageInfoFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Padding(
                                          padding: EdgeInsets.only(top: 16),
                                          child: Text(
                                            'Loading...',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      } else if (snapshot.hasError) {
                                        return const Padding(
                                          padding: EdgeInsets.only(top: 16),
                                          child: Text(
                                            'App Version: Unknown',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      } else {
                                        final packageInfo = snapshot.data!;
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16,
                                          ),
                                          child: Text(
                                            'App Version: ${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey ?? 'anonymous-avatar',
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 40,
      ),
    );
  }
}
