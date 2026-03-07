import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipsTabItemExtentCache {
  const TipsTabItemExtentCache._();

  static List<double> buildExtents(DAUComp selectedComp) {
    final extents = <double>[WelcomeHeader.height];

    for (final dauRound in selectedComp.daurounds) {
      extents.add(_leagueHeaderExtent(dauRound, League.nrl));
      extents.add(_leagueGamesExtent(dauRound, League.nrl));
      extents.add(_leagueHeaderExtent(dauRound, League.afl));
      extents.add(_leagueGamesExtent(dauRound, League.afl));
    }

    extents.add(EndFooter.height);
    return extents;
  }

  static double _leagueHeaderExtent(DAURound dauRound, League league) {
    final games = dauRound.getGamesForLeague(league);
    if (games.isEmpty) {
      return DAURound.leagueHeaderHeight;
    }
    if (dauRound.roundState == RoundState.allGamesEnded) {
      return DAURound.leagueHeaderEndedHeight;
    }
    return DAURound.leagueHeaderHeight;
  }

  static double _leagueGamesExtent(DAURound dauRound, League league) {
    final games = dauRound.getGamesForLeague(league);
    if (games.isEmpty) {
      return DAURound.noGamesCardHeight;
    }
    return games.length * Game.gameCardHeight;
  }
}

class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  TipsTabState createState() => TipsTabState();
}

class TipsTabState extends State<TipsTab> {
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();

  int latestRoundNumber = 0;
  late ScrollController scrollController;
  late FocusNode focusNode;
  int initialScrollOffset = -150;
  bool _scrollSetupDone = false;
  String? _itemExtentCacheKey;
  List<double> _cachedItemExtents = const [];

  @override
  void initState() {
    log('TipsPageBody.constructor()');
    super.initState();

    focusNode = FocusNode();
    scrollController = ScrollController();
    daucompsViewModel.addListener(_onDAUCompsChanged);
    _setupInitialScroll();
  }

  void _onDAUCompsChanged() {
    if (!mounted) return;
    setState(_setupInitialScroll);
  }

  void _setupInitialScroll() {
    if (_scrollSetupDone) return;
    final selectedComp = daucompsViewModel.selectedDAUComp;
    if (selectedComp == null) {
      log('TipsPageBody._setupInitialScroll() selectedDAUComp is null');
      return;
    }

    _scrollSetupDone = true;
    latestRoundNumber = selectedComp.latestsCompletedRoundNumber();
    log('TipsPageBody._setupInitialScroll() latestRoundNumber: $latestRoundNumber');

    final initialOffset =
        selectedComp.pixelHeightUpToRound(latestRoundNumber) + initialScrollOffset;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      scrollController.jumpTo(initialOffset);
    });
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

    if (daucompsViewModel.selectedDAUComp == null) {
      log('TipsPageBody.build() selectedDAUComp is null; waiting for load');
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    _ensureItemExtentCache(daucompsViewModel.selectedDAUComp!);

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
              return CustomScrollView(
                controller: scrollController,
                restorationId: 'tipsListView',
                slivers: [
                  SliverVariedExtentList.builder(
                    itemExtentBuilder: (index, dimensions) {
                      return _cachedItemExtents[index];
                    },
                    itemCount: _cachedItemExtents.length,
                    itemBuilder: (context, index) {
                      log('building index: $index');
                      if (index == 0) {
                        return WelcomeHeader(
                          daucompsViewmodelConsumer: daucompsViewmodelConsumer,
                        );
                      }
                      if (index ==
                          (daucompsViewmodelConsumer
                                      .selectedDAUComp!
                                      .daurounds
                                      .length *
                                  4) +
                              1) {
                        return const EndFooter();
                      }

                      final roundIndex = (index - 1) ~/ 4;
                      final itemIndex = (index - 1) % 4;

                      return _buildItem(
                        daucompsViewmodelConsumer,
                        roundIndex,
                        itemIndex,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _ensureItemExtentCache(DAUComp selectedComp) {
    final nextKey = _buildItemExtentCacheKey(selectedComp);
    if (_itemExtentCacheKey == nextKey) {
      return;
    }

    _itemExtentCacheKey = nextKey;
    _cachedItemExtents = TipsTabItemExtentCache.buildExtents(selectedComp);
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

  Widget _buildItem(
    DAUCompsViewModel daucompsViewmodelConsumer,
    int roundIndex,
    int itemIndex,
  ) {
    final dauRound =
        daucompsViewmodelConsumer.selectedDAUComp!.daurounds[roundIndex];

    if (itemIndex == 0 || itemIndex == 2) {
      final league = itemIndex == 0 ? League.nrl : League.afl;
      return roundLeagueHeaderListTile(
        league,
        50,
        50,
        dauRound,
        daucompsViewmodelConsumer,
        di<TippersViewModel>().selectedTipper,
        false,
      );
    } else if (itemIndex == 1 || itemIndex == 3) {
      final league = itemIndex == 1 ? League.nrl : League.afl;
      return GameListBuilder(
        currentTipper: di<TippersViewModel>().selectedTipper,
        roundIndex: roundIndex,
        league: league,
        tipperTipsViewModel:
            daucompsViewmodelConsumer.selectedTipperTipsViewModel,
        dauCompsViewModel: daucompsViewmodelConsumer,
        isPercentStatsPage: false,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    daucompsViewModel.removeListener(_onDAUCompsChanged);
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

class EndFooter extends StatelessWidget {
  const EndFooter({super.key});

  static const double height = 75;

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

  static const double height = 200;

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
