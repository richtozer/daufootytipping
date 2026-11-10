import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Tipper _tipper(String name, {TipperRole role = TipperRole.tipper}) => Tipper(
  dbkey: 'tipper-1',
  authuid: 'auth-1',
  email: 'tipper@example.com',
  logon: 'tipper@example.com',
  name: name,
  tipperRole: role,
  compsPaidFor: const [],
);

void main() {
  test('applyOwnAlias shows the new alias at once, without waiting for a stream refresh', () {
    final Tipper listed = _tipper('Old Alias');
    // The signed-in copy carries the private fields (here the role) that the
    // public list does not, so it must stay the signed-in copy.
    final Tipper signedIn = _tipper('Old Alias', role: TipperRole.admin);
    final TippersViewModel vm = TippersViewModel(true, skipInit: true);
    vm.applyTippersSnapshotForTest([listed]);
    vm.setLinkedTippersForTest(signedIn);
    var notifications = 0;
    vm.addListener(() => notifications++);

    vm.applyOwnAlias('tipper-1', 'New Alias');

    expect(vm.tippers.single.name, 'New Alias');
    expect(vm.authenticatedTipper!.name, 'New Alias');
    expect(vm.selectedTipper.name, 'New Alias');
    expect(identical(vm.authenticatedTipper, signedIn), isTrue);
    expect(vm.authenticatedTipper!.tipperRole, TipperRole.admin);
    expect(notifications, greaterThan(0));
  });

  test('applyOwnAlias leaves other tippers alone', () {
    final TippersViewModel vm = TippersViewModel(true, skipInit: true);
    final Tipper other = Tipper(
      dbkey: 'tipper-2',
      authuid: 'auth-2',
      email: null,
      name: 'Other',
      tipperRole: TipperRole.tipper,
      compsPaidFor: const [],
    );
    vm.applyTippersSnapshotForTest([_tipper('Old Alias'), other]);
    vm.setLinkedTippersForTest(_tipper('Old Alias'));

    vm.applyOwnAlias('tipper-1', 'New Alias');

    expect(other.name, 'Other');
  });
}
