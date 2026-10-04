import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

typedef _TipsScrollTarget = ({double offset, int sectionIndex});

class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  TipsTabState createState() => TipsTabState();
}

class TipsTabState extends State<TipsTab> {
  static const int _maxStartupScrollRetries = 120;

  /// How long the first startup jump will wait for the list to stop growing
  /// before going anyway. Roughly two seconds of frames.
  static const int maxStartupHoldFrames = 120;
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();

  late ScrollController scrollController;
  late FocusNode focusNode;
  String? _lastScrollSignature;
  double _pendingStartupOffset = 0;
  bool _startupScrollPending = false;
  bool _startupScrollSettled = false;
  int _startupScrollRetryCount = 0;
  double _lastStartupMaxScrollExtent = -1;
  int _startupHoldFrames = 0;
  bool _hasJumpedOnce = false;

  /// Whether the list has been placed at least once since a competition was
  /// selected. Distinct from [_hasJumpedOnce], which the hold re-arms on every
  /// relayout: a fold must not put the spinner back.
  bool _hasPlacedOnce = false;

  /// Height seen on the previous held frame. Separate from
  /// [_lastStartupMaxScrollExtent], which the post-jump settle check owns:
  /// writing that one here would tell it the height had already settled and
  /// stop it correcting for the shrink the first jump itself causes.
  double _holdPreviousMaxScrollExtent = -1;
  int _activeSectionIndex = 0;
  bool _showLoadingPlaceholder = true;
  bool _stickyHeaderVisible = false;
  double _topSafeInset = 0;
  List<TipsLeagueSection> _cachedSections = const [];
  TipsCardLayout? _cardLayout;
  String? _cardLayoutKey;
  final ValueNotifier<double> _stickyHeaderPushUpOffset = ValueNotifier<double>(
    0,
  );

  @override
  void initState() {
    super.initState();

    focusNode = FocusNode();
    scrollController = ScrollController();
    scrollController.addListener(_handleScrollChanged);
    daucompsViewModel.addListener(_onDAUCompsChanged);
    _showLoadingPlaceholder = daucompsViewModel.selectedDAUComp == null;
    _syncSelectedCompState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _topSafeInset = MediaQuery.paddingOf(context).top;
  }

  double get _welcomeSliverHeight => WelcomeHeader.height + _topSafeInset;

  void _onDAUCompsChanged() {
    if (!mounted) return;
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      _lastScrollSignature = null;
      _resetStartupScrollState();
      _activeSectionIndex = 0;
      _stickyHeaderVisible = false;
      _cachedSections = const [];
      _stickyHeaderPushUpOffset.value = 0;
      _hasPlacedOnce = false;
      if (!_showLoadingPlaceholder) {
        setState(() {
          _showLoadingPlaceholder = true;
        });
      }
      return;
    }

