import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundGameScoresForTipper extends StatefulWidget {
  const StatRoundGameScoresForTipper(
    this.statsTipper,
    this.roundNumberToDisplay, {
    super.key,
  });

  final Tipper statsTipper;
  final int roundNumberToDisplay;

  @override
  State<StatRoundGameScoresForTipper> createState() =>
      _StatRoundGameScoresForTipperState();
}

class _StatRoundGameScoresForTipperState
    extends State<StatRoundGameScoresForTipper> {
  late DAUCompsViewModel dauCompsViewModel;
  TipsViewModel? allTipsViewModel;
  String? _allTipsViewModelCompDbKey;
  Map<League, List<Game>> games = {
    League.nrl: const <Game>[],
    League.afl: const <Game>[],
  };
  final Map<String, Tip?> _tipsByGameKey = {};
  late DAURound roundToDisplay;

  final List<String> columns = [
    'Teams/\nScores',
    'Result',
    'Tip',
    'Score',
    'Max\nScore',
  ];

  @override
  void initState() {
    super.initState();
    dauCompsViewModel = di<DAUCompsViewModel>();
    dauCompsViewModel.addListener(_refreshTableData);
    _refreshTableData();
  }

  @override
  void dispose() {
    dauCompsViewModel.removeListener(_refreshTableData);
    allTipsViewModel?.removeListener(_refreshTableData);
    allTipsViewModel?.dispose();
    super.dispose();
  }

  void _ensureTipsViewModelForComp(DAUComp selectedComp) {
    if (_allTipsViewModelCompDbKey == selectedComp.dbkey &&
        allTipsViewModel != null) {
      return;
    }

    allTipsViewModel?.removeListener(_refreshTableData);
    allTipsViewModel?.dispose();

    allTipsViewModel = TipsViewModel.forTipper(
      di<TippersViewModel>(),
      selectedComp,
      dauCompsViewModel.gamesViewModel!,
      widget.statsTipper,
    );
    _allTipsViewModelCompDbKey = selectedComp.dbkey;
    allTipsViewModel!.addListener(_refreshTableData);
  }

  Future<void> _refreshTableData() async {
    final selectedComp = dauCompsViewModel.selectedDAUComp;
    final gamesViewModel = dauCompsViewModel.gamesViewModel;
    if (!mounted || selectedComp == null || gamesViewModel == null) {
      return;
    }

    _ensureTipsViewModelForComp(selectedComp);
    final localTipsViewModel = allTipsViewModel;
    if (localTipsViewModel == null) {
      return;
    }

    roundToDisplay = selectedComp.daurounds[widget.roundNumberToDisplay - 1];

    final groupedGames = dauCompsViewModel.groupGamesIntoLeagues(roundToDisplay);
    final filteredGames = <League, List<Game>>{
      League.nrl: List<Game>.from(groupedGames[League.nrl] ?? const <Game>[]),
      League.afl: List<Game>.from(groupedGames[League.afl] ?? const <Game>[]),
    };

    filteredGames.forEach((league, gameList) {
      gameList.retainWhere(
        (game) =>
            game.gameState == GameState.startedResultNotKnown ||
            game.gameState == GameState.startedResultKnown,
      );
    });

    await localTipsViewModel.initialLoadCompleted;
    if (!mounted ||
        selectedComp.dbkey != dauCompsViewModel.selectedDAUComp?.dbkey ||
        localTipsViewModel != allTipsViewModel) {
      return;
    }

    final tipsByGameKey = <String, Tip?>{};
    for (final leagueGames in filteredGames.values) {
      for (final game in leagueGames) {
        tipsByGameKey[game.dbkey] = await localTipsViewModel.findTip(
          game,
          widget.statsTipper,
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      games = filteredGames;
      _tipsByGameKey
        ..clear()
        ..addAll(tipsByGameKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildScaffold(
      context,
      games[League.afl],
      games[League.nrl],
      MediaQuery.of(context).size.width > 500,
    );
  }

  Scaffold buildScaffold(
    BuildContext context,
    List<Game>? aflGames,
    List<Game>? nrlGames,
    bool isLargeScreen,
  ) {
    Orientation orientation = MediaQuery.of(context).orientation;
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final fabBackgroundColor = isDarkMode
        ? const Color(0xFF4E7A36)
        : Colors.lightGreen[200];
    final fabForegroundColor =
        isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: fabBackgroundColor,
        foregroundColor: fabForegroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (orientation == Orientation.portrait)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      avatarPic(
                        widget.statsTipper,
                        widget.roundNumberToDisplay,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Round ${widget.roundNumberToDisplay} Games',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                widget.statsTipper.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            LiveScoresWarningCard(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: DataTable2(
                  border: TableBorder.all(
                    width: 1.0,
                    color: Colors.grey.shade300,
                  ),
                  columnSpacing: 0,
                  horizontalMargin: 0,
                  minWidth: 800,
                  fixedTopRows: 1,
                  showCheckboxColumn: false,
                  isHorizontalScrollBarVisible: false,
                  isVerticalScrollBarVisible: true,
                  columns: getColumns(columns),
                  rows: [
                    _buildLeagueHeaderRow(context, League.nrl),
                    ...List<DataRow>.generate(nrlGames?.length ?? 0, (index) {
                      return buildDataRow(nrlGames!, index);
                    }),
                    _buildLeagueHeaderRow(context, League.afl),
                    ...List<DataRow>.generate(aflGames?.length ?? 0, (index) {
                      return buildDataRow(aflGames!, index);
                    }),
                  ],
                ),
              ),
            ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildLeagueHeaderRow(BuildContext context, League league) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              SvgPicture.asset(league.logo, width: 20, height: 20),
              Text(league.name.toUpperCase(), style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        ...List<DataCell>.generate(
          columns.length - 1,
          (_) => DataCell(Text('', style: Theme.of(context).textTheme.titleLarge)),
        ),
      ],
    );
  }

  DataRow buildDataRow(List<Game> games, int index) {
    final game = games[index];
    final tip = _tipsByGameKey[game.dbkey];
    final gameResult = game.scoring!.getGameResultCalculated(game.league);
    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  '${game.homeTeam.name} v ${game.awayTeam.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Center(
                child: Text(
                  '${game.scoring!.homeTeamScore ?? ''} - ${game.scoring!.awayTeamScore ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            game.league == League.afl
                ? '${gameResult.afl} (${gameResult.name})'
                : '${gameResult.nrl} (${gameResult.name})',
          ),
        ),
        DataCell(
          Text(
            tip == null
                ? 'loading..'
                : game.league == League.afl
                ? '${tip.tip.afl} (${tip.tip.name})'
                : '${tip.tip.nrl} (${tip.tip.name})',
          ),
        ),
        DataCell(
          Text(tip?.getTipScoreCalculated().toString() ?? 'loading..'),
        ),
        DataCell(
          Text(tip?.getMaxScoreCalculated().toString() ?? 'loading..'),
        ),
      ],
    );
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map(
        (String column) => DataColumn2(
          fixedWidth: column.startsWith('Teams')
              ? 175
              : column.startsWith('Tip')
              ? 60
              : 60,
          numeric: column.startsWith('Max') || column == 'Score' ? true : false,
          label: Text(column),
        ),
      )
      .toList();

  Widget avatarPic(Tipper tipper, int round) {
    return Hero(
      tag:
          '$round-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds

      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 30,
      ),
    );
  }
}
