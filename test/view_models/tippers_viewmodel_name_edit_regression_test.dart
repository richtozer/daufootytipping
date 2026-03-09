import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class NameEditTestTippersViewModel extends TippersViewModel {
  NameEditTestTippersViewModel() : super(true, skipInit: true);

  @override
  Future<void> updateTipperAttribute(
    String tipperDbKey,
    String attributeName,
    dynamic attributeValue,
  ) async {}

  @override
  Future<void> saveBatchOfTipperChangesToDb() async {}
}

void main() {
  test(
    'setTipperName updates linked state immediately without waiting for a stream refresh',
    () async {
      final Tipper freshTipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'tipper@example.com',
        logon: 'tipper@example.com',
        name: 'Old Alias',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const [],
      );
      final Tipper cachedTipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'tipper@example.com',
        logon: 'tipper@example.com',
        name: 'Old Alias',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const [],
      );

      final NameEditTestTippersViewModel vm = NameEditTestTippersViewModel();
      vm.applyTippersSnapshotForTest([freshTipper]);
      vm.setLinkedTippersForTest(cachedTipper);

      int notifyCount = 0;
      vm.addListener(() {
        notifyCount += 1;
      });

      await vm.setTipperName('tipper-1', 'New Alias');

      expect(vm.tippers.single.name, 'New Alias');
      expect(vm.authenticatedTipper!.name, 'New Alias');
      expect(vm.selectedTipper.name, 'New Alias');
      expect(identical(vm.authenticatedTipper, vm.tippers.single), isTrue);
      expect(identical(vm.selectedTipper, vm.tippers.single), isTrue);
      expect(notifyCount, greaterThan(0));
    },
  );
}
