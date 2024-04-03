import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundGameScoresForTipper extends StatefulWidget {
  const StatRoundGameScoresForTipper(this.statsTipper, this.roundToDisplay,
      {super.key});

  final Tipper statsTipper;
  final int roundToDisplay;

  @override
  State<StatRoundGameScoresForTipper> createState() =>
      _StatRoundGameScoresForTipperState();
}

class _StatRoundGameScoresForTipperState
    extends State<StatRoundGameScoresForTipper> {
  late DAUCompsViewModel dauCompsViewModel;
  late Future<Map<League, List<Game>>> gamesFuture;
  bool isAscending = true;
  int? sortColumnIndex = 1;
  int initialRound = 1;

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

    gamesFuture =
        dauCompsViewModel.getGamesForCombinedRoundNumber(widget.roundToDisplay);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<League, List<Game>>>(
      future: gamesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else if (!snapshot.hasData) {
            return const Text('No data');
          }
          var games = snapshot.data;
          //filter out games that have not started - we do not want to expose tips to other tippers until tipping is closed
          games!.forEach((league, gameList) {
            gameList.retainWhere((game) =>
                game.gameState == GameState.resultNotKnown ||
                game.gameState == GameState.resultKnown);
          });

          List<Game>? nrlGames = games[League.nrl];
          List<Game>? aflGames = games[League.afl];

          return buildScaffold(context, aflGames, nrlGames,
              MediaQuery.of(context).size.width > 500);
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }

  Scaffold buildScaffold(BuildContext context, List<Game>? aflGames,
      List<Game>? nrlGames, bool isLargeScreen) {
    Orientation orientation = MediaQuery.of(context).orientation;

    AllTipsViewModel allTips = AllTipsViewModel.forTipper(
        di<TippersViewModel>(),
        di<DAUCompsViewModel>().selectedDAUCompDbKey,
        di<GamesViewModel>(),
        widget.statsTipper);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'roundscoresfortipper',
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            orientation == Orientation.portrait
                ? HeaderWidget(
                    text:
                        '${widget.statsTipper.name} - Round ${widget.roundToDisplay} games',
                    leadingIconAvatar: avatarPic(widget.statsTipper))
                : Text(
                    '${widget.statsTipper.name} Round ${widget.roundToDisplay} games'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: ChangeNotifierProvider<DAUCompsViewModel>.value(
                  value: dauCompsViewModel,
                  builder: (context, snapshot) {
                    return Consumer<DAUCompsViewModel>(
                        builder: (context, dauCompsViewModelConsumer, child) {
                      return DataTable2(
                          border: TableBorder.all(
                            width: 1.0,
                            color: Colors.grey.shade300,
                          ),
                          //sortColumnIndex: sortColumnIndex,
                          //sortAscending: isAscending,
                          columnSpacing: 0,
                          horizontalMargin: 0,
                          minWidth: 800,
                          fixedTopRows: 1,
                          fixedLeftColumns:
                              orientation == Orientation.portrait ? 1 : 0,
                          showCheckboxColumn: false,
                          isHorizontalScrollBarVisible: true,
                          isVerticalScrollBarVisible: true,
                          columns: getColumns(columns),
                          // rows: List<DataRow>.generate(aflGames!.length, (index) {
                          //   return buildDataRow(aflGames, index, allTips);
                          // for the rows output a header row 'NRL' and then the games
                          // followed by a header row 'AFL' and then the games
                          rows: [
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    'NRL',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            ...List<DataRow>.generate(nrlGames!.length,
                                (index) {
                              return buildDataRow(nrlGames, index, allTips);
                            }),
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    'AFL',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            ...List<DataRow>.generate(aflGames!.length,
                                (index) {
                              return buildDataRow(aflGames, index, allTips);
                            }),
                          ]);
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow buildDataRow(List<Game> games, int index, AllTipsViewModel allTips) {
    GameTipsViewModel gameTipsViewModel = GameTipsViewModel(widget.statsTipper,
        di<DAUCompsViewModel>().selectedDAUCompDbKey, games[index], allTips);
    return DataRow(
      cells: [
        DataCell(
          Flexible(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    //overflow: TextOverflow.ellipsis,
                    '${gameTipsViewModel.game.homeTeam.name} v ${gameTipsViewModel.game.awayTeam.name}',
                  ),
                  Text(
                    //overflow: TextOverflow.ellipsis,
                    '${gameTipsViewModel.game.scoring!.homeTeamScore ?? ''} - ${gameTipsViewModel.game.scoring!.awayTeamScore ?? ''}',
                  ),
                ],
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            games[index].league == League.afl
                ? gameTipsViewModel.game.scoring!
                    .getGameResultCalculated(games[index].league)
                    .afl
                : gameTipsViewModel.game.scoring!
                    .getGameResultCalculated(games[index].league)
                    .nrl,
          ),
        ),
        DataCell(
          FutureBuilder<TipGame?>(
            future: gameTipsViewModel
                .gettip(), // Replace with your method that returns Future<TipGame>
            builder: (BuildContext context, AsyncSnapshot<TipGame?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('loading..');
              } else if (snapshot.hasError) {
                return Flexible(child: Text('Error: ${snapshot.error}'));
              } else {
                return Text(snapshot.data?.game.league == League.afl
                    ? snapshot.data?.tip.afl ?? 'No data'
                    : snapshot.data?.tip.nrl ?? 'No data');
              }
            },
          ),
        ),
        DataCell(
          FutureBuilder<TipGame?>(
            future: gameTipsViewModel
                .gettip(), // Replace with your method that returns Future<TipGame>
            builder: (BuildContext context, AsyncSnapshot<TipGame?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('loading..');
              } else if (snapshot.hasError) {
                return Flexible(child: Text('Error: ${snapshot.error}'));
              } else {
                return Text(snapshot.data?.getTipScoreCalculated().toString() ??
                    'No data');
              }
            },
          ),
        ),
        DataCell(
          FutureBuilder<TipGame?>(
            future: gameTipsViewModel
                .gettip(), // Replace with your method that returns Future<TipGame>
            builder: (BuildContext context, AsyncSnapshot<TipGame?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('loading..');
              } else if (snapshot.hasError) {
                return Flexible(child: Text('Error: ${snapshot.error}'));
              } else {
                return Text(snapshot.data?.getMaxScoreCalculated().toString() ??
                    'No data');
              }
            },
          ),
        ),
      ],
    );
  }

  void onSort(int columnIndex, bool ascending) {
    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            fixedWidth: column.startsWith('Teams') ? 175 : 60,
            numeric: column.startsWith('Teams') ||
                    column == 'Result' ||
                    column == 'Tip'
                ? false
                : true,
            label: Text(
              column,
            ),
            onSort: onSort,
          ))
      .toList();

  Widget avatarPic(Tipper tipper) {
    return Hero(
        tag: tipper.dbkey!,
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 30));
  }
}
