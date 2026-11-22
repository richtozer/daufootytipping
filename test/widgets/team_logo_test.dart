import 'dart:async';

import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:daufootytipping/widgets/team_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart';

const String _squareSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="red"/></svg>';

Widget _app(Widget child) => MaterialApp(home: Center(child: child));

void main() {
  group('TeamInitialsBadge.initialsOf', () {
    test('takes the first letter of the first two words', () {
      expect(TeamInitialsBadge.initialsOf('Perth Bears'), 'PB');
      expect(TeamInitialsBadge.initialsOf('Broncos'), 'B');
      expect(TeamInitialsBadge.initialsOf('West Coast Eagles'), 'WC');
      expect(TeamInitialsBadge.initialsOf('  sea   eagles '), 'SE');
      expect(TeamInitialsBadge.initialsOf(''), '');
    });
  });

  group('TeamLogo', () {
    late StreamController<Object?> values;

    setUp(() {
      values = StreamController<Object?>();
      di.registerSingleton<TeamLogosViewModel>(
        TeamLogosViewModel(source: () => values.stream),
      );
    });

    tearDown(() async {
      await di.reset();
      await values.close();
    });

    Future<void> emit(WidgetTester tester, Object? value) async {
      values.add(value);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows initials until the logos arrive, then the svg', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const TeamLogo(
            teamDbKey: 'nrl-Perth Bears',
            teamName: 'Perth Bears',
            size: 28,
          ),
        ),
      );
      expect(find.text('PB'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);

      await emit(tester, {
        'nrl-Perth Bears': {'svg': _squareSvg},
      });

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.getSize(find.byType(TeamLogo)), const Size(28, 28));
    });

    testWidgets('keeps initials for a team with no stored logo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const TeamLogo(
            teamDbKey: 'nrl-Perth Bears',
            teamName: 'Perth Bears',
            size: 28,
          ),
        ),
      );
      await emit(tester, {
        'nrl-Broncos': {'svg': _squareSvg},
      });

      expect(find.text('PB'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('falls back to initials when the stored svg is invalid', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const TeamLogo(
            teamDbKey: 'nrl-Broncos',
            teamName: 'Broncos',
            size: 28,
          ),
        ),
      );
      await tester.runAsync(() async {
        values.add({
          'nrl-Broncos': {'svg': 'this is not svg'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('B'), findsOneWidget);
    });
  });

  testWidgets('shows initials when no logos view model is registered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const TeamLogo(teamDbKey: 'nrl-Storm', teamName: 'Storm', size: 20)),
    );

    expect(find.text('S'), findsOneWidget);
  });
}
