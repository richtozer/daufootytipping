import 'dart:ui';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RestorationMixin {
  late final RestorableInt _currentIndex = RestorableInt(
    kIsWeb ? 1 : 0,
  ); // Set to 1 for web, 0 otherwise - TODO this is to get around the bug where web users dont jump to the current round when they first load the app, this should be fixed in the future
  bool _startupReadyMarked = false;

  @override
  String? get restorationId => 'home_page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_currentIndex, 'current_tab_index');
  }

  void onTabTapped(int index) {
    setState(() {
      _currentIndex.value = index;
    });
  }

  List<Widget> content() {
    return [TipsTab(), StatsTab(), Profile()];
  }

  @override
  void dispose() {
    _currentIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> destinationContent = content();

    return ChangeNotifierProvider<DAUCompsViewModel>.value(
      value: di<DAUCompsViewModel>(),
      child: ChangeNotifierProvider<TippersViewModel>.value(
        value: di<TippersViewModel>(),
        child: Consumer<DAUCompsViewModel>(
          builder: (context, dauCompsViewModelConsumer, child) {
            return Consumer<TippersViewModel>(
              builder: (context, tippersViewModelConsumer, child) {
                if (!_startupReadyMarked &&
                    dauCompsViewModelConsumer.gamesViewModel != null &&
                    dauCompsViewModelConsumer.selectedTipperTipsViewModel != null) {
                  _startupReadyMarked = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    StartupProfiling.instant(
                      'startup.home_models_ready',
                      arguments: <String, Object?>{
                        'compDbKey':
                            dauCompsViewModelConsumer.selectedDAUComp?.dbkey ??
                            'unknown',
                      },
                    );
                  });
                }

                if (tippersViewModelConsumer.selectedTipper.isAnonymous &&
                    _currentIndex.value == 0) {
                  _currentIndex.value = 2;
                }

                Widget scaffold = Stack(
                  children: [
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Image.asset(
                        'assets/teams/grass with scoreboard.png',
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        fit: BoxFit.fill,
                      ),
                    ),
                    Scaffold(
                      backgroundColor:
                          MediaQuery.of(context).platformBrightness !=
                              Brightness.dark
                          ? Colors.white54
                          : Colors.black54,
                      body: Center(
                        child: destinationContent[_currentIndex.value],
                      ),
                      bottomNavigationBar: NavigationBar(
                        indicatorColor: Colors.lightGreen[200],
                        indicatorShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        onDestinationSelected: (int index) {
                          onTabTapped(index);
                        },
                        selectedIndex: _currentIndex.value,
                        height: 60,
                        destinations: [
                          (() {
                            final isAnonymous =
                                tippersViewModelConsumer.selectedTipper.isAnonymous;
                            final outstandingTips = isAnonymous
                                ? 0
                                : dauCompsViewModelConsumer
                                      .currentRoundOutstandingTipsCount();
                            final tipsIcon = outstandingTips > 0
                                ? Badge.count(
                                    count: outstandingTips,
                                    child: const Icon(
                                      Icons.sports_rugby_outlined,
                                    ),
                                  )
                                : const Icon(Icons.sports_rugby_outlined);

                            return NavigationDestination(
                              icon: tipsIcon,
                              selectedIcon: tipsIcon,
                              enabled: !isAnonymous,
                              label: MediaQuery.of(context).size.width > 400
                                  ? 'T  I  P  S'
                                  : 'TIPS',
                            );
                          })(),
                          NavigationDestination(
                            enabled: true,
                            icon: const Icon(Icons.auto_graph),
                            label: MediaQuery.of(context).size.width > 400
                                ? 'S  T  A  T  S'
                                : 'STATS',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.person),
                            label: MediaQuery.of(context).size.width > 400
                                ? 'P  R  O  F  I  L  E'
                                : 'PROFILE',
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                if (tippersViewModelConsumer.inGodMode) {
                  return Banner(
                    message: tippersViewModelConsumer.selectedTipper.name,
                    location: BannerLocation.bottomStart,
                    color: Colors.red,
                    child: Banner(
                      message: 'God mode',
                      location: BannerLocation.bottomEnd,
                      color: Colors.red,
                      child: scaffold,
                    ),
                  );
                } else if (!dauCompsViewModelConsumer
                    .isSelectedCompActiveComp()) {
                  String compYear =
                      dauCompsViewModelConsumer.selectedDAUComp!.name;
                  RegExp regExp = RegExp(r'\d{4}');
                  Match? match = regExp.firstMatch(compYear);
                  if (match != null) {
                    compYear = match.group(0)!;
                  }

                  return Banner(
                    message: compYear,
                    textStyle: const TextStyle(color: Colors.black),
                    location: BannerLocation.bottomStart,
                    color: Colors.orange,
                    child: scaffold,
                  );
                } else {
                  return scaffold;
                }
              },
            );
          },
        ),
      ),
    );
  }
}
