import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = Typography.material2021().black;

  List<InlineSpan> spansOf(TipsTeamDisplay team, {Color? highlight}) =>
      team.text(theme, highlight: highlight ?? kSelectionLightColor).children!;

  test('a winning score is a rounded badge in the highlight colour', () {
    const team = TipsTeamDisplay('Storm', 'x.svg', score: 23, winner: true);
    const green = Color(0xFF123456);

    final badge = spansOf(team, highlight: green).whereType<ScoreBadgeSpan>();

    expect(badge, hasLength(1));
    expect(badge.single.score, '23');
    final box = badge.single.child as DecoratedBox;
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, green);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(kCardCornerRadius),
      reason: 'the same corner as the other elements',
    );
  });

  test('a score that did not win stays plain bold text', () {
    const team = TipsTeamDisplay('Eels', 'x.svg', score: 22);

    final spans = spansOf(team);

    expect(spans.whereType<ScoreBadgeSpan>(), isEmpty);
    expect((spans.last as TextSpan).text, ' 22');
  });

  test('a team with no score has no badge', () {
    const team = TipsTeamDisplay('Eels', 'x.svg');

    expect(spansOf(team).whereType<ScoreBadgeSpan>(), isEmpty);
  });

  test('the highlight is the nav selection green in light and dark', () {
    expect(kSelectionLightColor, const Color(0xF2C5E1A5));
    expect(kSelectionDarkColor, const Color(0x998BC34A));
  });
}
