import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/repositories/daucomps_repository.dart';
import 'package:daufootytipping/services/url_health_checker.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';

class _FakeDauCompsRepository implements DauCompsRepository {
  Map<String, dynamic>? capturedUpdates;

  @override
  Stream<DatabaseEvent> streamDauComps(String daucompsPath) =>
      const Stream.empty();

  @override
  Future<void> update(Map<String, dynamic> updates) async {
    capturedUpdates = updates;
  }

  @override
  Future<String> newCompKey(String daucompsPath) async =>
      throw UnimplementedError('not exercised when saving an existing comp');
}

void main() {
  group('DAUCompsViewModel.processAndSaveDauComp', () {
    test('editing only the end date on an existing comp skips the URL health '
        'check, saves successfully, and persists the new dates', () async {
      final repo = _FakeDauCompsRepository();
      final vm = DAUCompsViewModel(
        null,
        true,
        skipInit: true,
        repo: repo,
        urlHealthChecker: UrlHealthChecker(
          remoteChecker: (_) async {
            fail(
              'URL health check should be skipped when the fixture URLs '
              'are unchanged from the saved comp',
            );
          },
        ),
      );
      vm.completeInitialDAUCompLoadForTest();

      final existingComp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Test Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        daurounds: const [],
      );

      final result = await vm.processAndSaveDauComp(
        name: existingComp.name,
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: '2026-08-31',
        aflRegularCompEndDateString: '2026-09-01',
        existingComp: existingComp,
        currentRounds: const [],
      );

      expect(result['success'], isTrue);
      expect(result['message'], 'DAUComp record saved');

      final updates = repo.capturedUpdates;
      expect(updates, isNotNull);
      expect(
        updates!['/AllDAUComps/comp-2026/nrlRegularCompEndDateUTC'],
        DateTime.parse('2026-08-31').toIso8601String(),
      );
      expect(
        updates['/AllDAUComps/comp-2026/aflRegularCompEndDateUTC'],
        DateTime.parse('2026-09-01').toIso8601String(),
      );
    });
  });
}
