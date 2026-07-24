import 'dart:async';

import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TippersViewModel god mode selection', () {
    late TippersViewModel viewModel;
    late Tipper adminTipper;
    late Tipper godModeTipper;

    setUp(() {
      viewModel = TippersViewModel(true, skipInit: true);
      adminTipper = Tipper(
        dbkey: 'admin-1',
        authuid: 'auth-admin',
        email: 'admin@example.com',
        name: 'Admin',
        tipperRole: TipperRole.admin,
        compsPaidFor: const [],
      );
      godModeTipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-tipper',
        email: 'tipper@example.com',
        name: 'Tipper',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const [],
      );
      viewModel.setLinkedTippersForTest(adminTipper);
    });

    test(
      'does not notify listeners until selected tipper view models refresh',
      () async {
        final refreshCompleter = Completer<void>();
        var notificationCount = 0;
        viewModel.addListener(() {
          notificationCount++;
        });

        final changeFuture = viewModel.changeSelectedTipperAfterRefresh(
          godModeTipper,
          refreshSelectedTipperViewModels: () => refreshCompleter.future,
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.selectedTipper, same(godModeTipper));
        expect(notificationCount, 0);

        refreshCompleter.complete();
        await changeFuture;

        expect(notificationCount, 1);
      },
    );

    test('rolls selected tipper back if the refresh fails', () async {
      var notificationCount = 0;
      viewModel.addListener(() {
        notificationCount++;
      });

      await expectLater(
        viewModel.changeSelectedTipperAfterRefresh(
          godModeTipper,
          refreshSelectedTipperViewModels: () async {
            throw StateError('refresh failed');
          },
        ),
        throwsStateError,
      );

      expect(viewModel.selectedTipper, same(adminTipper));
      expect(notificationCount, 1);
    });
  });
}
