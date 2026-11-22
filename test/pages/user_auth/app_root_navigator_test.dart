import 'package:daufootytipping/pages/user_auth/app_root_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page that records when it goes, standing in for a signed-in screen that
/// still draws from the user's view models while it fades out.
class _RecordingPage extends StatefulWidget {
  const _RecordingPage(this.label, this.events);

  final String label;
  final List<String> events;

  @override
  State<_RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<_RecordingPage> {
  @override
  void dispose() {
    widget.events.add('${widget.label} disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

void main() {
  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> events;
  late AppRootNavigator rootNavigator;

  setUp(() {
    navigatorKey = GlobalKey<NavigatorState>();
    events = <String>[];
    rootNavigator = AppRootNavigator(
      navigatorKey: navigatorKey,
      rootBuilder: (context) {
        events.add('root built');
        return const Text('root page');
      },
      onReturn: () => events.add('reset'),
      onOldRoutesGone: () => events.add('released'),
    );
  });

  // The app wraps its Navigator in a host carrying the connection banner and
  // floating controls; returning to the root must reuse it, not add another.
  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, navigator) => Column(
          children: [
            const Text('app host'),
            Expanded(child: navigator ?? const SizedBox.shrink()),
          ],
        ),
        home: _RecordingPage('home', events),
      ),
    );
  }

  NavigatorState navigatorOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator));

  Future<void> pushPages(WidgetTester tester, List<String> labels) async {
    for (final String label in labels) {
      navigatorOf(tester).push(
        MaterialPageRoute<void>(
          builder: (context) => _RecordingPage(label, events),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('clears a stack of several routes down to the root page', (
    tester,
  ) async {
    await pumpApp(tester);
    await pushPages(tester, <String>['profile', 'help', 'sign out']);
    expect(navigatorOf(tester).canPop(), isTrue);

    rootNavigator.returnToRoot();
    await tester.pumpAndSettle();

    expect(find.text('root page'), findsOneWidget);
    for (final String label in <String>[
      'home',
      'profile',
      'help',
      'sign out',
    ]) {
      expect(find.text(label), findsNothing);
      expect(events, contains('$label disposed'));
    }
    expect(navigatorOf(tester).canPop(), isFalse);
  });

  testWidgets('resets before the root page is built', (tester) async {
    await pumpApp(tester);

    rootNavigator.returnToRoot();
    await tester.pumpAndSettle();

    expect(events.indexOf('reset'), lessThan(events.indexOf('root built')));
  });

  testWidgets(
    'releases only after the old pages have faded out and been disposed',
    (tester) async {
      await pumpApp(tester);
      await pushPages(tester, <String>['profile']);

      rootNavigator.returnToRoot();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('profile'), findsOneWidget, reason: 'still fading out');
      expect(events, isNot(contains('released')));

      await tester.pumpAndSettle();

      expect(events, contains('released'));
      expect(
        events.indexOf('profile disposed'),
        lessThan(events.indexOf('released')),
      );
    },
  );

  testWidgets('keeps one app host across repeated sign-outs', (tester) async {
    await pumpApp(tester);

    for (int signOut = 0; signOut < 3; signOut++) {
      await pushPages(tester, <String>['signed in $signOut']);
      rootNavigator.returnToRoot();
      await tester.pumpAndSettle();
    }

    expect(find.text('app host'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('root page'), findsOneWidget);
    expect(events.where((event) => event == 'reset'), hasLength(3));
    expect(events.where((event) => event == 'released'), hasLength(3));
  });

  test('resets and releases at once when no Navigator is built yet', () {
    rootNavigator.returnToRoot();

    expect(events, <String>['reset', 'released']);
  });
}
