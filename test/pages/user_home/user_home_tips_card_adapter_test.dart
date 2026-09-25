import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _GameModel extends Mock implements GameTipViewModel {}

Game _game({required DateTime startTimeUTC, Scoring? scoring}) => Game(
  dbkey: 'game-1',
  league: League.nrl,
  homeTeam: Team(dbkey: 'home-1', name: 'Dragons', league: League.nrl),
  awayTeam: Team(dbkey: 'away-1', name: 'Eels', league: League.nrl),
  location: 'Test Oval',
  startTimeUTC: startTimeUTC,
  fixtureRoundNumber: 27,
  fixtureMatchNumber: 1,
  scoring: scoring,
);

TipsCardDisplay _display(
  Game game, {
  String homeRank = '',
  String awayRank = '',
  GameStatsEntry? gameStatsEntry,
}) {
  final model = _GameModel();
  when(() => model.game).thenReturn(game);
  when(() => model.tip).thenReturn(null);
  when(() => model.savingTip).thenReturn(false);
  return tipsCardDisplayFor(
    gameTipViewModel: model,
    homeRank: homeRank,
    awayRank: awayRank,
    gameStatsEntry: gameStatsEntry,
  );
}

void main() {
  final future = DateTime.now().toUtc().add(const Duration(days: 7));
  final past = DateTime.now().toUtc().subtract(const Duration(days: 7));

  test('an interim score takes precedence over the live game state', () {
    final scoring = Scoring(
      crowdSourcedScores: [
        CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper-1',
          12,
          false,
        ),
        CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.away,
          'tipper-1',
          6,
          false,
        ),
      ],
    );
    final display = _display(_game(startTimeUTC: past, scoring: scoring));

    expect(display.status, TipsStatus.interim);
    expect(display.home.score, 12);
    expect(display.away.score, 6);
  });

  test('a final fixture score reports finalScore and marks the winner', () {
    final display = _display(
      _game(
        startTimeUTC: past,
        scoring: Scoring(homeTeamScore: 24, awayTeamScore: 12),
      ),
    );

    expect(display.status, TipsStatus.finalScore);
    expect(display.home.winner, isTrue);
    expect(display.away.winner, isFalse);
  });

  test('scores and ranks swap over at kickoff', () {
    final upcoming = _display(
      _game(startTimeUTC: future, scoring: Scoring(homeTeamScore: 24)),
      homeRank: '17th',
      awayRank: '13th',
    );
    expect(upcoming.status, TipsStatus.upcoming);
    expect(upcoming.home.score, isNull, reason: 'no score before kickoff');
    expect(upcoming.home.rank, '17th');
    expect(upcoming.away.rank, '13th');

    final played = _display(
      _game(
        startTimeUTC: past,
        scoring: Scoring(homeTeamScore: 24, awayTeamScore: 12),
      ),
      homeRank: '17th',
      awayRank: '13th',
    );
    expect(played.home.score, 24);
    expect(played.home.rank, isNull, reason: 'ranks are a pre-game hint only');
  });

  test('percentages stay null until every value has arrived', () {
    final partial = GameStatsEntry(
      percentageTippedHomeMargin: 1.8,
      percentageTippedHome: 42.1,
      percentageTippedDraw: 0.0,
    );
    expect(
      _display(_game(startTimeUTC: past), gameStatsEntry: partial).percentages,
      isNull,
    );

    // Stored as fractions; the card renders whole numbers.
    final complete = GameStatsEntry(
      percentageTippedHomeMargin: 0.018,
      percentageTippedHome: 0.421,
      percentageTippedDraw: 0.0,
      percentageTippedAway: 0.544,
      percentageTippedAwayMargin: 0.017,
    );
    expect(
      _display(_game(startTimeUTC: past), gameStatsEntry: complete).percentages,
      [
        closeTo(1.8, 0.001),
        closeTo(42.1, 0.001),
        0.0,
        closeTo(54.4, 0.001),
        closeTo(1.7, 0.001),
      ],
    );
  });

  test('each team carries the ladder page hero tag', () {
    final display = _display(_game(startTimeUTC: future));

    expect(display.home.heroTag, 'team_icon_home-1');
    expect(display.away.heroTag, 'team_icon_away-1');
    expect(display.home.heroTag, isNot(display.away.heroTag));
  });

  test('the info panel keeps the kickoff, venue and fixture parts', () {
    final kickoff = DateTime.utc(2026, 9, 25, 9, 50);
    final upcoming = _display(
      _game(startTimeUTC: kickoff.add(const Duration(days: 365))),
    );

    expect(upcoming.info, contains('Kickoff: '));
    expect(upcoming.info, contains('Test Oval'));
    expect(upcoming.info, contains('Fixture: round 27, match 1'));
    expect(upcoming.info, isNot(contains('Played: ')));
    expect(
      upcoming.info,
      isNot(contains('Tipped: ')),
      reason: 'no tip submitted, so no tipped-at part',
    );

    final played = _display(
      _game(
        startTimeUTC: past,
        scoring: Scoring(homeTeamScore: 24, awayTeamScore: 12),
      ),
    );
    expect(played.info, contains('Played: '));
    expect(played.info, isNot(contains('Kickoff: ')));
  });

  test('points read as unknown until the game has a result', () {
    final display = _display(_game(startTimeUTC: future));

    expect(display.points, '? / ?');
    expect(display.average, '? / ?');
  });
}
