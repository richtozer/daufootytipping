import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  TipsTabState createState() => TipsTabState();
}

class TipsTabState extends State<TipsTab> {
  static const int _maxStartupScrollRetries = 120;
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();

  late ScrollController scrollController;
  late FocusNode focusNode;
  int initialScrollOffset = -150;
  String? _lastScrollSignature;
  double _pendingStartupOffset = 0;
  bool _startupScrollPending = false;
  bool _startupScrollSettled = false;
  int _startupScrollRetryCount = 0;
  int _activeSectionIndex = 0;
  bool _showLoadingPlaceholder = true;

  @override
  void initState() {
    log('TipsPageBody.constructor()');
    super.initState();

    focusNode = FocusNode();
    scrollController = ScrollController();
    scrollController.addListener(_handleScrollChanged);
    daucompsViewModel.addListener(_onDAUCompsChanged);
    _showLoadingPlaceholder = daucompsViewModel.selectedDAUComp == null;
    _syncSelectedCompState();
  }

  void _onDAUCompsChanged() {
    if (!mounted) return;
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      _lastScrollSignature = null;
      _resetStartupScrollState();
      _activeSectionIndex = 0;
      if (!_showLoadingPlaceholder) {
        setState(() {
          _showLoadingPlaceholder = true;
        });
      }
      return;
    }

