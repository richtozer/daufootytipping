import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_panel_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watch_it/watch_it.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockPackageInfoService extends Mock implements PackageInfoService {}

void main() {
  late Tipper tipper;

  Future<void> pumpProfile(WidgetTester tester, {required double width}) async {
    await di.reset();
    tipper = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'comm@example.com',
      logon: 'toaster@example.com',
      name: 'toaster',
      tipperRole: TipperRole.tipper,
      compsPaidFor: const [],
    );
    final comp = DAUComp(
      dbkey: 'comp-1',
      name: 'DAU Footy Tipping 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );
    final tippers = _MockTippersViewModel();
    when(() => tippers.addListener(any())).thenReturn(null);
    when(() => tippers.removeListener(any())).thenReturn(null);
    when(() => tippers.authenticatedTipper).thenReturn(tipper);
    when(() => tippers.tippers).thenReturn([tipper]);
    when(() => tippers.selectedTipper).thenReturn(tipper);
    final comps = _MockDAUCompsViewModel();
    when(() => comps.addListener(any())).thenReturn(null);
    when(() => comps.removeListener(any())).thenReturn(null);
    when(() => comps.activeDAUComp).thenReturn(comp);
    when(() => comps.selectedDAUComp).thenReturn(comp);
    final packageInfo = _MockPackageInfoService();
    when(() => packageInfo.packageInfo).thenAnswer(
      (_) async => PackageInfo(
        appName: 'DAU Tips',
        packageName: 'coach.interview.daufootytipping',
        version: '1.4.1',
        buildNumber: '713',
      ),
    );
    di.registerSingleton<TippersViewModel>(tippers);
    di.registerSingleton<DAUCompsViewModel>(comps);
    di.registerSingleton<PackageInfoService>(packageInfo);

    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Profile())));
    await tester.pump();
    await tester.pump();
  }

  tearDown(() async => di.reset());

  testWidgets('is as wide as the Stats page, and no wider', (tester) async {
    await pumpProfile(tester, width: 1000);

    for (final card in find.byType(AppPanelCard).evaluate()) {
      expect(
        tester.getSize(find.byWidget(card.widget)).width,
        kFormContentWidth,
      );
    }
  });

  testWidgets('a long prompt flows in the width available, not a fixed box', (
    tester,
  ) async {
    await pumpProfile(tester, width: 1000);

    final prompt = tester.getSize(
      find.textContaining('Tipper in a previous year?'),
    );
    // Flows across the card instead of wrapping in a box of its own.
    expect(prompt.width, greaterThan(350));
  });
}