    _cachedSections = buildTipsLeagueSections(
      selectedComp: selectedComp,
      cardExtent: _cardExtent,
      headerExtent: _headerExtent,
    );
    _syncSelectedCompState();
    if (!_startupScrollPending) {
      _syncActiveSectionIndex();
      _syncStickyHeaderPushUp();
    }
    if (_showLoadingPlaceholder) {
      setState(() {
        _showLoadingPlaceholder = false;
      });
    }
  }

  void _syncSelectedCompState() {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      return;
    }

    final latestRoundNumber = selectedComp.latestsCompletedRoundNumber();
    final tipsLoaded =
        daucompsViewModel.selectedTipperTipsViewModel?.isInitialLoadComplete ??
        false;
    final nextScrollSignature =
        '${selectedComp.dbkey}:$latestRoundNumber:$tipsLoaded:$_cardExtent:'
        '${_buildItemExtentCacheKey(selectedComp)}';
    if (_lastScrollSignature != nextScrollSignature) {
      _lastScrollSignature = nextScrollSignature;
      _startupScrollSettled = false;
      _startupScrollRetryCount = 0;
      _lastStartupMaxScrollExtent = -1;
    }
    if (_startupScrollSettled) {
      return;
    }
    log(
      'TipsPageBody._syncSelectedCompState() latestRoundNumber: $latestRoundNumber',
    );

    _cachedSections = buildTipsLeagueSections(
      selectedComp: selectedComp,
      cardExtent: _cardExtent,
      headerExtent: _headerExtent,
    );
    final sections = _cachedSections;
    final defaultTarget = _defaultScrollTarget(
      selectedComp: selectedComp,
      sections: sections,
      latestRoundNumber: latestRoundNumber,
    );
    _pendingStartupOffset = defaultTarget.offset;
    if (_activeSectionIndex != defaultTarget.sectionIndex) {
      _activeSectionIndex = defaultTarget.sectionIndex;
    }
    _syncStickyHeaderVisibility(scrollOffsetOverride: _pendingStartupOffset);
    _syncStickyHeaderPushUp(scrollOffsetOverride: _pendingStartupOffset);

    // A post-frame jump may already be queued from an earlier startup state.
    // Reuse that callback with the latest computed target instead of locking
    // in the stale offset from the first cold-start snapshot.
    if (_startupScrollPending) {
      return;
    }

    _scheduleStartupScrollAttempt();
  }

  /// [allowHold] is false when the caller already knows the list is built --
  /// the navigation cycle reuses this machinery on a settled page, where
  /// waiting for the height to stop moving would only cost it a frame.
  void _scheduleStartupScrollAttempt({bool allowHold = true}) {
    _startupScrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupScrollPending = false;
      if (!mounted || !scrollController.hasClients) {
        return;
      }

      final maxScrollExtent = scrollController.position.maxScrollExtent;

      // Sections have no games in them yet on the first frames, so the list is
      // a fraction of its eventual height and an offset computed against it
      // lands on the wrong round. Wait for the height to stop moving before
      // the first jump instead of jumping and correcting in full view.
      if (allowHold &&
          shouldHoldStartupJump(
            hasJumped: _hasJumpedOnce,
            previousMaxScrollExtent: _holdPreviousMaxScrollExtent,
            maxScrollExtent: maxScrollExtent,
            heldFrames: _startupHoldFrames,
          )) {
        _startupHoldFrames += 1;
        _holdPreviousMaxScrollExtent = maxScrollExtent;
        _scheduleStartupScrollAttempt(allowHold: allowHold);
        return;
      }

      final clampedOffset = _pendingStartupOffset.clamp(0.0, maxScrollExtent);
      scrollController.jumpTo(clampedOffset);
      _hasJumpedOnce = true;
      if (!_hasPlacedOnce) {
        setState(() {
          _hasPlacedOnce = true;
        });
      }
      _syncStickyHeaderVisibility(scrollOffsetOverride: clampedOffset);
      _syncActiveSectionIndex(scrollOffsetOverride: clampedOffset);
      _syncStickyHeaderPushUp(scrollOffsetOverride: clampedOffset);

      final hitTarget = (scrollController.offset - clampedOffset).abs() <= 8;
      final targetBeyondCurrentMax =
          _pendingStartupOffset > maxScrollExtent + 8;
      final maxScrollExtentStable =
          (_lastStartupMaxScrollExtent - maxScrollExtent).abs() <= 8;
      if (hitTarget && (!targetBeyondCurrentMax || maxScrollExtentStable)) {
        _startupScrollSettled = true;
        StartupProfiling.end('startup.tips_page_stable');
        return;
      }

      if (_startupScrollRetryCount >= _maxStartupScrollRetries) {
        _startupScrollSettled = true;
        return;
      }

      _startupScrollRetryCount += 1;
      _lastStartupMaxScrollExtent = maxScrollExtent;
      _scheduleStartupScrollAttempt(allowHold: allowHold);
    });
  }

  void _resetStartupScrollState() {
    _pendingStartupOffset = 0;
    _startupScrollPending = false;
    _startupScrollSettled = false;
    _startupScrollRetryCount = 0;
    _lastStartupMaxScrollExtent = -1;
    _rearmStartupHold();
  }

  /// Lets the hold guard the next jump again after the layout moves under it.
  /// Narrower than [_resetStartupScrollState]: the pending offset survives,
  /// because only the extents it was measured against have changed.
  void _rearmStartupHold() {
    _startupHoldFrames = 0;
    _hasJumpedOnce = false;
    _holdPreviousMaxScrollExtent = -1;
  }

  /// Re-places the list after the cards are remeasured.
  ///
  /// Offsets are pixels, so folding or rotating moves every section while the
  /// scroll offset stays put, leaving a different round on screen. Nothing
  /// else corrects it: startup placement only runs off a view model
  /// notification, and a relayout is not one. Re-uses the startup target
  /// rather than inventing a second placement rule, with the hold re-armed so
  /// it waits for the new extents to settle exactly as a cold start does.
  void _replaceAfterRelayout(DAUComp selectedComp) {
    _rearmStartupHold();
    final target = _defaultScrollTarget(
      selectedComp: selectedComp,
      sections: _cachedSections,
      latestRoundNumber: selectedComp.latestsCompletedRoundNumber(),
    );
    _pendingStartupOffset = target.offset;
    _activeSectionIndex = target.sectionIndex;
    _startupScrollSettled = false;
    _startupScrollRetryCount = 0;
    _lastStartupMaxScrollExtent = -1;
    if (!_startupScrollPending) {
      _scheduleStartupScrollAttempt();
    }
  }

  /// Whether the first startup jump should wait another frame.
  ///
  /// The tips list grows as game data streams in, and the target offset is
  /// derived from the section extents, so both climb together during startup.
  /// Jumping before they settle puts the user on the wrong round and then
  /// moves them. Only the first jump waits; later corrections are cheap
  /// because the user is already in the right place.
  @visibleForTesting
  static bool shouldHoldStartupJump({
    required bool hasJumped,
    required double previousMaxScrollExtent,
    required double maxScrollExtent,
    required int heldFrames,
    int maxHeldFrames = maxStartupHoldFrames,
  }) {
    if (hasJumped) return false;
    if (heldFrames >= maxHeldFrames) return false;
    return (maxScrollExtent - previousMaxScrollExtent).abs() > 8;
  }

  void scrollToNextNavigationPosition() {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      return;
    }

    final sections = buildTipsLeagueSections(
      selectedComp: selectedComp,
      cardExtent: _cardExtent,
      headerExtent: _headerExtent,
    );
    if (sections.isEmpty) {
      return;
    }
    _cachedSections = sections;

    final defaultTarget = _defaultScrollTarget(
      selectedComp: selectedComp,
      sections: sections,
      latestRoundNumber: selectedComp.latestsCompletedRoundNumber(),
    );
    final targetRoundIndex = sections[defaultTarget.sectionIndex].roundIndex;
    final leagueTargets = <_TipsScrollTarget>[
      for (final league in const [League.nrl, League.afl])
        if (_sectionIndexForRoundAndLeague(
              sections: sections,
              roundIndex: targetRoundIndex,
              league: league,
            )
            case final sectionIndex when sectionIndex >= 0)
          (
            offset: _startupScrollOffset(
              sections: sections,
              targetSectionIndex: sectionIndex,
            ),
            sectionIndex: sectionIndex,
          ),
    ];
    final defaultMatchesLeagueTarget = leagueTargets.any(
      (target) => (target.offset - defaultTarget.offset).abs() <= 8,
    );
    final cycleTargets = defaultMatchesLeagueTarget
        ? leagueTargets
        : [defaultTarget, ...leagueTargets];
    if (cycleTargets.isEmpty) {
      return;
    }

    final maxScrollExtent = scrollController.hasClients
        ? scrollController.position.maxScrollExtent
        : double.infinity;
    final currentOffset = scrollController.hasClients
        ? scrollController.offset
        : 0.0;
    final currentTargetIndex = cycleTargets.indexWhere((target) {
      final reachableOffset = target.offset.clamp(0.0, maxScrollExtent);
      return (currentOffset - reachableOffset).abs() <= 8;
    });
    final nextTarget = currentTargetIndex == -1
        ? cycleTargets.first
        : cycleTargets[(currentTargetIndex + 1) % cycleTargets.length];

    _resetStartupScrollState();
    _pendingStartupOffset = nextTarget.offset;
    final nextActiveSectionIndex = activeStickyTipsLeagueSectionIndex(
      sections: sections,
      scrollOffset: nextTarget.offset,
      leadingExtent: _welcomeSliverHeight,
      topSafeInset: _topSafeInset,
    );
    final sectionChanged = _activeSectionIndex != nextActiveSectionIndex;
    _activeSectionIndex = nextActiveSectionIndex;
    final visibilityChanged = _updateStickyHeaderVisibility(
      scrollOffsetOverride: nextTarget.offset,
    );
    _syncStickyHeaderPushUp(scrollOffsetOverride: nextTarget.offset);
    if (sectionChanged || visibilityChanged) {
      setState(() {});
    }
    _scheduleStartupScrollAttempt(allowHold: false);
  }

  _TipsScrollTarget _defaultScrollTarget({
    required DAUComp selectedComp,
    required List<TipsLeagueSection> sections,
    required int latestRoundNumber,
  }) {
    final isCompComplete =
        latestRoundNumber >= selectedComp.daurounds.length &&
        sections.isNotEmpty;
    if (isCompComplete) {
      return (
        offset: _endFooterStartupOffset(sections),
        sectionIndex: sections.length - 1,
      );
    }

    final targetSectionIndex = _targetStartupSectionIndex(
      selectedComp,
      sections,
    );
    final base = _startupScrollOffset(
      sections: sections,
      targetSectionIndex: targetSectionIndex,
    );
    final refinement = _intraRoundScrollRefinement(
      selectedComp: selectedComp,
      sections: sections,
      targetSectionIndex: targetSectionIndex,
    );
    return (offset: base + refinement, sectionIndex: targetSectionIndex);
  }

  int _sectionIndexForRoundAndLeague({
    required List<TipsLeagueSection> sections,
    required int roundIndex,
    required League league,
  }) {
    return sections.indexWhere(
      (section) => section.roundIndex == roundIndex && section.league == league,
    );
  }

  void _handleScrollChanged() {
    if (!mounted) {
      return;
    }
    final visibilityChanged = _updateStickyHeaderVisibility();
    final sectionChanged = _updateActiveSectionIndex();
    _updateStickyHeaderPushUp();
    if (visibilityChanged || sectionChanged) {
      setState(() {});
    }
  }

  int _targetStartupSectionIndex(
    DAUComp selectedComp,
    List<TipsLeagueSection> sections,
  ) {
    return targetStartupSectionIndex(selectedComp, sections);
  }

  double _startupScrollOffset({
    required List<TipsLeagueSection> sections,
    required int targetSectionIndex,
  }) {
    var offset = _welcomeSliverHeight;
    for (var index = 0; index < targetSectionIndex; index++) {
      if (index != 0) {
        offset += sections[index].headerExtent;
      }
      offset += sections[index].bodyExtent;
    }
    return targetSectionIndex == 0
        ? offset
        : (offset - _topSafeInset).clamp(0.0, double.infinity);
  }

  double _intraRoundScrollRefinement({
    required DAUComp selectedComp,
    required List<TipsLeagueSection> sections,
    required int targetSectionIndex,
  }) {
    final tipsViewModel = daucompsViewModel.selectedTipperTipsViewModel;
    if (tipsViewModel == null || !tipsViewModel.isInitialLoadComplete) {
      return 0;
    }

    final tipper = di<TippersViewModel>().selectedTipper;
    return intraRoundScrollRefinement(
      selectedComp: selectedComp,
      sections: sections,
      targetSectionIndex: targetSectionIndex,
      firstUntippedGameIndex: (games) =>
          tipsViewModel.firstUntippedGameIndex(games, tipper),
      cardExtent: _cardExtent,
    );
  }

  double _endFooterStartupOffset(List<TipsLeagueSection> sections) {
    if (sections.isEmpty) {
      return 0;
    }

    var offset = _welcomeSliverHeight + sections.first.bodyExtent;
    for (var index = 1; index < sections.length; index++) {
      offset += sections[index].headerExtent + sections[index].bodyExtent;
    }

    final stickyOverlayExtent = sections.last.headerExtent + _topSafeInset;
    return (offset - stickyOverlayExtent).clamp(0.0, double.infinity);
  }

  bool _updateStickyHeaderVisibility({double? scrollOffsetOverride}) {
    final scrollOffset =
        scrollOffsetOverride ??
        (scrollController.hasClients ? scrollController.offset : 0);
    final nextVisibility = scrollOffset >= _welcomeSliverHeight;
    if (_stickyHeaderVisible == nextVisibility) {
      return false;
    }
    _stickyHeaderVisible = nextVisibility;
    return true;
  }

  void _syncStickyHeaderVisibility({double? scrollOffsetOverride}) {
    if (_updateStickyHeaderVisibility(
      scrollOffsetOverride: scrollOffsetOverride,
    )) {
      setState(() {});
    }
  }

  bool _updateActiveSectionIndex({double? scrollOffsetOverride}) {
    final sections = _cachedSections;
    if (sections.isEmpty) {
      return false;
    }

    final scrollOffset =
        scrollOffsetOverride ??
        (scrollController.hasClients ? scrollController.offset : 0);
    final nextIndex = activeStickyTipsLeagueSectionIndex(
      sections: sections,
      scrollOffset: scrollOffset,
      leadingExtent: _welcomeSliverHeight,
      topSafeInset: _topSafeInset,
    );

    if (_activeSectionIndex == nextIndex) {
      return false;
    }
    _activeSectionIndex = nextIndex;
    return true;
  }

  void _syncActiveSectionIndex({double? scrollOffsetOverride}) {
    if (_updateActiveSectionIndex(scrollOffsetOverride: scrollOffsetOverride)) {
      setState(() {});
    }
  }

  bool _showsInlineHeaderForSection(int index, {required bool stickyVisible}) {
    return index != 0 || !stickyVisible;
  }

  double _sectionHeaderTopOffset(
    int targetSectionIndex, {
    required bool stickyVisible,
    List<TipsLeagueSection>? sections,
  }) {
    final activeSections = sections ?? _cachedSections;
    var offset = _welcomeSliverHeight;
    for (var index = 0; index < targetSectionIndex; index++) {
      if (_showsInlineHeaderForSection(index, stickyVisible: stickyVisible)) {
        offset += activeSections[index].headerExtent;
      }
      offset += activeSections[index].bodyExtent;
    }
    return offset;
  }

  bool _updateStickyHeaderPushUp({double? scrollOffsetOverride}) {
    final sections = _cachedSections;
    if (!_stickyHeaderVisible ||
        sections.isEmpty ||
        _activeSectionIndex >= sections.length - 1) {
      if (_stickyHeaderPushUpOffset.value == 0) {
        return false;
      }
      _stickyHeaderPushUpOffset.value = 0;
      return true;
    }

    final scrollOffset =
        scrollOffsetOverride ??
        (scrollController.hasClients ? scrollController.offset : 0);
    final stickyHeight = sections[_activeSectionIndex].headerExtent;
    final nextHeaderTop = _sectionHeaderTopOffset(
      _activeSectionIndex + 1,
      stickyVisible: true,
      sections: sections,
    );
    final distanceToNextHeader = nextHeaderTop - (scrollOffset + _topSafeInset);
    final nextPushUp = (stickyHeight - distanceToNextHeader).clamp(
      0.0,
      stickyHeight,
    );

    if ((_stickyHeaderPushUpOffset.value - nextPushUp).abs() <= 0.5) {
      return false;
    }

    _stickyHeaderPushUpOffset.value = nextPushUp;
    return true;
  }

  void _syncStickyHeaderPushUp({double? scrollOffsetOverride}) {
    _updateStickyHeaderPushUp(scrollOffsetOverride: scrollOffsetOverride);
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
    if (_showLoadingPlaceholder || daucompsViewModel.selectedDAUComp == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    // The list has to be laid out for its scroll controller to attach, and
    // placement cannot run until it is -- so while it is being placed it is
    // built and hidden rather than skipped. Skipping it would deadlock: no
    // list, no controller, no placement, no list. Hiding it spares the reader
    // watching it travel from round one to wherever they actually belong.
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          key: const Key('tipsPlacementVeil'),
          opacity: _hasPlacedOnce ? 1 : 0,
          child: _buildTipsList(),
        ),
        if (!_hasPlacedOnce)
          const Center(child: CircularProgressIndicator(color: Colors.orange)),
      ],
    );
  }

  Widget _buildTipsList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _syncCardLayout(context, constraints.maxWidth);
        final cardLayout = _cardLayout;
        if (cardLayout == null) {
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
            ],
            child: Theme(
              data: myTheme,
              child: Consumer<DAUCompsViewModel>(
                builder: (context, daucompsViewmodelConsumer, client) {
                  final sections = _cachedSections;
                  if (sections.isEmpty) {
                    return ChangeNotifierProvider<StatsViewModel?>.value(
                      value: daucompsViewmodelConsumer.statsViewModel,
                      child: CustomScrollView(
                        controller: scrollController,
                        restorationId: 'tipsListView',
                        slivers: const [SliverToBoxAdapter(child: EndFooter())],
                      ),
                    );
                  }
                  final stickySection =
                      sections[_activeSectionIndex.clamp(
                        0,
                        sections.length - 1,
                      )];

                  return ChangeNotifierProvider<StatsViewModel?>.value(
                    value: daucompsViewmodelConsumer.statsViewModel,
                    child: Stack(
                      children: [
                        CustomScrollView(
                          controller: scrollController,
                          restorationId: 'tipsListView',
                          slivers: [
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: _welcomeSliverHeight,
                                child: Column(
                                  children: [
                                    SizedBox(height: _topSafeInset),
                                    Expanded(
                                      child: WelcomeHeader(
                                        daucompsViewmodelConsumer:
                                            daucompsViewmodelConsumer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            for (
                              var sectionIndex = 0;
                              sectionIndex < sections.length;
                              sectionIndex++
                            )
                              ...buildRoundLeagueSectionSlivers(
                                section: sections[sectionIndex],
                                roundIndex: sections[sectionIndex].roundIndex,
                                league: sections[sectionIndex].league,
                                dauCompsViewModel: daucompsViewmodelConsumer,
                                currentTipper:
                                    di<TippersViewModel>().selectedTipper,
                                isPercentStatsPage: false,
                                showInlineHeader:
                                    sectionIndex != 0 || !_stickyHeaderVisible,
                                hideInlineHeaderVisual:
                                    _stickyHeaderVisible &&
                                    sectionIndex == _activeSectionIndex,
                                layout: cardLayout,
                              ),
                            const SliverToBoxAdapter(child: EndFooter()),
                          ],
                        ),
                        if (_stickyHeaderVisible)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _stickyHeaderPushUpOffset,
                                builder: (context, pushUpOffset, child) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(height: _topSafeInset),
                                      Transform.translate(
                                        offset: Offset(0, -pushUpOffset),
                                        child: child,
                                      ),
                                    ],
                                  );
                                },
                                child: TipsStickyHeader(
                                  inlineRoundLabel: cardLayout.inlineRoundLabel,
                                  section: stickySection,
                                  dauCompsViewModel: daucompsViewmodelConsumer,
                                  currentTipper:
                                      di<TippersViewModel>().selectedTipper,
                                  isPercentStatsPage: false,
                                  topPadding: 0,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// The measured row height every scroll offset in this tab is built from.
  /// Exposed so navigation tests assert against the same value the list uses
  /// rather than a constant that no longer describes the row.
  double get cardExtent => _cardExtent;

  double get _headerExtent =>
      _cardLayout?.headerExtent ?? DAURound.leagueHeaderHeight;

  /// The measured row height, or the legacy constant before the first layout
  /// pass. Offsets built from the fallback are corrected by the startup scroll
  /// retry once the real measurement arrives.
  double get _cardExtent => _cardLayout?.cardExtent ?? Game.gameCardHeight;

  /// Measures once per competition, width and text scale. The width comes from
  /// the list's own constraints and never from MediaQuery: the app shell caps
  /// the content, so the window is a different box from the card.
  void _syncCardLayout(BuildContext context, double width) {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null || width <= 0) {
      return;
    }
    final textScaler = MediaQuery.textScalerOf(context);
    final textTheme = Theme.of(context).textTheme;
    // Keyed on the games too, not just the comp. Team names arrive with them,
    // and they set the width the inline matchup needs -- measured before they
    // land, the row is sized for names it has not seen, so they wrap and the
    // score falls out of the height measured for them. Without this the first
    // measurement stands for the life of the comp at this width.
    final key =
        '${selectedComp.dbkey}:$width:${textScaler.scale(16)}:'
        '${_buildItemExtentCacheKey(selectedComp)}';
    if (key == _cardLayoutKey && _cardLayout != null) {
      return;
    }
    _cardLayoutKey = key;
    final previousExtent = _cardLayout?.cardExtent;
    final previousHeaderExtent = _cardLayout?.headerExtent;
    final nextLayout = TipsCardLayout.measure(
      width: width,
      textScaler: textScaler,
      textTheme: textTheme,
      textDirection: Directionality.of(context),
      cards: [
        for (final card in tipsMeasurementCards(selectedComp.daurounds))
          card.content(textTheme),
      ],
    );
    _cardLayout = nextLayout;

    if (previousExtent == nextLayout.cardExtent &&
        previousHeaderExtent == nextLayout.headerExtent) {
      return;
    }
    // The cached sections describe the previous row height, and the sticky
    // header is positioned from them. Rebuild in this same frame, before the
    // slivers below read them, so the header never sits against stale offsets
    // waiting for the next view model notification to correct it.
    _cachedSections = buildTipsLeagueSections(
      selectedComp: selectedComp,
      cardExtent: nextLayout.cardExtent,
      headerExtent: nextLayout.headerExtent,
    );
    // The first measurement counts too. Until it lands the extents are
    // Game.gameCardHeight, a fallback the startup target is computed against
    // and which the measured card does not match -- 128 against 124 here, and
    // the target it placed 47 out. Excluding it left the list resting beside
    // the position its own placement had chosen.
    _replaceAfterRelayout(selectedComp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncStickyHeaderVisibility();
      _syncActiveSectionIndex();
      _syncStickyHeaderPushUp();
    });
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
    _stickyHeaderPushUpOffset.dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

/// The last card of the list.
///
/// Taller by the room the floating controls take along the bottom, so the card
/// can scroll clear of them. Its content stays where it was, at the top, and the
/// extra is simply card below it.
class EndFooter extends StatelessWidget {
  const EndFooter({super.key});

  static const double height = kTipsEndFooterHeight;

  @override
  Widget build(BuildContext context) {
    final controlsRoom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: height + controlsRoom,
      child: _CompBoundaryCard(
        iconSize: 46,
        title: 'End of regular competition',
        body: 'Hope to see you again next year.',
        bottomRoom: controlsRoom,
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
    return _CompBoundaryCard(
      iconSize: 64,
      title:
          'Start of competition\n${daucompsViewmodelConsumer.selectedDAUComp!.name}',
      body: 'New here? You will find instructions and scoring information in the [Help...] section on the Profile Tab.',
    );
  }
}

class _CompBoundaryCard extends StatelessWidget {
  const _CompBoundaryCard({
    required this.iconSize,
    required this.title,
    this.body,
    this.bottomRoom = 0,
  });

  final double iconSize;
  final String title;
  final String? body;

  /// Extra card kept empty below the content.
  final double bottomRoom;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardCornerRadius),
      ),
      color: Colors.black38,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.0, 10.0, 18.0, 10.0 + bottomRoom),
        child: Row(
          children: [
            SizedBox(
              width: iconSize + 8,
              child: Center(child: AppIcon(size: iconSize, borderRadius: 12)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: body == null
                  ? Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            height: 1.1,
                          ),
                          softWrap: true,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            body!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.15,
                            ),
                            softWrap: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
