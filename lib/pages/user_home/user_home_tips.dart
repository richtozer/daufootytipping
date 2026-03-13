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
  String? _lastScrollSignature;
  double _pendingStartupOffset = 0;
  bool _startupScrollPending = false;
  bool _startupScrollSettled = false;
  int _startupScrollRetryCount = 0;
  double _lastStartupMaxScrollExtent = -1;
  int? _startupTargetSectionIndex;
  int _activeSectionIndex = 0;
  bool _showLoadingPlaceholder = true;
  bool _stickyHeaderVisible = false;
  double _topSafeInset = 0;
  List<TipsLeagueSection> _cachedSections = const [];

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
      if (!_showLoadingPlaceholder) {
        setState(() {
          _showLoadingPlaceholder = true;
        });
      }
      return;
    }

    _cachedSections = buildTipsLeagueSections(selectedComp: selectedComp);
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

    _cachedSections = buildTipsLeagueSections(selectedComp: selectedComp);
    final sections = _cachedSections;
    final isCompComplete =
        latestRoundNumber >= selectedComp.daurounds.length &&
        sections.isNotEmpty;
    if (isCompComplete) {
      _pendingStartupOffset = _endFooterStartupOffset(sections);
      _startupTargetSectionIndex = sections.length - 1;
      _activeSectionIndex = _startupTargetSectionIndex!;
      _syncStickyHeaderVisibility(scrollOffsetOverride: _pendingStartupOffset);
    } else {
      final targetSectionIndex = _targetStartupSectionIndex(
        selectedComp,
        sections,
      );
      _startupTargetSectionIndex = targetSectionIndex;
      _pendingStartupOffset = _startupScrollOffset(
        sections: sections,
        targetSectionIndex: targetSectionIndex,
      );
      if (_activeSectionIndex != targetSectionIndex) {
        _activeSectionIndex = targetSectionIndex;
      }
      _syncStickyHeaderVisibility(scrollOffsetOverride: _pendingStartupOffset);
    }

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
      _syncStickyHeaderVisibility(scrollOffsetOverride: clampedOffset);
      if (_startupTargetSectionIndex != null &&
          (_pendingStartupOffset - clampedOffset).abs() <= 8) {
        final targetSectionIndex = _startupTargetSectionIndex!;
        if (_activeSectionIndex != targetSectionIndex) {
          setState(() {
            _activeSectionIndex = targetSectionIndex;
          });
        }
      } else {
        _syncActiveSectionIndex(scrollOffsetOverride: clampedOffset);
      }

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
      _scheduleStartupScrollAttempt();
    });
  }

  void _resetStartupScrollState() {
    _pendingStartupOffset = 0;
    _startupScrollPending = false;
    _startupScrollSettled = false;
    _startupScrollRetryCount = 0;
    _lastStartupMaxScrollExtent = -1;
    _startupTargetSectionIndex = null;
  }

  void _handleScrollChanged() {
    if (!mounted) {
      return;
    }
    final visibilityChanged = _updateStickyHeaderVisibility();
    final sectionChanged = _updateActiveSectionIndex();
    if (visibilityChanged || sectionChanged) {
      setState(() {});
    }
  }

  int _targetStartupSectionIndex(
    DAUComp selectedComp,
    List<TipsLeagueSection> sections,
  ) {
    if (sections.isEmpty) {
      return 0;
    }

    final latestCompletedRoundNumber = selectedComp
        .latestsCompletedRoundNumber();
    final targetRoundIndex = latestCompletedRoundNumber.clamp(
      0,
      selectedComp.daurounds.length - 1,
    );
    final targetSectionIndex = sections.indexWhere(
      (section) =>
          section.roundIndex == targetRoundIndex &&
          section.league == League.nrl,
    );
    return targetSectionIndex == -1 ? 0 : targetSectionIndex;
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

    final baseScrollOffset =
        scrollOffsetOverride ??
        (scrollController.hasClients ? scrollController.offset : 0);
    final baseIndex = activeTipsLeagueSectionIndex(
      sections: sections,
      scrollOffset: baseScrollOffset,
      leadingExtent: _welcomeSliverHeight,
    );
    final stickyVisible = scrollOffsetOverride != null
        ? baseScrollOffset >= _welcomeSliverHeight
        : _stickyHeaderVisible;
    final referenceIndex = baseIndex.clamp(0, sections.length - 1);
    final overlayAdjustedOffset =
        baseScrollOffset +
        (stickyVisible
            ? sections[referenceIndex].headerExtent + _topSafeInset
            : 0);
    final nextIndex = activeTipsLeagueSectionIndex(
      sections: sections,
      scrollOffset: overlayAdjustedOffset,
      leadingExtent: _welcomeSliverHeight,
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
              final sections = _cachedSections;
              if (sections.isEmpty) {
                return CustomScrollView(
                  controller: scrollController,
                  restorationId: 'tipsListView',
                  slivers: const [SliverToBoxAdapter(child: EndFooter())],
                );
              }
              final stickySection =
                  sections[_activeSectionIndex.clamp(0, sections.length - 1)];

              return Stack(
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
                          currentTipper: di<TippersViewModel>().selectedTipper,
                          isPercentStatsPage: false,
                          showInlineHeader:
                              sectionIndex != 0 || !_stickyHeaderVisible,
                          hideInlineHeaderVisual:
                              _stickyHeaderVisible &&
                              sectionIndex == _activeSectionIndex,
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
                        child: TipsStickyHeader(
                          section: stickySection,
                          dauCompsViewModel: daucompsViewmodelConsumer,
                          currentTipper: di<TippersViewModel>().selectedTipper,
                          isPercentStatsPage: false,
                          topPadding: _topSafeInset,
                        ),
                      ),
                    ),
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
      child: const _CompBoundaryCard(
        iconSize: 46,
        title: 'End of regular competition',
        body: 'Hope to see you again next year.',
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
      body:
          'New here? You will find instructions and scoring information in the [Help...] section on the Profile Tab.',
    );
  }
}

class _CompBoundaryCard extends StatelessWidget {
  const _CompBoundaryCard({
    required this.iconSize,
    required this.title,
    this.body,
  });

  final double iconSize;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      color: Colors.black38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
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
                            fontSize: 17,
                          ),
                          softWrap: true,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Center(
                            child: Text(
                              body!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                              softWrap: true,
                              textAlign: TextAlign.center,
                            ),
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
