import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundGameScoresForTipper extends StatefulWidget {
  const StatRoundGameScoresForTipper(
      this.statsTipper, this.roundNumberToDisplay,
      {super.key});

  final Tipper statsTipper;
  final int roundNumberToDisplay;

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

    DAURound roundToDisplay = dauCompsViewModel
        .selectedDAUComp!.daurounds[widget.roundNumberToDisplay - 1];

    gamesFuture = dauCompsViewModel.sortGamesIntoLeagues(roundToDisplay);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<League, List<Game>>>(
      future: gamesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (!snapshot.hasData) {
            return const Text('No data');
          }
          var games = snapshot.data;
          //filter out games that have not started - we do not want to expose tips to other tippers until tipping is closed
          games!.forEach((league, gameList) {
            gameList.retainWhere((game) =>
                game.gameState == GameState.startedResultNotKnown ||
                game.gameState == GameState.startedResultKnown);
          });

          List<Game>? nrlGames = games[League.nrl];
          List<Game>? aflGames = games[League.afl];

          return buildScaffold(context, aflGames, nrlGames,
              MediaQuery.of(context).size.width > 500);
        } else {
          return CircularProgressIndicator(color: League.afl.colour);
        }
      },
    );
  }

  Scaffold buildScaffold(BuildContext context, List<Game>? aflGames,
      List<Game>? nrlGames, bool isLargeScreen) {
    Orientation orientation = MediaQuery.of(context).orientation;

    TipsViewModel allTips = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        di<DAUCompsViewModel>().selectedDAUComp!,
        di<DAUCompsViewModel>().gamesViewModel!,
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
                        'Round ${widget.roundNumberToDisplay} games\n${widget.statsTipper.name}',
                    leadingIconAvatar: avatarPic(
                        widget.statsTipper, widget.roundNumberToDisplay))
                : Text(
                    'Round ${widget.roundNumberToDisplay} games${widget.statsTipper.name}\n'),
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
                          // fixedLeftColumns:
                          //     orientation == Orientation.portrait ? 1 : 0,
                          showCheckboxColumn: false,
                          isHorizontalScrollBarVisible: false,
                          isVerticalScrollBarVisible: true,
                          columns: getColumns(columns),
                          rows: [
                            DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      SvgPicture.asset(
                                        League.nrl.logo,
                                        width: 20,
                                        height: 20,
                                      ),
                                      Text(
                                        'NRL',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ],
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
                                  Row(
                                    children: [
                                      SvgPicture.asset(
                                        League.afl.logo,
                                        width: 20,
                                        height: 20,
                                      ),
                                      Text(
                                        'AFL',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ],
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
            const SizedBox(height: 100)
          ],
        ),
      ),
    );
  }

  DataRow buildDataRow(List<Game> games, int index, TipsViewModel allTips) {
    DAURound dauRound = di<DAUCompsViewModel>()
        .selectedDAUComp!
        .daurounds
        .firstWhere(
            (element) => element.dAUroundNumber == widget.roundNumberToDisplay);

    GameTipsViewModel gameTipsViewModel = GameTipsViewModel(
        widget.statsTipper,
        di<DAUCompsViewModel>().selectedDAUComp!.dbkey!,
        games[index],
        allTips,
        dauRound);
    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  '${gameTipsViewModel.game.homeTeam.name} v ${gameTipsViewModel.game.awayTeam.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Center(
                child: Text(
                  '${gameTipsViewModel.game.scoring!.homeTeamScore ?? ''} - ${gameTipsViewModel.game.scoring!.awayTeamScore ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          Text(games[index].league == League.afl
              ? '${gameTipsViewModel.game.scoring!.getGameResultCalculated(games[index].league).afl} (${gameTipsViewModel.game.scoring!.getGameResultCalculated(games[index].league).name})'
              : '${gameTipsViewModel.game.scoring!.getGameResultCalculated(games[index].league).nrl} (${gameTipsViewModel.game.scoring!.getGameResultCalculated(games[index].league).name})'),
        ),
        DataCell(
          FutureBuilder<TipGame?>(
            future: gameTipsViewModel.gettip(),
            builder: (BuildContext context, AsyncSnapshot<TipGame?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('loading..');
              } else {
                return Text(snapshot.data?.game.league == League.afl
                    ? '${snapshot.data?.tip.afl} (${snapshot.data?.tip.name})'
                    : '${snapshot.data?.tip.nrl} (${snapshot.data?.tip.name})');
              }
            },
          ),
        ),
        DataCell(
          FutureBuilder<TipGame?>(
            future: gameTipsViewModel.gettip(),
            builder: (BuildContext context, AsyncSnapshot<TipGame?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('loading..');
              } else {
                return Text(snapshot.data?.getTipScoreCalculated().toString() ??
                    'No data');
              }
            },
          ),
        ),
        DataCell(
          FutureBuilder<TipGame?>(
            future: gameTipsViewModel.gettip(),
            builder: (BuildContext context, AsyncSnapshot<TipGame?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('loading..');
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

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            fixedWidth: column.startsWith('Teams')
                ? 175
                : column.startsWith('Tip')
                    ? 60
                    : 60,
            numeric:
                column.startsWith('Max') || column == 'Score' ? true : false,
            label: Text(
              column,
            ),
          ))
      .toList();

  Widget avatarPic(Tipper tipper, int round) {
    return Hero(
        tag:
            '$round-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds

        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 30));
  }
}
