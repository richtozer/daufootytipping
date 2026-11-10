import 'package:daufootytipping/pages/user_auth/user_auth_upgate_app_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Uri> opened;
  var reloads = 0;
  var storeOpens = true;

  Future<void> pumpLink(
    WidgetTester tester, {
    bool onWeb = false,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UpdateAppLink(
              onWeb: onWeb,
              platform: platform,
              reload: () async => reloads++,
              open: (url) async {
                opened.add(url);
                return storeOpens;
              },
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    opened = <Uri>[];
    reloads = 0;
    storeOpens = true;
  });

  group('on the web', () {
    testWidgets('reloads the page and opens no store', (tester) async {
      await pumpLink(tester, onWeb: true, platform: TargetPlatform.macOS);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(reloads, 1);
      expect(opened, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the button says Reload, not Update App', (tester) async {
      await pumpLink(tester, onWeb: true);

      expect(find.text('Reload'), findsOneWidget);
      expect(find.text('Update App'), findsNothing);
    });
  });

  group('in an installed app', () {
    testWidgets('on iOS it opens the App Store listing', (tester) async {
      await pumpLink(tester);

      await tester.tap(find.text('Update App'));
      await tester.pump();

      expect(opened, [Uri.parse(appStoreUrl)]);
      expect(reloads, 0);
    });

    testWidgets('on Android it opens the Play Store listing', (tester) async {
      await pumpLink(tester, platform: TargetPlatform.android);

      await tester.tap(find.text('Update App'));
      await tester.pump();

      expect(opened, [Uri.parse(playStoreUrl)]);
    });

    testWidgets('a store that will not open says so, in words', (tester) async {
      storeOpens = false;
      await pumpLink(tester);

      await tester.tap(find.text('Update App'));
      await tester.pump();

      expect(
        find.textContaining('Could not open the app store'),
        findsOneWidget,
      );
    });

    testWidgets('a platform with no store opens nothing and says so', (
      tester,
    ) async {
      await pumpLink(tester, platform: TargetPlatform.macOS);

      await tester.tap(find.text('Update App'));
      await tester.pump();

      expect(opened, isEmpty);
      expect(
        find.textContaining('Could not open the app store'),
        findsOneWidget,
      );
    });
  });

  group('what the notice says', () {
    test('a web user is told to reload', () {
      final message = unsupportedVersionMessage(onWeb: true);

      expect(message, contains('Reload the page'));
      expect(message, contains('close the tab and reopen the site'));
      expect(message, isNot(contains('app store')));
    });

    test('an installed app user is told to use the app store', () {
      expect(
        unsupportedVersionMessage(onWeb: false),
        contains('update the app from the app store'),
      );
    });

    testWidgets('the message widget shows the one for where it runs', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: UnsupportedVersionMessage(onWeb: true)),
      );

      expect(find.textContaining('Reload the page'), findsOneWidget);
    });
  });
}
