import 'dart:async';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/services/app_badge_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/services/unconfirmed_tips_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_scopes.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  final UnconfirmedTipsService? _unconfirmedTips =
      di.isRegistered<UnconfirmedTipsService>()
      ? di<UnconfirmedTipsService>()
      : null;
  bool _tipNoticeShowing = false;
  TipsViewModel? _watchedTips;
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
    _unconfirmedTips?.addListener(_showTipNotices);
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
    _watchQueuedTips();
  }

  /// Keeps an eye on the signed-in tipper's tips for any that were queued and
  /// have since disappeared, which means the server refused them. Follows the
  /// tips view model as the selected tipper or competition changes.
  void _watchQueuedTips() {
    final tips = _dauCompsViewModel.selectedTipperTipsViewModel;
    if (_unconfirmedTips == null || identical(tips, _watchedTips)) {
      return;
    }
    _watchedTips?.removeListener(_lookAtQueuedTips);
    _watchedTips = tips;
    tips?.addListener(_lookAtQueuedTips);
    _lookAtQueuedTips();
  }

  void _lookAtQueuedTips() {
    final UnconfirmedTipsService? service = _unconfirmedTips;
    final String? compKey = _dauCompsViewModel.selectedDAUComp?.dbkey;
    final TipsViewModel? tips = _watchedTips;
    final tipper = _tippersViewModel.selectedTipper;
    final String? tipperKey = tipper.dbkey;
    if (!mounted ||
        service == null ||
        compKey == null ||
        tipperKey == null ||
        tips == null ||
        !tips.isInitialLoadComplete ||
        tipper.isAnonymous) {
      return;
    }
    unawaited(
      service.observe(
        compKey: compKey,
        tipperKey: tipperKey,
        shown: (String gameKey) {
          final shownTip = tips.submittedTipForGame(gameKey, tipper);
          return shownTip == null
              ? null
              : (
                  choice: shownTip.tip.name,
                  submittedUtcSeconds:
                      shownTip.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000,
                );
        },
      ),
    );
  }

  /// Says so when a tip did not count, however long after it was made that
  /// became known.
  void _showTipNotices() {
    final UnconfirmedTipsService? service = _unconfirmedTips;
    if (!mounted || service == null || _tipNoticeShowing) {
      return;
    }
    final List<String> messages = service.takeNotices();
    if (messages.isEmpty) {
      return;
    }
    _tipNoticeShowing = true;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          icon: const Icon(Icons.info_outline),
          title: const Text('Tip not counted'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String message in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(message),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ).whenComplete(() {
        _tipNoticeShowing = false;
        _showTipNotices();
      }),
    );
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
    _unconfirmedTips?.removeListener(_showTipNotices);
    _unconfirmedTips?.stopObserving();
    _watchedTips?.removeListener(_lookAtQueuedTips);
    _currentIndex.dispose();
    super.dispose();
  }

  /// The destinations the floating tab pill offers.
  List<AppNavDestination> _navDestinations(TippersViewModel tippersViewModel) {
    final tipsTabIcon = SizedBox(
      width: kGlassIconSlot,
      height: kGlassIconSlot,
      child: Center(
        child: Builder(
          builder: (context) {
            final iconTheme = IconTheme.of(context);
            return SvgPicture.asset(
              'assets/icon/DAU-football-black.svg',
              width: iconTheme.size ?? 24,
              height: iconTheme.size ?? 24,
              colorFilter: ColorFilter.mode(
                (iconTheme.color ?? Colors.black).withValues(
                  alpha: (iconTheme.color?.a ?? 1) * (iconTheme.opacity ?? 1),
                ),
                BlendMode.srcIn,
              ),
            );
          },
        ),
      ),
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
        enabled: !tippersViewModel.selectedTipper.isAnonymous,
      ),
      const AppNavDestination(
        icon: Icon(Icons.auto_graph),
        shortLabel: 'STATS',
      ),
      const AppNavDestination(icon: Icon(Icons.person), shortLabel: 'PROFILE'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> destinationContent = content();
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    return ChangeNotifierProvider<DAUCompsViewModel>.value(
      value: di<DAUCompsViewModel>(),
      child: ChangeNotifierProvider<TippersViewModel>.value(
        value: di<TippersViewModel>(),
        child: Consumer<DAUCompsViewModel>(
          builder: (context, dauCompsViewModelConsumer, child) {
            return Consumer<TippersViewModel>(
              builder: (context, tippersViewModelConsumer, child) {
                // The floating controls hold their own room clear of the
                // content, so the body is simply the selected tab.
                final Widget scaffold = AppNavTabsScope(
                  tabs: AppNavTabs(
                    destinations: _navDestinations(tippersViewModelConsumer),
                    selectedIndex: _currentIndex.value,
                    onSelected: onTabTapped,
                  ),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: RepaintBoundary(child: AppBackdrop()),
                      ),
                      Scaffold(
                        backgroundColor: !isDarkMode
                            ? Colors.white54
                            : Colors.black54,
                        body: AppContentWidth(
                          daurounds:
                              dauCompsViewModelConsumer
                                  .selectedDAUComp
                                  ?.daurounds ??
                              const [],
                          child: Center(
                            child: destinationContent[_currentIndex.value],
                          ),
                        ),
                      ),
                    ],
                  ),
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
