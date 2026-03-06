import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:watch_it/watch_it.dart';

class MockFirebaseMessagingService extends Mock
    implements FirebaseMessagingService {}

void main() {
  late MockFirebaseMessagingService messagingService;

  setUp(() {
    messagingService = MockFirebaseMessagingService();
    when(() => messagingService.initialLoadComplete).thenAnswer((_) async {});
    when(() => messagingService.fbmToken).thenReturn('token12345');

    if (di.isRegistered<FirebaseMessagingService>()) {
      di.unregister<FirebaseMessagingService>();
    }
    di.registerSingleton<FirebaseMessagingService>(messagingService);
  });

  tearDown(() {
    if (di.isRegistered<FirebaseMessagingService>()) {
      di.unregister<FirebaseMessagingService>();
    }
  });

  test(
    'regression: background user link waits for tipper snapshot before unblocking paid status',
    () async {
      final DAUComp comp = DAUComp(
        dbkey: 'comp-2026',
        name: '2026 DAU',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: const [],
      );

      final Tipper cachedTipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'tipper@example.com',
        logon: 'tipper@example.com',
        name: 'Tipper One',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const [],
      );

      final Tipper freshTipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'tipper@example.com',
        logon: 'tipper@example.com',
        name: 'Tipper One',
        tipperRole: TipperRole.tipper,
        compsPaidFor: [comp],
      );

      final TippersViewModel vm = TippersViewModel(true, skipInit: true);
      vm.setLinkedTippersForTest(cachedTipper);

      await vm.completeIsUserLinkedWhenReadyForTest(
        awaitMessagingRegistration: true,
      );

      await Future<void>.delayed(Duration.zero);
      expect(vm.isUserLinkedCompletedForTest, isFalse);
      expect(vm.selectedTipper.paidForComp(comp), isFalse);

      vm.applyTippersSnapshotForTest([freshTipper]);

      await vm.isUserLinked.timeout(const Duration(seconds: 1));

      expect(vm.isUserLinkedCompletedForTest, isTrue);
      expect(vm.selectedTipper.paidForComp(comp), isTrue);
      expect(vm.authenticatedTipper!.paidForComp(comp), isTrue);
    },
  );
}
