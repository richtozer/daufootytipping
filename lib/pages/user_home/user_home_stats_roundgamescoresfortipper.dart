import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
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
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundGameScoresForTipper extends StatefulWidget {
  const StatRoundGameScoresForTipper(
    this.statsTipper,
    this.roundNumberToDisplay, {
    super.key,
    this.createTipsViewModel,
  });

  /// The page owns and disposes the returned model; defaults to Firebase-backed tips.
  final TipsViewModel Function(DAUComp comp, Tipper tipper)?
  createTipsViewModel;
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

  static const columns = [
    AppColumn.text('Teams / Scores'),
    AppColumn.text('Result'),
    AppColumn.text('Tip'),
    AppColumn.numeric('Points'),
    AppColumn.numeric('Max Points'),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    final values = <Object?>[
      titleStyle,
      for (final league in [League.nrl, League.afl])
        for (final game in games[league] ?? <Game>[]) ...[
          game.dbkey,
          league,
          game.homeTeam.name,
          game.awayTeam.name,
          game.scoring?.homeTeamScore,
          game.scoring?.awayTeamScore,
          game.scoring?.getGameResultCalculated(league),
          _tipsByGameKey[game.dbkey]?.tip,
          _tipsByGameKey[game.dbkey]?.getTipPointsCalculated(),
          _tipsByGameKey[game.dbkey]?.getMaxPointsCalculated(),
        ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    _rows = [
      for (final league in [League.nrl, League.afl]) ...[
        AppRow(
          key: ValueKey(league),
          cells: [
            AppCell.text(
              league.name.toUpperCase(),
              style: titleStyle,
              leading: SvgPicture.asset(league.logo, width: 20, height: 20),
              leadingSize: const Size(20, 20),
            ),
            for (var i = 1; i < columns.length; i++) const AppCell.text(''),
          ],
        ),
        for (final game in games[league] ?? <Game>[]) _gameRow(game),
      ],
    ];
    return _rows;
  }

  AppRow _gameRow(Game game) {
    final tip = _tipsByGameKey[game.dbkey];
    final result = game.scoring?.getGameResultCalculated(game.league);
    // The league's own wording only; the enum name it came from added a
    // parenthesised letter that said the same thing twice.
    String label(GameResult value) =>
        game.league == League.afl ? value.afl : value.nrl;
    return AppRow(
      key: ValueKey(game.dbkey),
      cells: [
        AppCell.text(
          '${game.homeTeam.name} v ${game.awayTeam.name}\n'
          '${game.scoring?.homeTeamScore ?? ''} - ${game.scoring?.awayTeamScore ?? ''}',
          maxLines: 2,
        ),
        AppCell.text(result == null ? '-' : label(result)),
        AppCell.text(tip == null ? 'loading..' : label(tip.tip)),
        AppCell.text(tip?.getTipPointsCalculated().toString() ?? 'loading..'),
        AppCell.text(tip?.getMaxPointsCalculated().toString() ?? 'loading..'),
      ],
    );
  }

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

    allTipsViewModel =
        widget.createTipsViewModel?.call(selectedComp, widget.statsTipper) ??
        TipsViewModel.forTipper(
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

    final groupedGames = dauCompsViewModel.groupGamesIntoLeagues(
      roundToDisplay,
    );
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
    return SelectedCompBanner(
      child: buildScaffold(
        context,
        games[League.afl],
        games[League.nrl],
        MediaQuery.of(context).size.width > 500,
      ),
    );
  }

  Scaffold buildScaffold(
    BuildContext context,
    List<Game>? aflGames,
    List<Game>? nrlGames,
    bool isLargeScreen,
  ) {
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final fabBackgroundColor = isDarkMode
        ? const Color(0xFF4E7A36)
        : Colors.lightGreen[200];
    final fabForegroundColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: fabBackgroundColor,
        foregroundColor: fabForegroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: SafeArea(
        child: AppTableFrame(
          columns: columns,
          rows: _tableRows(context),
          frozenLeading: 1,
          banner: LiveScoresWarningCard(),
          heading: AppTableHeading(
            leading: avatarPic(widget.statsTipper, widget.roundNumberToDisplay),
            title: 'Round ${widget.roundNumberToDisplay} Games',
            subtitle: widget.statsTipper.name,
          ),
          table: Padding(
            padding: const EdgeInsets.all(5.0),
            child: AppTable(
              columns: columns,
              rows: _tableRows(context),
              frozenLeading: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget avatarPic(Tipper tipper, int round) {
    return Hero(
      tag: '$round-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds

      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 30,
      ),
    );
  }
}
