import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:intl/intl.dart';

/// Separator between the parts of the info panel paragraph.
const String _infoSeparator = ' 🏉 ';

/// Prefix for the team logo Hero tags shared with the league ladder page.
const String _heroTagPrefix = 'team_icon_';

/// The Hero tag for a team's logo on a tips card.
///
/// Scoped to the game, not just the team: a team plays every round and the
/// list holds a card for each, so tagging by team alone put the same tag on
/// every one of them. Two mounted at once -- adjacent rounds, or the sliver
/// cache holding a neighbour alive -- and pushing any route threw.
String tipsCardHeroTag({
  required String gameDbKey,
  required String teamDbKey,
}) => '$_heroTagPrefix${gameDbKey}_$teamDbKey';

/// The Hero tag for a team's logo where a screen shows it once: the league
/// ladder's rows and the team history page it opens.
String teamHeroTag(String teamDbKey) => '$_heroTagPrefix$teamDbKey';

/// Reads live tipping state and returns the presentation values the adaptive
/// card renders. Saving, permissions, navigation, ladder lookups and Firebase
/// subscriptions stay with the caller; this function only reads.
TipsCardDisplay tipsCardDisplayFor({
  required GameTipViewModel gameTipViewModel,
  String homeRank = '',
  String awayRank = '',
  GameStatsEntry? gameStatsEntry,
  bool percentStatsLoading = false,
  bool canTip = true,
}) {
  final Game game = gameTipViewModel.game;
  final Scoring? scoring = game.scoring;
  final TipsStatus status = _statusFor(game, scoring);
  final bool showRanks =
      status == TipsStatus.upcoming || status == TipsStatus.today;

  return TipsCardDisplay(
    id: game.dbkey,
    home: _team(
      gameDbKey: game.dbkey,
      team: game.homeTeam,
      score: _scoreFor(scoring, ScoringTeam.home, status),
      rank: showRanks ? homeRank : '',
      winner: _hasFinalScore(scoring) && (scoring?.didHomeTeamWin() ?? false),
    ),
    away: _team(
      gameDbKey: game.dbkey,
      team: game.awayTeam,
      score: _scoreFor(scoring, ScoringTeam.away, status),
      rank: showRanks ? awayRank : '',
      winner: _hasFinalScore(scoring) && (scoring?.didAwayTeamWin() ?? false),
    ),
    league: game.league,
    info: _infoParagraph(gameTipViewModel),
    status: status,
    selected: gameTipViewModel.tip?.tip,
    result: _hasGameResult(game)
        ? scoring?.getGameResultCalculated(game.league)
        : null,
    points: _pointsText(gameTipViewModel),
    average: _averageText(gameTipViewModel, gameStatsEntry),
    percentages: _percentages(gameStatsEntry),
    loading: percentStatsLoading,
    saving: gameTipViewModel.savingTip,
    canTip: canTip,
  );
}

TipsTeamDisplay _team({
  required String gameDbKey,
  required Team team,
  required int? score,
  required String rank,
  required bool winner,
}) {
  return TipsTeamDisplay(
    team.name,
    team.logoURI ??
        (team.league == League.nrl ? League.nrl.logo : League.afl.logo),
    score: score,
    rank: rank.isEmpty ? null : rank,
    winner: winner,
    heroTag: tipsCardHeroTag(gameDbKey: gameDbKey, teamDbKey: team.dbkey),
  );
}

/// The interim state wins over the game state: a crowd-sourced score without a
/// final fixture score is what the card marks as provisional.
TipsStatus _statusFor(Game game, Scoring? scoring) {
  final bool hasCrowdSourcedScore =
      scoring?.crowdSourcedScores?.isNotEmpty ?? false;
  if (hasCrowdSourcedScore && !_hasFinalScore(scoring)) {
    return TipsStatus.interim;
  }
  return switch (game.gameState) {
    GameState.notStarted => TipsStatus.upcoming,
    GameState.startingSoon => TipsStatus.today,
    GameState.startedResultNotKnown => TipsStatus.live,
    GameState.startedResultKnown => TipsStatus.finalScore,
  };
}

bool _hasFinalScore(Scoring? scoring) =>
    scoring?.homeTeamScore != null && scoring?.awayTeamScore != null;

bool _hasGameResult(Game game) =>
    game.scoring != null && game.gameState == GameState.startedResultKnown;

int? _scoreFor(Scoring? scoring, ScoringTeam team, TipsStatus status) {
  if (scoring == null ||
      status == TipsStatus.upcoming ||
      status == TipsStatus.today) {
    return null;
  }
  return scoring.currentScore(team);
}

String _pointsText(GameTipViewModel gameTipViewModel) {
  final tip = gameTipViewModel.tip;
  if (tip == null || !_hasGameResult(gameTipViewModel.game)) {
    return '? / ?';
  }
  return '${tip.getTipPointsCalculated()} / ${tip.getMaxPointsCalculated()}';
}

