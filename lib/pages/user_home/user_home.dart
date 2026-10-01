import 'dart:async';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/services/app_badge_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:daufootytipping/pages/user_home/user_home_nav.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
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
  final GlobalKey<TipsTabState> _tipsTabKey = GlobalKey<TipsTabState>();
  final OutstandingTipsAppBadgeController _appBadgeController =
      OutstandingTipsAppBadgeController(AppBadgeService());
  late final RestorableInt _currentIndex = RestorableInt(0);
  bool _homeModelsReadyLogged = false;
  bool _tipsContentReadyTrackingStarted = false;
  int _outstandingTipsCount = 0;

  @override
  void initState() {
    super.initState();
    _dauCompsViewModel.addListener(_handleHomeViewModelsUpdated);
    _tippersViewModel.addListener(_handleHomeViewModelsUpdated);
    _outstandingTipsCount = _calculateOutstandingTipsCount();
    unawaited(_syncAppBadge());
    _trackStartupMilestones();
    // Do NOT access _currentIndex.value here — the RestorableInt's
    // internal value is only initialised after registerForRestoration()
    // in restoreState(). Accessing it before that causes:
    // TypeError: null is not a subtype of type 'int' (dart2js).
  }

  @override
  String? get restorationId => 'home_page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_currentIndex, 'current_tab_index');
    // _currentIndex.value is now safe to access.
    if (_tippersViewModel.selectedTipper.isAnonymous &&
        _currentIndex.value == 0) {
      _currentIndex.value = 1; // Anonymous users see Stats tab
    }
  }

  void onTabTapped(int index) {
    if (index == 0 && _currentIndex.value == 0) {
      _tipsTabKey.currentState?.scrollToNextNavigationPosition();
      return;
    }

    setState(() {
      _currentIndex.value = index;
    });
  }

  List<Widget> content() => [
    TipsTab(key: _tipsTabKey),
    const StatsTab(),
    const Profile(),
  ];

  int _calculateOutstandingTipsCount() {
    if (_tippersViewModel.selectedTipper.isAnonymous) {
      return 0;
    }

    return _dauCompsViewModel.currentRoundOutstandingTipsCount();
  }

  void _handleHomeViewModelsUpdated() {
    if (!mounted) return;

    final nextOutstandingTipsCount = _calculateOutstandingTipsCount();
    final shouldSwitchToStats =
        _tippersViewModel.selectedTipper.isAnonymous &&
        _currentIndex.value == 0;

    unawaited(_syncAppBadge());
    _trackStartupMilestones();

    if (nextOutstandingTipsCount == _outstandingTipsCount &&
        !shouldSwitchToStats) {
      return;
    }

    setState(() {
      _outstandingTipsCount = nextOutstandingTipsCount;
      if (shouldSwitchToStats) {
        _currentIndex.value = 1; // Anonymous users see Stats tab
      }
    });
  }

  Future<void> _syncAppBadge() async {
    await _appBadgeController.sync(
      tipper: _tippersViewModel.selectedTipper,
      comp: _dauCompsViewModel.selectedDAUComp,
      outstandingCount: _dauCompsViewModel.appBadgeOutstandingTipsCount(),
    );
  }

  void _trackStartupMilestones() {
    if (!mounted) {
      return;
    }

    if (!_homeModelsReadyLogged &&
        _dauCompsViewModel.gamesViewModel != null &&
        _dauCompsViewModel.selectedTipperTipsViewModel != null) {
      _homeModelsReadyLogged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        StartupProfiling.instant(
          'startup.home_models_ready',
          arguments: <String, Object?>{
            'compDbKey': _dauCompsViewModel.selectedDAUComp?.dbkey ?? 'unknown',
          },
        );
      });
    }

    _trackTipsContentReadyIfNeeded();
  }

  void _trackTipsContentReadyIfNeeded() {
    if (_tipsContentReadyTrackingStarted) {
      return;
    }

    final gamesViewModel = _dauCompsViewModel.gamesViewModel;
    final tipsViewModel = _dauCompsViewModel.selectedTipperTipsViewModel;
    if (gamesViewModel == null || tipsViewModel == null) {
      return;
    }

    _tipsContentReadyTrackingStarted = true;
    unawaited(() async {
      await gamesViewModel.initialLoadComplete;
      await tipsViewModel.initialLoadCompleted;
      if (!mounted) {
        return;
      }
      StartupProfiling.end(
        'startup.tips_content_ready',
        arguments: <String, Object?>{
          'compDbKey': _dauCompsViewModel.selectedDAUComp?.dbkey ?? 'unknown',
        },
      );
    }());
  }

  @override
  void dispose() {
    _dauCompsViewModel.removeListener(_handleHomeViewModelsUpdated);
    _tippersViewModel.removeListener(_handleHomeViewModelsUpdated);
    _currentIndex.dispose();
    super.dispose();
  }

  /// Described once so the bar and the rail cannot drift apart.
  List<AppNavDestination> _navDestinations(TippersViewModel tippersViewModel) {
    const tipsTabIcon = SizedBox(
      width: 32,
      height: 32,
      child: Center(child: Icon(Icons.sports_rugby_outlined)),
    );
    final tipsIcon = _outstandingTipsCount > 0
        ? Badge.count(
            count: _outstandingTipsCount,
            backgroundColor: Colors.red[800],
            largeSize: 20,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            child: tipsTabIcon,
          )
        : tipsTabIcon;
    return [
      AppNavDestination(
        icon: tipsIcon,
        shortLabel: 'TIPS',
        wideLabel: 'T  I  P  S',
        enabled: !tippersViewModel.selectedTipper.isAnonymous,
      ),
      const AppNavDestination(
        icon: Icon(Icons.auto_graph),
        shortLabel: 'STATS',
        wideLabel: 'S  T  A  T  S',
      ),
      const AppNavDestination(
        icon: Icon(Icons.person),
        shortLabel: 'PROFILE',
        wideLabel: 'P  R  O  F  I  L  E',
      ),
    ];
  }

  Widget _navigationRail(
    BuildContext context, {
    required List<AppNavDestination> destinations,
    required Color? indicatorColor,
    required double inset,
    required bool onRight,
  }) {
    // iOS reserves the same strip on both sides in landscape -- 62 each on
    // this phone -- whichever edge the island is on, and reports no display
    // features at all, so there is no telling which side is genuinely spent.
    // The rail keeps clear of its own side either way; what changes here is
    // that the backdrop keeps the strip rather than the rail painting across
    // it, which made a reservation look like part of the navigation.
    return Padding(
      padding: EdgeInsets.only(
        left: onRight ? 0 : inset,
        right: onRight ? inset : 0,
      ),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainer,
        // The home indicator still runs along the bottom, which is exactly
        // where the destinations are grouped.
        child: SafeArea(
          left: false,
          right: false,
          top: false,
          // NavigationRail always holds itself clear of the *leading* inset, on
          // the assumption that is the edge it sits against. The Row has already
          // chosen a side, so left to itself it insets the wrong one when the
          // rail is on the right, and doubles up with the Row when it is on the
          // left -- a 51pt inset widened the rail from 103.5 to 154.5 and pushed
          // every destination off centre by exactly that much. Strip both and
          // apply the one the rail is genuinely against: an island on that edge
          // reaches the destinations, which are not far enough down to miss it.
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            removeRight: true,
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              indicatorColor: indicatorColor,
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              // Grouped at the bottom: the same thumb zone the bar occupied, and
              // clear of a camera strip mounted at the top of the inset.
              groupAlignment: 1,
              labelType: NavigationRailLabelType.all,
              minWidth: kNavigationRailWidth,
              selectedIndex: _currentIndex.value,
              onDestinationSelected: onTabTapped,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: destination.icon,
                    disabled: !destination.enabled,
                    label: Text(destination.shortLabel),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The bar's surface spans the display while its destinations stay grouped,
  /// rather than drifting to the far corners of a tablet.
  Widget _bottomNavigationBar(
    BuildContext context, {
    required List<AppNavDestination> destinations,
    required Color? indicatorColor,
  }) {
    final wide = MediaQuery.of(context).size.width > 400;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Align(
        alignment: Alignment.center,
        // Size to the bar rather than the space available: a Center here
        // would fill the whole scaffold.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kFormContentWidth),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            indicatorColor: indicatorColor,
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            onDestinationSelected: onTabTapped,
            selectedIndex: _currentIndex.value,
            height: 60,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: destination.icon,
                  selectedIcon: destination.icon,
                  enabled: destination.enabled,
                  label: wide ? destination.wideLabel : destination.shortLabel,
                ),
            ],
          ),
        ),
      ),
    );
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
                final displayPadding = MediaQuery.paddingOf(context);
                final displaySize = MediaQuery.sizeOf(context);
                final displayFeatures = MediaQuery.displayFeaturesOf(context);
                final useNavigationRail = shouldUseNavigationRail(
                  size: displaySize,
                  displayPadding: displayPadding,
                );
                final railOnRight = navigationRailOnRight(
                  features: displayFeatures,
                  size: displaySize,
                  displayPadding: displayPadding,
                );
                final railInset = navigationRailInset(
                  features: displayFeatures,
                  size: displaySize,
                  displayPadding: displayPadding,
                  onRight: railOnRight,
                );
                final navDestinations = _navDestinations(
                  tippersViewModelConsumer,
                );
                final Widget bodyContent = AppContentWidth(
                  daurounds:
                      dauCompsViewModelConsumer.selectedDAUComp?.daurounds ??
                      const [],
                  child: Center(child: destinationContent[_currentIndex.value]),
                );

                Widget scaffold = Stack(
                  children: [
                    RepaintBoundary(
                      child: Image.asset(
                        'assets/grass_background_blurred.webp',
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        fit: BoxFit.fill,
                      ),
                    ),
                    Scaffold(
                      backgroundColor: !isDarkMode
                          ? Colors.white54
                          : Colors.black54,
                      body: useNavigationRail
                          ? Row(
                              children: [
                                if (!railOnRight)
                                  _navigationRail(
                                    context,
                                    destinations: navDestinations,
                                    indicatorColor: navIndicatorColor,
                                    inset: railInset,
                                    onRight: railOnRight,
                                  ),
                                Expanded(
                                  // The rail now occupies the inset, so the
                                  // content must not hold it clear a second
                                  // time and lose the room twice over.
                                  child: MediaQuery.removePadding(
                                    context: context,
                                    removeLeft: !railOnRight,
                                    removeRight: railOnRight,
                                    child: bodyContent,
                                  ),
                                ),
                                if (railOnRight)
                                  _navigationRail(
                                    context,
                                    destinations: navDestinations,
                                    indicatorColor: navIndicatorColor,
                                    inset: railInset,
                                    onRight: railOnRight,
                                  ),
                              ],
                            )
                          : bodyContent,
                      bottomNavigationBar: useNavigationRail
                          ? null
                          : _bottomNavigationBar(
                              context,
                              destinations: navDestinations,
                              indicatorColor: navIndicatorColor,
                            ),
                    ),
                  ],
                );

                final scaffoldWithCompBanner = SelectedCompBanner(
                  dauCompsViewModel: dauCompsViewModelConsumer,
                  child: scaffold,
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
                      child: scaffoldWithCompBanner,
                    ),
                  );
                } else {
                  return scaffoldWithCompBanner;
                }
              },
            );
          },
        ),
      ),
    );
  }
}
