import 'dart:async';

import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseDatabase extends Mock implements FirebaseDatabase {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

void main() {
  group('TippersViewModel.saveBatchOfTipperChangesToDb', () {
    const String rolePath = '/AllTippers/tipper-1/tipperRole';
    late MockFirebaseDatabase database;
    late MockDatabaseReference root;
    late Completer<void> serverAnswer;
    late TippersViewModel viewModel;

    setUp(() {
      database = MockFirebaseDatabase();
      root = MockDatabaseReference();
      when(() => database.ref()).thenReturn(root);
      ConfiguredRealtimeDatabase.configure(database);
      serverAnswer = Completer<void>();
      when(() => root.update(any())).thenAnswer((_) => serverAnswer.future);
      viewModel = TippersViewModel(true, skipInit: true);
      viewModel.applyTippersSnapshotForTest(const []);
      viewModel.updates[rolePath] = 'tipper';
    });

    tearDown(() {
      ConfiguredRealtimeDatabase.resetForTest();
    });

    test('without a limit it waits for the server, as it always has', () async {
      var finished = false;
      final Future<void> save = viewModel.saveBatchOfTipperChangesToDb().then((
        _,
      ) {
        finished = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(finished, isFalse);
      verify(() => root.update({rolePath: 'tipper'})).called(1);

      serverAnswer.complete();
      await save;
      expect(finished, isTrue);
      expect(viewModel.updates, isEmpty);
    });

    test(
      'with a limit it stops waiting and says the write is queued',
      () async {
        await expectLater(
          viewModel.saveBatchOfTipperChangesToDb(
            acknowledgementLimit: const Duration(milliseconds: 30),
          ),
          throwsA(isA<WriteNotConfirmedException>()),
        );

        expect(
          viewModel.updates,
          isEmpty,
          reason: 'the pending set is cleared',
        );
        verify(() => root.update({rolePath: 'tipper'})).called(1);

        // The write is still the database's to deliver; a late answer is harmless.
        serverAnswer.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'with a limit it still surfaces a rejection from the server',
      () async {
        when(() => root.update(any()))
            .thenAnswer((_) async => throw StateError('permission denied'));

        await expectLater(
          viewModel.saveBatchOfTipperChangesToDb(
            acknowledgementLimit: const Duration(seconds: 5),
          ),
          throwsA(isA<StateError>()),
        );
        expect(viewModel.updates, isEmpty);
      },
    );

    test(
      'with a limit it completes normally when the server answers in time',
      () async {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 5))
              .then((_) => serverAnswer.complete()),
        );

        await viewModel.saveBatchOfTipperChangesToDb(
          acknowledgementLimit: const Duration(seconds: 5),
        );

        expect(viewModel.updates, isEmpty);
      },
    );
  });
}