String _averageText(
  GameTipViewModel gameTipViewModel,
  GameStatsEntry? gameStatsEntry,
) {
  final tip = gameTipViewModel.tip;
  if (tip == null || !_hasGameResult(gameTipViewModel.game)) {
    return '? / ?';
  }
  final maxPoints = tip.getMaxPointsCalculated();
  final averagePoints = gameStatsEntry?.averagePoints;
  if (averagePoints == null) {
    return '? / $maxPoints';
  }
  return '${averagePoints.toStringAsPrecision(2)} / $maxPoints';
}

/// Percentages in choice order, scaled from the stored fractions to the whole
/// numbers the card renders, or null while any of them is still missing so the
/// card shows its loading footprint rather than a partial row.
List<double>? _percentages(GameStatsEntry? gameStatsEntry) {
  if (gameStatsEntry == null) {
    return null;
  }
  final values = <double?>[
    gameStatsEntry.percentageTippedHomeMargin,
    gameStatsEntry.percentageTippedHome,
    gameStatsEntry.percentageTippedDraw,
    gameStatsEntry.percentageTippedAway,
    gameStatsEntry.percentageTippedAwayMargin,
  ];
  if (values.any((value) => value == null)) {
    return null;
  }
  return [for (final value in values) value! * 100];
}

String _infoParagraph(GameTipViewModel gameTipViewModel) {
  final Game game = gameTipViewModel.game;
  final tip = gameTipViewModel.tip;

  String tipText = '';
  if (tip != null) {
    tipText = tip.isDefaultTip()
        ? 'Default tip of [Away] given'
        : 'Tipped: ${DateFormat('EEE dd MMM hh:mm a').format(tip.submittedTimeUTC.toLocal())}';
  }

  final bool started =
      game.gameState != GameState.notStarted &&
      game.gameState != GameState.startingSoon;
  final kickoffText = started
      ? 'Played: ${DateFormat('EEE d MMM').format(game.startTimeUTC.toLocal())}'
      : 'Kickoff: ${DateFormat('EEE dd MMM hh:mm').format(game.startTimeUTC.toLocal())}';

  return [
    if (tipText.isNotEmpty) tipText,
    kickoffText,
    game.location,
    'Fixture: round ${game.fixtureRoundNumber}, match ${game.fixtureMatchNumber}',
  ].join(_infoSeparator);
}

/// Widest values each field can hold, so the measured row height depends on the
/// competition and the text scale alone. Measuring the live cards instead would
/// resize every row as scores arrive during a round.
const int _widestScore = 888;
const String _widestRank = '88th';
const String _widestDates =
    'Tipped: Wed 28 Sep 08:88 pm${_infoSeparator}Kickoff: Wed 28 Sep 08:88';
const String _widestFixture = 'Fixture: round 88, match 88';

/// Bounded worst-case cards used to size every row in the list. Covers both
/// leagues (their choice labels differ) and the three matchup arrangements:
/// ranks before kickoff, scores after it, and the edit pen while live.
List<TipsCardDisplay> tipsMeasurementCards(Iterable<DAURound> daurounds) {
  final widestName = <League, String>{};
  var widestLocation = '';
  for (final dauRound in daurounds) {
    for (final game in dauRound.games) {
      if (game.location.length > widestLocation.length) {
        widestLocation = game.location;
      }
      for (final team in [game.homeTeam, game.awayTeam]) {
        final current = widestName[team.league];
        if (current == null || team.name.length > current.length) {
          widestName[team.league] = team.name;
        }
      }
    }
  }

  final info = [
    _widestDates,
    widestLocation,
    _widestFixture,
  ].where((part) => part.isNotEmpty).join(_infoSeparator);

  return [
    for (final league in const [League.nrl, League.afl])
      for (final status in const [
        TipsStatus.upcoming,
        TipsStatus.finalScore,
        TipsStatus.live,
      ])
        _measurementCard(
          league: league,
          teamName: widestName[league] ?? '',
          info: info,
          status: status,
        ),
  ];
}

TipsCardDisplay _measurementCard({
  required League league,
  required String teamName,
  required String info,
  required TipsStatus status,
}) {
  final bool beforeKickoff = status == TipsStatus.upcoming;
  TipsTeamDisplay team() => TipsTeamDisplay(
    teamName,
    league.logo,
    score: beforeKickoff ? null : _widestScore,
    rank: beforeKickoff ? _widestRank : null,
  );

  return TipsCardDisplay(
    id: 'measurement-${league.name}-${status.name}',
    home: team(),
    away: team(),
    league: league,
    info: info,
    status: status,
    selected: GameResult.a,
    result: GameResult.a,
    points: '8 / 8',
    average: '8.8 / 8',
    percentages: const [100.0, 100.0, 100.0, 100.0, 100.0],
  );
}
