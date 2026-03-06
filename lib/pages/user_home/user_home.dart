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
  final DAUCompsViewModel _dauCompsViewModel = di<DAUCompsViewModel>();
  final TippersViewModel _tippersViewModel = di<TippersViewModel>();
  late final RestorableInt _currentIndex = RestorableInt(
    kIsWeb ? 1 : 0,
  ); // Set to 1 for web, 0 otherwise - TODO this is to get around the bug where web users dont jump to the current round when they first load the app, this should be fixed in the future
  bool _startupReadyMarked = false;
  int _outstandingTipsCount = 0;

  @override
  void initState() {
    super.initState();
    _dauCompsViewModel.addListener(_handleHomeViewModelsUpdated);
    _tippersViewModel.addListener(_handleHomeViewModelsUpdated);
    _outstandingTipsCount = _calculateOutstandingTipsCount();
    if (_tippersViewModel.selectedTipper.isAnonymous &&
        _currentIndex.value == 0) {
      _currentIndex.value = 2;
    }
  }

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

  List<Widget> content() => const [TipsTab(), StatsTab(), Profile()];

  int _calculateOutstandingTipsCount() {
    if (_tippersViewModel.selectedTipper.isAnonymous) {
      return 0;
    }

    return _dauCompsViewModel.currentRoundOutstandingTipsCount();
  }

  void _handleHomeViewModelsUpdated() {
    if (!mounted) return;

    final nextOutstandingTipsCount = _calculateOutstandingTipsCount();
    final shouldSwitchToProfile =
        _tippersViewModel.selectedTipper.isAnonymous && _currentIndex.value == 0;

    if (nextOutstandingTipsCount == _outstandingTipsCount &&
        !shouldSwitchToProfile) {
      return;
    }

    setState(() {
      _outstandingTipsCount = nextOutstandingTipsCount;
      if (shouldSwitchToProfile) {
        _currentIndex.value = 2;
      }
    });
  }

  @override
  void dispose() {
    _dauCompsViewModel.removeListener(_handleHomeViewModelsUpdated);
    _tippersViewModel.removeListener(_handleHomeViewModelsUpdated);
    _currentIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> destinationContent = content();
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final navIndicatorColor = isDarkMode
        ? const Color(0xFF4E7A36)
        : Colors.lightGreen[200];

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

                Widget scaffold = Stack(
                  children: [
                    RepaintBoundary(
                      child: Image.asset(
                        'assets/teams/grass_background_blurred.webp',
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        fit: BoxFit.fill,
                      ),
                    ),
                    Scaffold(
                      backgroundColor:
                          !isDarkMode ? Colors.white54 : Colors.black54,
                      body: Center(
                        child: destinationContent[_currentIndex.value],
                      ),
                      bottomNavigationBar: NavigationBar(
                        indicatorColor: navIndicatorColor,
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
                            final tipsIcon = _outstandingTipsCount > 0
                                ? Badge.count(
                                    count: _outstandingTipsCount,
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
