/* import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gsheets/gsheets.dart';
import 'package:mockito/annotations.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}

@GenerateMocks([GSheets, DotEnv])
void main() {
  group('submitDefaultTips', () {
    test('throws an exception if the tipper cannot be found', () async {
      final service = LegacyTippingService();
      final gamesViewModel = MockGamesViewModel();

      when(gamesViewModel.getCombinedRoundNumbers())
          .thenAnswer((_) async => [1, 2, 3]);
      when(gamesViewModel.getCurrentCombinedRoundNumber())
          .thenAnswer((_) async => 1);

      expect(
        () => service.submitDefaultTips("dd", gamesViewModel),
        throwsA(isA<Exception>()),
      );
    });

    test('submits default tips for a known tipper', () async {
      final service = LegacyTippingService();
      final gamesViewModel = MockGamesViewModel();

      when(gamesViewModel.getCombinedRoundNumbers())
          .thenAnswer((_) async => [1, 2, 3]);
      when(gamesViewModel.getCurrentCombinedRoundNumber())
          .thenAnswer((_) async => 1);
      when(gamesViewModel.getDefaultTipsForCombinedRoundNumber(1))
          .thenAnswer((_) async => 'default tip');

      await service.submitDefaultTips('known tipper', gamesViewModel);

      verify(gamesViewModel.getDefaultTipsForCombinedRoundNumber(1)).called(3);
    });
  });
}
 */