import 'package:cached_network_image/cached_network_image.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows initials when no image URL is available', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: circleAvatarWithFallback(text: 'Ada Lovelace'),
        ),
      ),
    );

    expect(find.text('AL'), findsOneWidget);
  });

  testWidgets('handles network image errors so initials can remain visible', (
    tester,
  ) async {
    final widget = circleAvatarWithFallback(
      imageUrl: 'https://example.com/avatar.png',
      text: 'Ada Lovelace',
    );

    final avatar = widget as CircleAvatar;

    expect(avatar.foregroundImage, isA<CachedNetworkImageProvider>());
    expect(avatar.onForegroundImageError, isNotNull);
    expect(
      () => avatar.onForegroundImageError!(
        const FormatException('decode failed'),
        StackTrace.empty,
      ),
      returnsNormally,
    );
  });
}
