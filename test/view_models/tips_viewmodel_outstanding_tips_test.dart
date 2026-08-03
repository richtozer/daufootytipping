import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

void main() {
  group('TipsViewModel upcoming outstanding tips', () {
    late MockGamesViewModel gamesViewModel;
    TipsViewModel? tipsViewModel;
    late DAURound round;

    setUp(() {
      gamesViewModel = MockGamesViewModel();
      when(() => gamesViewModel.addListener(any())).thenReturn(null);
      when(() => gamesViewModel.removeListener(any())).thenReturn(null);

      final now = DateTime.now().toUtc();
      round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 1)),
        lastGameKickOffUTC: now.add(const Duration(days: 2)),
      );
      round.games = <Game>[
        _game('started', now.subtract(const Duration(hours: 1))),
        _game('upcoming', now.add(const Duration(days: 1))),
      ];
      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: <DAURound>[round],
      );

      tipsViewModel = TipsViewModel(
        MockTippersViewModel(),
        comp,
        gamesViewModel,
        database: MockDatabaseReference(),
        listenToTips: false,
      );
    });

    tearDown(() {
      tipsViewModel?.dispose();
    });

    test('stops counting an untipped game once it has started', () {
      expect(round.getGamesForLeague(League.nrl), hasLength(2));
      expect(
        tipsViewModel!
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          round,
          League.nrl,
        ),
        1,
      );
    });
  });
}

Game _game(String dbkey, DateTime startTimeUTC) {
  return Game(
    dbkey: dbkey,
    league: League.nrl,
    homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
    awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
    location: 'Stadium',
    startTimeUTC: startTimeUTC,
    fixtureRoundNumber: 1,
    fixtureMatchNumber: 1,
    );
}
