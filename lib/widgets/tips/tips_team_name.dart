import 'dart:math' as math;

import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/material.dart';

/// A team's name on a tips card, in as many lines as the card has room for.
///
/// Cards are sized for the names of the teams that play the season, so those
/// always fit. A finals placeholder such as "Highest-ranked WF Winner" can need
/// more lines than that; it ends in an ellipsis where the height runs out
/// rather than overflowing the card.
class TipsTeamName extends StatelessWidget {
  const TipsTeamName(this.text, {super.key});

  /// The name, with any rank or score badge, as the card styles it.
  final TextSpan text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Text.rich(
        text,
        textAlign: TextAlign.center,
        maxLines: _linesThatFit(context, constraints),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Null, for no limit, when the height is unbounded or every line fits.
  int? _linesThatFit(BuildContext context, BoxConstraints constraints) {
    if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
      return null;
    }
    final painter = TextPainter(
      text: text,
      textAlign: TextAlign.center,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    );
    setBadgeDimensions(painter);
    painter.layout(maxWidth: constraints.maxWidth);
    final lines = painter.computeLineMetrics();
    painter.dispose();
    var height = 0.0;
    for (var index = 0; index < lines.length; index++) {
      height += lines[index].height;
      if (height > constraints.maxHeight + 0.5) {
        return index == 0 ? 1 : index;
      }
    }
    return null;
  }
}

/// One of the two names in a [TipsNamesColumn]: what it shows, and the text
/// that sets how much height it needs.
class TipsNameLine {
  const TipsNameLine({
    required this.text,
    required this.child,
    this.besideWidth = 0,
    this.minHeight = 0,
  });

  /// A name alone on its line, with the card's 4 either side of it.
  TipsNameLine.padded(this.text)
    : besideWidth = 8,
      minHeight = 0,
      child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TipsTeamName(text),
      );

  /// The name as the card styles it, measured to find the height it needs.
  final TextSpan text;

  /// The line itself: the name, and anything beside it.
  final Widget child;

  /// Width the line gives to other things beside the name: padding, a logo,
  /// the "V".
  final double besideWidth;

  /// Height the line needs whatever the name, such as a logo's, when deciding
  /// which name needs less.
  final double minHeight;
}

/// The two names of a matchup, one above the other, with [between] (the logos
/// and "V") between them if given.
///
/// The name that needs less height at this width gets all it needs, and the
/// other gets the rest. Cards are measured to hold both of the season's teams'
/// names, so a real name is never cut short; only a name past that, a finals
/// placeholder, is, beside a real name or another placeholder. Sharing the
/// height in proportion to need instead gave a one-line name less than a line
/// beside a four-line placeholder.
class TipsNamesColumn extends StatelessWidget {
  const TipsNamesColumn({
    super.key,
    required this.home,
    required this.away,
    this.between,
  });

  final TipsNameLine home;
  final TipsNameLine away;
  final Widget? between;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        double need(TipsNameLine line) {
          final painter = TextPainter(
            text: line.text,
            textAlign: TextAlign.center,
            textScaler: scaler,
            textDirection: direction,
          );
          setBadgeDimensions(painter);
          painter.layout(
            maxWidth: math.max(1.0, constraints.maxWidth - line.besideWidth),
          );
          final height = math.max(painter.height, line.minHeight);
          painter.dispose();
          return height;
        }

        final homeNeed = need(home);
        final awayNeed = need(away);
        final same = (homeNeed - awayNeed).abs() < 0.5;
        Widget fit(TipsNameLine line, {required bool shorter}) =>
            shorter && !same ? line.child : Flexible(child: line.child);
        final between = this.between;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            fit(home, shorter: homeNeed < awayNeed),
            ?between,
            fit(away, shorter: awayNeed < homeNeed),
          ],
        );
      },
    );
  }
}

/// Two lines, each a logo beside its team's name, with the "V" on the shorter
/// name's line rather than a row of its own. A live card has no logos and its
/// edit pencil takes the "V"'s place.
class TipsStackedTeams extends StatelessWidget {
  const TipsStackedTeams({
    super.key,
    required this.home,
    required this.away,
    required this.editable,
    required this.logo,
  });

  final TipsTeamDisplay home;
  final TipsTeamDisplay away;

  /// Whether the game is live, so the edit pencil replaces the logos and "V".
  final bool editable;

  /// Builds a team's logo, with the card's hero tag.
  final Widget Function(TipsTeamDisplay team) logo;

  @override
  Widget build(BuildContext context) {
    final theme = appPanelTextTheme(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double textWidth(InlineSpan text) {
      final painter = TextPainter(
        text: text,
        textScaler: scaler,
        textDirection: direction,
      );
      setBadgeDimensions(painter);
      painter.layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final markOnHome = TipsCardLayout.markOnHomeLine(
      homeNameWidth: textWidth(home.text(theme)),
      awayNameWidth: textWidth(away.text(theme)),
    );
    final iconSize = TipsCardLayout.scaledIconSize(scaler, theme);
    final mark = editable ? Icon(Icons.edit, size: iconSize) : const Text('V');
    final markWidth =
        (editable
            ? iconSize
            : textWidth(
                TextSpan(text: 'V', style: DefaultTextStyle.of(context).style),
              )) +
        kStackedMarkGap;
    final logoSize = TipsCardLayout.teamLogoSize(
      scaler,
      Theme.of(context).textTheme,
    );
    TipsNameLine line(
      TipsTeamDisplay team, {
      required bool markBefore,
      required bool markAfter,
    }) {
      final text = team.text(
        theme,
        highlight: appSelectionColor(context),
        onHighlight: appOnSelectionColor(context),
      );
      return TipsNameLine(
        text: text,
        besideWidth:
            8 +
            (editable ? 0 : logoSize + kStackedLogoGap) +
            (markBefore || markAfter ? markWidth : 0),
        minHeight: editable ? 0 : logoSize,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (markBefore) ...[mark, const SizedBox(width: kStackedMarkGap)],
              if (!editable) ...[
                logo(team),
                const SizedBox(width: kStackedLogoGap),
              ],
              Flexible(child: TipsTeamName(text)),
              if (markAfter) ...[const SizedBox(width: kStackedMarkGap), mark],
            ],
          ),
        ),
      );
    }

    return TipsNamesColumn(
      home: line(home, markBefore: false, markAfter: markOnHome),
      away: line(away, markBefore: !markOnHome, markAfter: false),
    );
  }
}
