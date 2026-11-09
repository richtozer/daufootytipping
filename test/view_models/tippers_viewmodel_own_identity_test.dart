import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:watch_it/watch_it.dart';

class _MockMessaging extends Mock implements FirebaseMessagingService {}

class _FakeTipper extends Fake implements Tipper {}

/// After the purge the public tipper list carries only a tipper's name, photo and
/// paid comps. The signed-in tipper's role, login, email and account id come from
/// their private record when they are linked, and must survive every refresh from
/// the public list: an administrator who lost the admin menu at the first refresh
/// would be the failure.
void main() {
  final DAUComp comp = DAUComp(
    dbkey: 'c1',
    name: '2027',
    aflFixtureJsonURL: Uri.parse('https://example.test/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.test/nrl'),
    daurounds: const [],
  );

  Tipper own() => Tipper(
    dbkey: 't1',
    authuid: 'uidA',
    email: 'a@example.test',
    logon: 'login@example.test',
    name: 'Alice',
    tipperRole: TipperRole.admin,
    compsPaidFor: const [],
    acctLoggedOnUTC: DateTime.utc(2026, 3, 2),
  );

  // As the public list now delivers it: no role, no login, no account id.
  Tipper fromThePublicList({
    String name = 'Alice',
    List<DAUComp> comps = const [],
  }) =>
      Tipper.fromJson(<String, dynamic>{'name': name}, 't1')
        ..compsPaidFor = comps;

  setUpAll(() {
    registerFallbackValue(_FakeTipper());
  });

  setUp(() {
    final messaging = _MockMessaging();
    when(() => messaging.initialLoadComplete).thenAnswer((_) async {});
    when(() => messaging.fbmToken).thenReturn('token12345');
    when(() => messaging.registerTokenForTipper(any()))
        .thenAnswer((_) async {});
    if (di.isRegistered<FirebaseMessagingService>()) {
      di.unregister<FirebaseMessagingService>();
    }
    di.registerSingleton<FirebaseMessagingService>(messaging);
  });

  tearDown(() {
    if (di.isRegistered<FirebaseMessagingService>()) {
      di.unregister<FirebaseMessagingService>();
    }
  });

  test('a refresh from the purged public list keeps the signed-in tipper\'s role, login and account id', () async {
    final vm = TippersViewModel(true, skipInit: true);
    vm.setLinkedTippersForTest(own());

    vm.applyTippersSnapshotForTest([
      fromThePublicList(name: 'Alice (renamed)', comps: [comp]),
    ]);

    final tipper = vm.authenticatedTipper!;
    expect(tipper.tipperRole, TipperRole.admin);
    expect(tipper.logon, 'login@example.test');
    expect(tipper.email, 'a@example.test');
    expect(tipper.authuid, 'uidA');
    expect(tipper.acctLoggedOnUTC, DateTime.utc(2026, 3, 2));
    // and takes what the public list is for.
    expect(tipper.name, 'Alice (renamed)');
    expect(tipper.paidForComp(comp), true);
    expect(vm.selectedTipper.tipperRole, TipperRole.admin);
  });

  test('so does every later refresh', () async {
    final vm = TippersViewModel(true, skipInit: true);
    vm.setLinkedTippersForTest(own());
    for (var i = 0; i < 3; i++) {
      vm.applyTippersSnapshotForTest([fromThePublicList(name: 'Alice $i')]);
    }
    expect(vm.authenticatedTipper!.tipperRole, TipperRole.admin);
    expect(vm.authenticatedTipper!.name, 'Alice 2');
  });

  test('opening from the kept tipper promotes it to the list\'s copy without losing its role', () async {
    final vm = TippersViewModel(true, skipInit: true);
    vm.applyTippersSnapshotForTest([
      fromThePublicList(comps: [comp]),
    ]);

    vm.setAuthenticatedTipper(own());

    expect(vm.authenticatedTipper!.tipperRole, TipperRole.admin);
    expect(vm.authenticatedTipper!.logon, 'login@example.test');
    expect(
      vm.authenticatedTipper!.paidForComp(comp),
      true,
      reason: 'the fresh paid comps',
    );
    expect(vm.selectedTipper.tipperRole, TipperRole.admin);
  });

  test('another tipper selected in god mode is not given the signed-in tipper\'s identity', () async {
    final vm = TippersViewModel(true, skipInit: true);
    vm.setLinkedTippersForTest(own());
    final other = Tipper.fromJson(<String, dynamic>{'name': 'Bob'}, 't2');
    vm.applyTippersSnapshotForTest([fromThePublicList(), other]);

    await vm.changeSelectedTipperAfterRefresh(
      other,
      refreshSelectedTipperViewModels: () async {},
    );
    vm.applyTippersSnapshotForTest([
      fromThePublicList(name: 'Alice again'),
      other,
    ]);

    expect(vm.selectedTipper.dbkey, 't2');
    expect(vm.selectedTipper.tipperRole, TipperRole.tipper);
    expect(vm.authenticatedTipper!.tipperRole, TipperRole.admin);
    expect(vm.inGodMode, true);
  });

  test('findTipperByUid finds only the signed-in tipper', () async {
    final vm = TippersViewModel(true, skipInit: true);
    vm.setLinkedTippersForTest(own());
    vm.applyTippersSnapshotForTest([
      fromThePublicList(),
      Tipper.fromJson(<String, dynamic>{'name': 'Bob'}, 't2'),
    ]);

    expect((await vm.findTipperByUid('uidA'))!.dbkey, 't1');
    expect(await vm.findTipperByUid('uidB'), isNull);
    expect(
      await vm.findTipperByUid(''),
      isNull,
      reason: 'an unknown account id never matches the others',
    );
  });
}
