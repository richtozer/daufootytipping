import 'dart:developer';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatPercentTipped extends StatefulWidget {
  const StatPercentTipped({super.key});

  @override
  StatPercentTippedState createState() => StatPercentTippedState();
}

class StatPercentTippedState extends State<StatPercentTipped> {
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();

  int latestRoundNumber = 0;
  String? _lastScrolledCompDbKey;
  bool _selectingActiveComp = false;
  late ScrollController scrollController;
  late FocusNode focusNode;
  int initialScrollOffset = -150;

  @override
  void initState() {
    log('StatPercentTipped.constructor()');
    super.initState();

    focusNode = FocusNode();
    scrollController = ScrollController();
    daucompsViewModel.addListener(_handleDAUCompsUpdated);
    _syncSelectedCompState();
    _ensureSelectedComp();
  }

  void _handleDAUCompsUpdated() {
    if (!mounted) return;
    _syncSelectedCompState();
    _ensureSelectedComp();
  }

  void _syncSelectedCompState() {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      return;
    }

    final nextLatestRoundNumber = selectedComp.latestsCompletedRoundNumber();
    log(
      'StatPercentTipped._syncSelectedCompState() latestRoundNumber: $nextLatestRoundNumber',
    );

    if (latestRoundNumber != nextLatestRoundNumber && mounted) {
      setState(() {
        latestRoundNumber = nextLatestRoundNumber;
      });
    }

    if (_lastScrolledCompDbKey != selectedComp.dbkey) {
      _lastScrolledCompDbKey = selectedComp.dbkey;
      final targetOffset =
          selectedComp.pixelHeightUpToRound(nextLatestRoundNumber) +
          initialScrollOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.hasClients) {
          return;
        }

        final clampedOffset = targetOffset.clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        );
        scrollController.jumpTo(clampedOffset);
      });
    }
  }

  void _ensureSelectedComp() {
    if (_selectingActiveComp ||
        daucompsViewModel.selectedDAUComp != null ||
        daucompsViewModel.activeDAUComp == null) {
      return;
    }

    _selectingActiveComp = true;
    daucompsViewModel
        .changeDisplayedDAUComp(daucompsViewModel.activeDAUComp!, false)
        .whenComplete(() {
          _selectingActiveComp = false;
        });
  }

  void _handleKeyEvent(KeyEvent event, BuildContext context) {
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
    log('StatPercentTipped.build()');

    Orientation orientation = MediaQuery.of(context).orientation;

    if (daucompsViewModel.selectedDAUComp == null) {
      return Center(
        child: SizedBox(
          height: 75,
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            color: Colors.black38,
            child: Center(
              child: Text(
                'Nothing to see here.\nContact support: https://interview.coach/tipping.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      );
    }

    return KeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, context),
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
              final selectedComp = daucompsViewmodelConsumer.selectedDAUComp;
              if (selectedComp == null) {
                return const SizedBox.shrink();
              }
              final sections = buildTipsLeagueSections(
                selectedComp: selectedComp,
                roundCount: latestRoundNumber,
              );

              return Scaffold(
                floatingActionButton: FloatingActionButton(
                  backgroundColor: Colors.lightGreen[200],
                  foregroundColor: Colors.white70,
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.arrow_back),
                ),
                body: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    if (orientation == Orientation.portrait)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Percentage Tipped',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Hero(
                                  tag: 'percentage',
                                  child: Icon(Icons.percent, size: 50),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Breakdown of how people tipped each game. Legend: 🟩 = Your tip, 🏆 = Game result.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: CustomScrollView(
                        controller: scrollController,
                        restorationId: 'statsPercentTippedView',
                        slivers: [
                          for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++)
                            ...buildRoundLeagueSectionSlivers(
                              section: sections[sectionIndex],
                              roundIndex: sections[sectionIndex].roundIndex,
                              league: sections[sectionIndex].league,
                              dauCompsViewModel: daucompsViewmodelConsumer,
                              currentTipper: di<TippersViewModel>().selectedTipper,
                              isPercentStatsPage: true,
                              showInlineHeader: true,
                              hideInlineHeaderVisual: false,
                            ),
                        ],
                      ),
                    ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    daucompsViewModel.removeListener(_handleDAUCompsUpdated);
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
