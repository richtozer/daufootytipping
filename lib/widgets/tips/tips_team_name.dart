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
    double nameWidth(TipsTeamDisplay team) {
      final painter = TextPainter(
        text: team.text(theme),
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
      homeNameWidth: nameWidth(home),
      awayNameWidth: nameWidth(away),
    );
    final mark = editable
        ? Icon(Icons.edit, size: TipsCardLayout.scaledIconSize(scaler, theme))
        : const Text('V');
    Widget line(
      TipsTeamDisplay team, {
      required bool markBefore,
      required bool markAfter,
    }) {
      return Padding(
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
            Flexible(
              child: TipsTeamName(
                team.text(
                  theme,
                  highlight: appSelectionColor(context),
                  onHighlight: appOnSelectionColor(context),
                ),
              ),
            ),
            if (markAfter) ...[const SizedBox(width: kStackedMarkGap), mark],
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: line(home, markBefore: false, markAfter: markOnHome)),
        Flexible(child: line(away, markBefore: !markOnHome, markAfter: false)),
      ],
    );
  }
}
