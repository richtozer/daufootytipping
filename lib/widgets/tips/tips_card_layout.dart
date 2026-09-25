import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TipsCardMode { wide, standard, stacked }
enum TipsChoiceArrangement { inline, paired, vertical }

/// The exact styled content rendered by one card, grouped for height measurement.
class TipsCardContent {
  const TipsCardContent({required this.home, required this.away,
    required this.info, required this.results, required this.editable,
    required this.choiceLabels});
  final List<String> choiceLabels;
  final TextSpan home;
  final TextSpan away;
  final String info;
  final List<TextSpan> results;
  final bool editable;
}

/// Measurements shared by all cards in one list, including its scroll offsets.
/// TextPainter uses the actual scaler rather than assuming linear font scaling.
class TipsCardLayout {
  const TipsCardLayout({
    this.carouselViewportFraction = viewportFraction,
    required this.mode,
    required this.choices,
    required this.cardExtent,
    required this.carouselHeight,
    required this.matchupWidth,
    required this.matchupHeight,
    required this.standardMinWidth,
    required this.wideMinWidth,
  });

  final TipsCardMode mode;
  final double carouselViewportFraction;
  final TipsChoiceArrangement choices;
  final double cardExtent;
  final double carouselHeight;
  final double matchupWidth;
  final double matchupHeight;
  final double standardMinWidth;
  final double wideMinWidth;

  static const double viewportFraction = 0.9;
  static const double standardTeamWidth = 135;
  static const double standardExtent = 128;

  static double teamLogoSize(TextScaler scaler, TextTheme theme) {
    return scaledIconSize(scaler, theme, size: 25);
  }

  static double scaledIconSize(TextScaler scaler, TextTheme theme, {double size = 24}) {
    final fontSize = theme.titleMedium?.fontSize ?? 16;
    return size * scaler.scale(fontSize) / fontSize;
  }