    _syncActiveSectionIndex();
    _syncSelectedCompState();
    if (_showLoadingPlaceholder) {
      setState(() {
        _showLoadingPlaceholder = false;
      });
    }
  }

  void _syncSelectedCompState() {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      log('TipsPageBody._syncSelectedCompState() selectedDAUComp is null');
      return;
    }

    final latestRoundNumber = selectedComp.latestsCompletedRoundNumber();
    final nextScrollSignature =
        '${selectedComp.dbkey}:$latestRoundNumber:${_buildItemExtentCacheKey(selectedComp)}';
    if (_lastScrollSignature != nextScrollSignature) {
      _lastScrollSignature = nextScrollSignature;
      _startupScrollSettled = false;
      _startupScrollRetryCount = 0;
    }
    if (_startupScrollSettled || _startupScrollPending) {
      return;
    }
    log(
      'TipsPageBody._syncSelectedCompState() latestRoundNumber: $latestRoundNumber',
    );

    _pendingStartupOffset =
        selectedComp.pixelHeightUpToRound(latestRoundNumber) + initialScrollOffset;

    _scheduleStartupScrollAttempt();
  }

  void _scheduleStartupScrollAttempt() {
    _startupScrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupScrollPending = false;
      if (!mounted || !scrollController.hasClients) {
        return;
      }

      final maxScrollExtent = scrollController.position.maxScrollExtent;
      final clampedOffset = _pendingStartupOffset.clamp(0.0, maxScrollExtent);
      scrollController.jumpTo(clampedOffset);

      final canReachTarget = maxScrollExtent + 8 >= _pendingStartupOffset;
      final hitTarget = (scrollController.offset - clampedOffset).abs() <= 8;
      final hitScrollBoundary =
          (clampedOffset - maxScrollExtent).abs() <= 8 ||
          clampedOffset.abs() <= 8;
      if (hitTarget && (canReachTarget || hitScrollBoundary)) {
        _startupScrollSettled = true;
        StartupProfiling.end('startup.tips_page_stable');
        return;
      }

      if (_startupScrollRetryCount >= _maxStartupScrollRetries) {
        _startupScrollSettled = true;
        return;
      }

      _startupScrollRetryCount += 1;
      _scheduleStartupScrollAttempt();
    });
  }

  void _resetStartupScrollState() {
    _pendingStartupOffset = 0;
    _startupScrollPending = false;
    _startupScrollSettled = false;
    _startupScrollRetryCount = 0;
  }

  void _handleScrollChanged() {
    if (!mounted) {
      return;
    }
    _syncActiveSectionIndex();
  }

  void _syncActiveSectionIndex() {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      return;
    }

    final sections = buildTipsLeagueSections(selectedComp: selectedComp);
    if (sections.isEmpty) {
      return;
    }

    final nextIndex = activeTipsLeagueSectionIndex(
      sections: sections,
      scrollOffset: scrollController.hasClients ? scrollController.offset : 0,
      leadingExtent: WelcomeHeader.height,
    );

    if (_activeSectionIndex != nextIndex) {
      setState(() {
        _activeSectionIndex = nextIndex;
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final double viewportHeight = MediaQuery.of(context).size.height;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _scrollBy(100);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _scrollBy(-100);
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _scrollBy(300);
      } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
        _scrollBy(viewportHeight);
      } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
        _scrollBy(-viewportHeight);
      }
    }
  }

  void _scrollBy(double offset) {
    scrollController.animateTo(
      scrollController.offset + offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    log('TipsPageBody.build()');

    if (_showLoadingPlaceholder || daucompsViewModel.selectedDAUComp == null) {
      log('TipsPageBody.build() selectedDAUComp is null; waiting for load');
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    return KeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<DAUCompsViewModel>.value(
            value: daucompsViewModel,
          ),
          ChangeNotifierProvider<StatsViewModel?>.value(
            value: daucompsViewModel.statsViewModel,
          ),
        ],
        child: Theme(
          data: myTheme,
          child: Consumer<DAUCompsViewModel>(
            builder: (context, daucompsViewmodelConsumer, client) {
              final sections = buildTipsLeagueSections(
                selectedComp: daucompsViewmodelConsumer.selectedDAUComp!,
              );
              if (sections.isEmpty) {
                return CustomScrollView(
                  controller: scrollController,
                  restorationId: 'tipsListView',
                  slivers: const [
                    SliverToBoxAdapter(child: EndFooter()),
                  ],
                );
              }
              final stickySection = sections[_activeSectionIndex.clamp(
                0,
                sections.length - 1,
              )];
              final topSafeInset = MediaQuery.paddingOf(context).top;

              return CustomScrollView(
                controller: scrollController,
                restorationId: 'tipsListView',
                slivers: [
                  SliverToBoxAdapter(
                    child: WelcomeHeader(
                      daucompsViewmodelConsumer: daucompsViewmodelConsumer,
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: TipsStickyHeaderDelegate(
                      extent: stickySection.headerExtent,
                      topPadding: topSafeInset,
                      child: TipsStickyHeader(
                        section: stickySection,
                        dauCompsViewModel: daucompsViewmodelConsumer,
                        currentTipper: di<TippersViewModel>().selectedTipper,
                        isPercentStatsPage: false,
                        topPadding: topSafeInset,
                      ),
                    ),
                  ),
                  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++)
                    ...buildRoundLeagueSectionSlivers(
                      section: sections[sectionIndex],
                      roundIndex: sections[sectionIndex].roundIndex,
                      league: sections[sectionIndex].league,
                      dauCompsViewModel: daucompsViewmodelConsumer,
                      currentTipper: di<TippersViewModel>().selectedTipper,
                      isPercentStatsPage: false,
                      showInlineHeader: sectionIndex != 0,
                      hideInlineHeaderVisual: sectionIndex == _activeSectionIndex,
                    ),
                  const SliverToBoxAdapter(child: EndFooter()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _buildItemExtentCacheKey(DAUComp selectedComp) {
    final buffer = StringBuffer('${selectedComp.dbkey}|');
    for (final dauRound in selectedComp.daurounds) {
      buffer
        ..write(dauRound.dAUroundNumber)
        ..write(':')
        ..write(dauRound.roundState.index)
        ..write(':')
        ..write(dauRound.getGamesForLeague(League.nrl).length)
        ..write(':')
        ..write(dauRound.getGamesForLeague(League.afl).length)
        ..write(';');
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    daucompsViewModel.removeListener(_onDAUCompsChanged);
    scrollController.removeListener(_handleScrollChanged);
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

class EndFooter extends StatelessWidget {
  const EndFooter({super.key});

  static const double height = kTipsEndFooterHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        color: Colors.black38,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Icon(Icons.flag, color: Colors.white70),
            Text(
              'End of regular competition',
              style: TextStyle(color: Colors.white70),
            ),
            Icon(Icons.flag, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({required this.daucompsViewmodelConsumer, super.key});

  final DAUCompsViewModel daucompsViewmodelConsumer;

  static const double height = kTipsWelcomeHeaderHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        color: Colors.black38,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Spacer(),
              const Spacer(),
              const Spacer(),
              const Spacer(),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Icon(Icons.sports_rugby, color: Colors.white70),
                  Text(
                    'Start of competition\n${daucompsViewmodelConsumer.selectedDAUComp!.name}',
                    style: const TextStyle(color: Colors.white70),
                    softWrap: true,
                  ),
                  const Icon(Icons.sports_rugby, color: Colors.white70),
                ],
              ),
              const Spacer(),
              const Text(
                'New here? You will find instructions and scoring information in the [Help...] section on the Profile Tab.',
                style: TextStyle(color: Colors.white70),
                softWrap: true,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
