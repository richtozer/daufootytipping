import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const tabs = AppNavTabs(
    destinations: [
      AppNavDestination(icon: Icon(Icons.person), shortLabel: 'PROFILE'),
    ],
    selectedIndex: 0,
    onSelected: _ignore,
  );
  final home = MaterialPageRoute<void>(builder: (_) => const SizedBox());
  final stats = MaterialPageRoute<void>(builder: (_) => const SizedBox());
  final owner = Object();

  late AppControlsViewModel viewModel;

  setUp(() => viewModel = AppControlsViewModel());
  tearDown(() => viewModel.dispose());

  test('offers nothing until a screen owns the tabs', () {
    viewModel.setPageRoutes([home]);
    expect(viewModel.mode, AppControlsMode.none);
  });

  test('offers the tabs on the only page when a screen owns them', () {
    viewModel.setPageRoutes([home]);
    viewModel.showTabs(owner, tabs);
    expect(viewModel.mode, AppControlsMode.tabs);
  });

  test('offers Back on any pushed page, tabs or not', () {
    viewModel.showTabs(owner, tabs);
    viewModel.setPageRoutes([home, stats]);
    expect(viewModel.mode, AppControlsMode.back);
    viewModel.hideTabs(owner);
    expect(viewModel.mode, AppControlsMode.back);
  });

  test('returns to the tabs when the pushed page is popped', () {
    viewModel.showTabs(owner, tabs);
    viewModel.setPageRoutes([home, stats]);
    viewModel.setPageRoutes([home]);
    expect(viewModel.mode, AppControlsMode.tabs);
  });

  test('only the screen that offered the tabs can take them back', () {
    final newcomer = Object();
    viewModel.showTabs(owner, tabs);
    viewModel.showTabs(newcomer, tabs);
    viewModel.hideTabs(owner);
    expect(viewModel.tabs, isNotNull, reason: 'the newcomer still holds them');
    viewModel.hideTabs(newcomer);
    expect(viewModel.tabs, isNull);
  });

  test('page actions belong to the page on top and go when it does', () {
    final add = AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () {});
    viewModel.setPageRoutes([home, stats]);
    viewModel.setPageActions(stats, [add]);
    expect(viewModel.pageActions, [add]);

    viewModel.setPageRoutes([
      home,
      stats,
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    ]);
    expect(viewModel.pageActions, isEmpty, reason: 'a page above has none');

    viewModel.setPageRoutes([home]);
    expect(viewModel.pageActions, isEmpty);
    viewModel.setPageRoutes([home, stats]);
    expect(
      viewModel.pageActions,
      isEmpty,
      reason: 'popped routes are forgotten',
    );
  });

  test('announces a change made outside a frame straight away', () {
    var heard = 0;
    viewModel.addListener(() => heard++);
    viewModel.showTabs(owner, tabs);
    expect(heard, 1);
  });
}

void _ignore(int index) {}
