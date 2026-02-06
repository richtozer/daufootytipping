import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}

void main() {
  group('DAUCompsViewModel round state via linkGamesWithRounds', () {
    late DAUCompsViewModel vm;
    late MockGamesViewModel mockGamesVM;
    late Team home;
    late Team away;

    setUp(() {
      vm = DAUCompsViewModel(null, false, skipInit: true);
      mockGamesVM = MockGamesViewModel();
      vm.gamesViewModel = mockGamesVM;
      vm.completeOtherViewModelsForTest();
      home = Team(dbkey: 'nrl-h', name: 'H', league: League.nrl);
      away = Team(dbkey: 'nrl-a', name: 'A', league: League.nrl);
      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: <DAURound>[],
      );
      vm.setSelectedCompForTest(comp);
    });

    Game g(DateTime start, {Scoring? scoring}) => Game(
          dbkey: 'nrl-01-001',
          league: League.nrl,
          homeTeam: home,
          awayTeam: away,
          location: 'X',
          startTimeUTC: start.toUtc(),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
          scoring: scoring,
        );

    test('allGamesEnded when all games have official scores and >2h past', () async {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        lastGameKickOffUTC: DateTime.now().toUtc().subtract(const Duration(hours: 10)),
      );
      // getGamesForRound returns one finished game
      when(() => mockGamesVM.getGames()).thenAnswer((_) async => <Game>[]);
      when(() => mockGamesVM.getGamesForRound(round)).thenAnswer((_) async => [
            g(DateTime.now().toUtc().subtract(const Duration(hours: 5)),
                scoring: Scoring(homeTeamScore: 12, awayTeamScore: 3))
          ]);

      await vm.linkGamesWithRounds([round]);
      expect(round.roundState, RoundState.allGamesEnded);
    });

    test('started when any game started but no official result', () async {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        lastGameKickOffUTC: DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      when(() => mockGamesVM.getGames()).thenAnswer((_) async => <Game>[]);
      // game started 1 hour ago, no official scores
      when(() => mockGamesVM.getGamesForRound(round)).thenAnswer((_) async => [
            g(DateTime.now().toUtc().subtract(const Duration(hours: 1)))
          ]);

      await vm.linkGamesWithRounds([round]);
      expect(round.roundState, RoundState.started);
    });

    test('noGames when round has no games', () async {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.now().toUtc().add(const Duration(days: 3)),
        lastGameKickOffUTC: DateTime.now().toUtc().add(const Duration(days: 4)),
      );
      when(() => mockGamesVM.getGames()).thenAnswer((_) async => <Game>[]);
      when(() => mockGamesVM.getGamesForRound(round)).thenAnswer((_) async => <Game>[]);

      await vm.linkGamesWithRounds([round]);
      expect(round.roundState, RoundState.noGames);
    });
  });
}