  static TipsCardLayout measure({
    required double width,
    required TextScaler textScaler,
    required TextTheme textTheme,
    required TextDirection textDirection,
    required List<TipsCardContent> cards,
    bool percentStats = false,
  }) {
    final label = textTheme.labelLarge ?? const TextStyle(fontSize: 14);
    final info = textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final body = textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    // Reuse repeated labels within this measurement pass.
    final measured = <(TextSpan, double), Size>{};
    Size measureSpan(TextSpan text, [double maxWidth = double.infinity]) {
      final key = (text, maxWidth);
      final cached = measured[key];
      if (cached != null) return cached;
      final painter = TextPainter(
        text: text, textScaler: textScaler,
        textDirection: textDirection,
      )..layout(maxWidth: math.max(1, maxWidth));
      final size = painter.size;
      painter.dispose();
      measured[key] = size;
      return size;
    }
    Size measureText(String text, TextStyle style, [double maxWidth = double.infinity]) =>
        measureSpan(TextSpan(text: text, style: style), maxWidth);

    final labels = cards.expand((card) => card.choiceLabels).toSet();
    final chipWidths = List.generate(5, (index) => cards.fold<double>(0,
        (width, card) => math.max(width,
            measureText(card.choiceLabels[index], label).width + 22)));
    // Include the result trophy and a loaded percentage's full footprint.
    final percentLabelWidth = math.max(measureText('100.0%', label).width,
        labels.fold<double>(0, (width, text) => math.max(width, measureText(text, info).width)));
    final percentWidth = percentLabelWidth + 16;
    final trophySize = scaledIconSize(textScaler, textTheme, size: 18);
    final trophyGrowth = math.max(0.0, trophySize - 18);
    final pairedWidth = (percentStats ? percentWidth * 2 + 48 + trophyGrowth :
      math.max(chipWidths[0] + chipWidths[1], chipWidths[3] + chipWidths[4])) + 24;
    // Normal chips retain their existing visible dimensions; adaptive chips
    // reserve at least 48 logical pixels per row for larger text/touch access.
    final textHeight = labels.fold<double>(0, (height, text) =>
        math.max(height, measureText(text, label).height));
    final compactChipHeight = math.max(32.0, textHeight + 16);
    final adaptiveChipHeight = math.max(48.0, textHeight + 16);
    final largestName = cards.fold<double>(0, (value, card) => math.max(value,
        math.max(measureSpan(card.home).width, measureSpan(card.away).width)));
    final logoSize = teamLogoSize(textScaler, textTheme);
    final middleWidth = logoSize * 2 + measureText(' V ', body).width;
    final inlineTeamWidth = largestName * 2 + math.max(88.0, middleWidth + 16);
    final inlineChoicesWidth = (percentStats ? percentWidth * 5 + 48 + 48 + trophyGrowth :
      chipWidths.fold<double>(0, (a, b) => a + b) + 48) + 32;
    // Card margins, panel padding and chip border/rounding allowance are included.
    final scaledTeamWidth = math.max(standardTeamWidth,
        standardTeamWidth * textScaler.scale(16) / 16);
    final standardMin = scaledTeamWidth + pairedWidth / viewportFraction + 8;
    final wideMin = inlineTeamWidth + inlineChoicesWidth / viewportFraction + 8;
    final mode = width >= wideMin ? TipsCardMode.wide
        : width >= standardMin ? TipsCardMode.standard : TipsCardMode.stacked;
    final matchupWidth = mode == TipsCardMode.wide ? inlineTeamWidth : scaledTeamWidth;
    final carouselWidth = mode == TipsCardMode.stacked
        ? width - 8 : width - 8 - matchupWidth;
    // The legacy allowance exceeds the rendered plain paired row by 16 px
    // with the app's chip theme. Keep the legacy standard breakpoint, but use
    // the rendered footprint for stacked mode (covered by layout tests).
    final requiredPairedWidth = mode == TipsCardMode.stacked && !percentStats
        ? pairedWidth - 16 : pairedWidth;
    // All layouts prioritise content width over the empty neighbouring strip.
    const fraction = viewportFraction;
    final panelWidth = math.max(1.0, carouselWidth * fraction - 24);
    final arrangement = mode == TipsCardMode.wide ? TipsChoiceArrangement.inline
        : carouselWidth * fraction >= requiredPairedWidth
            ? TipsChoiceArrangement.paired : TipsChoiceArrangement.vertical;
    final percentageContentWidth = math.min(percentLabelWidth,
        math.max(1.0, panelWidth - 72 - trophyGrowth));
    final percentageHeight = math.max(20.0,
        measureText('100.0%', label, percentageContentWidth).height) + 2 +
        labels.fold<double>(0, (height, text) => math.max(height,
            measureText(text, info, percentageContentWidth).height)) + 16;
    final chipHeight = percentStats ? math.max(trophySize + 16, math.max(48.0, percentageHeight)) :
        mode == TipsCardMode.standard ? compactChipHeight : adaptiveChipHeight;
    final choiceHeight = switch (arrangement) {
      TipsChoiceArrangement.inline => chipHeight + 8,
      TipsChoiceArrangement.paired => chipHeight * 3 + 8,
      TipsChoiceArrangement.vertical => 5.0 * math.max(chipHeight,
          labels.fold<double>(0, (height, text) => math.max(height,
              measureText(text, label, panelWidth - 24).height)) + 16) + 24,
    };
    // Inner card margins are 8 px; results add 2 px padding on each side.
    final resultWidth = carouselWidth * fraction - 12;
    double resultHeight(TipsCardContent card) {
      if (card.results.isEmpty) return 0;
      if (mode != TipsCardMode.wide) {
        return card.results.fold<double>(8, (height, row) =>
            height + measureSpan(row, resultWidth).height + 4);
      }
      // Match Wrap's actual runs, including the 12 px gap between groups.
      var total = 8.0;
      var runWidth = 0.0;
      var runHeight = 0.0;
      for (final row in card.results) {
        final size = measureSpan(row, resultWidth);
        final itemWidth = size.width + 4;
        if (runWidth > 0 && runWidth + 12 + itemWidth > resultWidth + 4) {
          total += runHeight;
          runWidth = 0;
          runHeight = 0;
        }
        runWidth += (runWidth == 0 ? 0 : 12) + itemWidth;
        runHeight = math.max(runHeight, size.height + 4);
      }
      return total + runHeight;
    }
    final panelHeight = percentStats ? choiceHeight : cards.fold<double>(choiceHeight,
        (height, card) => math.max(height, math.max(resultHeight(card),
            measureText(card.info, info, panelWidth).height + 24)));
    final teamWidth = mode == TipsCardMode.stacked ? width - 16 : matchupWidth - 8;
    final matchupHeight = cards.fold<double>(0, (height, card) {
      final middleHeight = card.editable ? scaledIconSize(textScaler, textTheme) :
          math.max(logoSize, measureText(' V ', body).height);
      final nameWidth = mode == TipsCardMode.wide
          ? (matchupWidth - middleWidth) / 2 - 8 : teamWidth;
      final homeHeight = measureSpan(card.home, nameWidth).height;
      final awayHeight = measureSpan(card.away, nameWidth).height;
      return math.max(height, mode == TipsCardMode.wide
          ? math.max(math.max(homeHeight, awayHeight), middleHeight) + 16
          : homeHeight + awayHeight + middleHeight + 16);
    });
    final carouselHeight = mode == TipsCardMode.standard
        ? math.max(standardExtent - 8, math.max(panelHeight, matchupHeight))
        : math.max(panelHeight, mode == TipsCardMode.wide ? matchupHeight : 0.0);
    return TipsCardLayout(
      carouselViewportFraction: fraction,
      mode: mode, choices: arrangement,
      cardExtent: carouselHeight + 8 +
          (mode == TipsCardMode.stacked ? matchupHeight : 0),
      carouselHeight: carouselHeight, matchupWidth: matchupWidth,
      matchupHeight: matchupHeight,
      standardMinWidth: standardMin, wideMinWidth: wideMin,
    );
  }
}
