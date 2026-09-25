import 'dart:async';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tips_card_layout.dart';
import 'tips_choice_panel.dart';

enum TipsPanel { tips, result, info, percentages }

enum TipsStatus { upcoming, today, live, interim, finalScore }

/// Presentation values only: the live adapter will retain ownership of saving,
/// permissions, score calculation and Firebase subscriptions.
class TipsTeamDisplay {
  const TipsTeamDisplay(
    this.name,
    this.logo, {
    this.score,
    this.rank,
    this.winner = false,
    this.heroTag,
  });
  final String name;
  final String logo;
  final int? score;
  final String? rank;
  final bool winner;

  /// Supplied by the live adapter so the ladder transition keeps its animation.
  /// Must be unique within the route: one tag per team per screen.
  final String? heroTag;

  TextSpan text(TextTheme theme, {bool rankAfterName = false}) => TextSpan(
    style: theme.titleMedium,
    children: [
      if (rank != null && !rankAfterName)
        TextSpan(text: '$rank ', style: theme.labelSmall),
      TextSpan(text: name),
      if (rank != null && rankAfterName)
        TextSpan(text: ' $rank', style: theme.labelSmall),
      if (score != null)
        TextSpan(
          text: ' $score',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            backgroundColor: winner ? Colors.lightGreen.shade200 : null,
          ),
        ),
    ],
  );
}

class TipsCardDisplay {
  const TipsCardDisplay({
    required this.id,
    required this.home,
    required this.away,
    required this.league,
    required this.info,
    this.status = TipsStatus.upcoming,
    this.selected,
    this.result,
    this.points = '? / ?',
    this.average = '? / ?',
    this.percentages,
    this.loading = false,
    this.saving = false,
    this.canTip = true,
  });
  final String id;
  final TipsTeamDisplay home;
  final TipsTeamDisplay away;
  final League league;
  final String info;
  final TipsStatus status;
  final GameResult? selected;
  final GameResult? result;
  final String points;
  final String average;
  final List<double>? percentages;
  final bool loading;
  final bool saving;
  final bool canTip;

  String label(GameResult value) =>
      league == League.afl ? value.afl : value.nrl;
  static const options = [
    GameResult.a,
    GameResult.b,
    GameResult.c,
    GameResult.d,
    GameResult.e,
  ];
  List<String> get choiceLabels => options.map(label).toList();
  bool get hasResult =>
      status == TipsStatus.live ||
      status == TipsStatus.interim ||
      status == TipsStatus.finalScore;
  List<String> get resultLines =>
      [
        'Result: ${label(result ?? GameResult.z)}',
        'Your tip: ${selected == null ? 'Not tipped' : label(selected!)}',
        'Your Points: $points',
        'Avg Points: $average',
      ].map((text) {
        // Keep each value together so wrapping prefers the space after the colon.
        // These same strings are measured when reserving the panel's height.
        final valueStart = text.indexOf(':') + 2;
        return text.substring(0, valueStart) +
            text.substring(valueStart).replaceAll(' ', '\u00a0');
      }).toList();

  List<TextSpan> resultSpans(TextTheme theme) => resultLines.map((text) {
    final split = text.indexOf(':') + 1;
    return TextSpan(
      style: theme.bodyMedium,
      children: [
        TextSpan(
          text: text.substring(0, split),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        TextSpan(text: text.substring(split)),
      ],
    );
  }).toList();

  TipsCardContent content(TextTheme theme) => TipsCardContent(
    home: home.text(theme),
    away: away.text(theme),
    info: info,
    results: hasResult ? resultSpans(theme) : [],
    choiceLabels: choiceLabels,
    editable: status == TipsStatus.live || status == TipsStatus.interim,
  );
}

/// Reusable presentation component, exercised in the prototype before the live
/// Tips/Stats adapters adopt it. It never reads or writes application services.
class AdaptiveTipsCard extends StatelessWidget {
  const AdaptiveTipsCard({
    super.key,
    required this.data,
    required this.layout,
    required this.activePanel,
    required this.onPanelChanged,
    this.percentStats = false,
    this.onTip,
    this.onMatchup,
  });
  final TipsCardDisplay data;
  final TipsCardLayout layout;
  final TipsPanel activePanel;
  final ValueChanged<TipsPanel> onPanelChanged;
  final bool percentStats;
  final ValueChanged<GameResult>? onTip;
  final VoidCallback? onMatchup;

  @override
  Widget build(BuildContext context) {
    final panels = percentStats
        ? [TipsPanel.percentages]
        : [
            if (data.hasResult) TipsPanel.result,
            TipsPanel.tips,
            TipsPanel.info,
          ];
    final page = panels.contains(activePanel) ? panels.indexOf(activePanel) : 0;
    final carousel = _TipsCarousel(
      // Panel-set changes recreate the page view at the same semantic panel.
      key: ValueKey('${data.id}:${panels.join(',')}'),
      layout: layout,
      initialPage: page,
      onPanelChanged: (index) => onPanelChanged(panels[index]),
      items: [
        for (final panel in panels)
          Semantics(
            container: true,
            label: '${data.home.name} versus ${data.away.name}, ${panel.name}',
            child: switch (panel) {
              TipsPanel.tips => _choices(context, false),
              TipsPanel.percentages => _choices(context, true),
              TipsPanel.info => _info(context),
              TipsPanel.result => _result(context),
            },
          ),
      ],
    );
    final matchup = _matchup(context);
    Widget card = Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Colors.white70,
      surfaceTintColor: League.nrl.colour,
      child: layout.mode == TipsCardMode.stacked
          ? Column(
              children: [
                SizedBox(height: layout.matchupHeight, child: matchup),
                carousel,
              ],
            )
          : Row(
              children: [
                SizedBox(width: layout.matchupWidth, child: matchup),
                Expanded(child: carousel),
              ],
            ),
    );
    final (message, color) = switch (data.status) {
      TipsStatus.today => ('Game today', Colors.orange),
      TipsStatus.live => ('Live', League.afl.colour),
      TipsStatus.interim => ('* Interim', Colors.grey.shade600),
      _ => ('', Colors.transparent),
    };
    if (message.isNotEmpty) {
      // Wide cards put actions near the corner. A separate status line avoids
      // obscuring their hit areas while standard keeps its familiar ribbon.
      card = layout.mode == TipsCardMode.wide
          ? Stack(
              children: [
                card,
                Positioned(
                  top: 4,
                  right: 8,
                  child: IgnorePointer(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: color),
                    ),
                  ),
                ),
              ],
            )
          : Banner(
              message: message,
              color: color,
              textStyle:
                  const Banner(
                    message: '',
                    location: BannerLocation.topEnd,
                  ).textStyle.copyWith(
                    fontFamily: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.fontFamily,
                  ),
              location: BannerLocation.topEnd,
              child: card,
            );
    }
    return SizedBox(height: layout.cardExtent, child: card);
  }

  Widget _matchup(BuildContext context) {
    final editable =
        data.status == TipsStatus.live || data.status == TipsStatus.interim;
    final logoSize = TipsCardLayout.teamLogoSize(
      MediaQuery.textScalerOf(context),
      Theme.of(context).textTheme,
    );
    Widget logo(TipsTeamDisplay team) {
      final picture = SvgPicture.asset(
        team.logo,
        width: logoSize,
        height: logoSize,
      );
      final tag = team.heroTag;
      return tag == null ? picture : Hero(tag: tag, child: picture);
    }

    Widget team(TipsTeamDisplay team, {bool rankAfterName = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text.rich(
        team.text(Theme.of(context).textTheme, rankAfterName: rankAfterName),
        textAlign: TextAlign.center,
      ),
    );
    final middle = editable
        ? Icon(
            Icons.edit,
            size: TipsCardLayout.scaledIconSize(
              MediaQuery.textScalerOf(context),
              Theme.of(context).textTheme,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [logo(data.home), const Text(' V '), logo(data.away)],
          );
    return Semantics(
      button: onMatchup != null,
      label: editable ? 'Edit live score' : 'Compare teams',
      child: InkWell(
        onTap: onMatchup,
        child: Center(
          child: layout.mode == TipsCardMode.wide
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: team(data.home)),
                    middle,
                    Flexible(
                      child: team(
                        data.away,
                        rankAfterName:
                            data.status == TipsStatus.upcoming ||
                            data.status == TipsStatus.today,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [team(data.home), middle, team(data.away)],
                ),
        ),
      ),
    );
  }

  Widget _choices(BuildContext context, bool percentages) {
    final trophySize = TipsCardLayout.scaledIconSize(
      MediaQuery.textScalerOf(context),
      Theme.of(context).textTheme,
      size: 18,
    );
    const options = TipsCardDisplay.options;
    return Stack(
      children: [
        TipsChoicePanel(
          arrangement: layout.choices,
          children: [
            for (var index = 0; index < options.length; index++)
              ChoiceChip.elevated(
                label: percentages
                    ? SizedBox(
                        width: _percentageWidth(context),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (data.loading)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Text(
                                data.percentages == null
                                    // Unknown, not empty: the live tab has
                                    // always marked a missing percentage.
                                    ? '?'
                                    : '${data.percentages![index].toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            const SizedBox(height: 2),
                            Text(
                              data.label(options[index]),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : Text(
                        data.label(options[index]),
                        textAlign: TextAlign.center,
                      ),
                avatar: percentages && data.result == options[index]
                    ? Icon(
                        Icons.emoji_events,
                        color: Colors.black,
                        size: trophySize,
                      )
                    : null,
                avatarBoxConstraints: BoxConstraints.tightFor(
                  width: trophySize,
                  height: trophySize,
                ),
                tooltip: data.league == League.afl
                    ? options[index].aflTooltip
                    : options[index].nrlTooltip,
                showCheckmark: false,
                materialTapTargetSize: layout.mode == TipsCardMode.standard
                    ? MaterialTapTargetSize.shrinkWrap
                    : MaterialTapTargetSize.padded,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.zero,
                selectedColor: Colors.lightGreen[500],
                selected: data.selected == options[index],
                onSelected:
                    percentages || data.saving || !data.canTip || onTip == null
                    ? null
                    : (_) => onTip?.call(options[index]),
              ),
          ],
        ),
        if (data.saving)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _percentageWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: '100.0%',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    var width = painter.width;
    for (final option in [GameResult.a, GameResult.e]) {
      painter.text = TextSpan(
        text: data.label(option),
        style: Theme.of(context).textTheme.labelSmall,
      );
      painter.layout();
      if (painter.width > width) width = painter.width;
    }
    painter.dispose();
    return width;
  }

  Widget _info(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final small = theme.labelSmall!;
            final target = theme.bodyMedium!;
            final painter = TextPainter(
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              textAlign: TextAlign.center,
            );
            bool fits(TextStyle style) {
              painter.text = TextSpan(text: data.info, style: style);
              painter.layout(maxWidth: bounds.maxWidth);
              return painter.height <= bounds.maxHeight;
            }

            var style = target;
            if (!fits(target)) {
              var low = 0.0;
              var high = 1.0;
              // Fill the existing space, without changing shared card heights or
              // reducing text below its previous size. Respect the user's scaler.
              for (var step = 0; step < 12; step++) {
                final middle = (low + high) / 2;
                if (fits(TextStyle.lerp(small, target, middle)!)) {
                  low = middle;
                } else {
                  high = middle;
                }
              }
              style = TextStyle.lerp(small, target, low)!;
            }
            painter.dispose();
            return Center(
              child: Text(data.info, style: style, textAlign: TextAlign.center),
            );
          },
        ),
      ),
    );
  }

  Widget _result(BuildContext context) {
    final lines = data.resultSpans(Theme.of(context).textTheme);
    Widget line(TextSpan text) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Text.rich(text, textAlign: TextAlign.center),
      );
    }

    return Card(
      child: layout.mode == TipsCardMode.wide
          ? Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [for (final text in lines) line(text)],
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final text in lines)
                  SizedBox(width: double.infinity, child: line(text)),
              ],
            ),
    );
  }
}

/// Owns the carousel controller so it survives the rebuilds the live view
/// models trigger. A controller built inside `build` is replaced on every
/// score or tip update, leaving keyboard navigation driving a detached one.
class _TipsCarousel extends StatefulWidget {
  const _TipsCarousel({
    super.key,
    required this.layout,
    required this.initialPage,
    required this.onPanelChanged,
    required this.items,
  });

  final TipsCardLayout layout;
  final int initialPage;
  final ValueChanged<int> onPanelChanged;
  final List<Widget> items;

  @override
  State<_TipsCarousel> createState() => _TipsCarouselState();
}

class _TipsCarouselState extends State<_TipsCarousel> {
  final CarouselSliderController _controller = CarouselSliderController();

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || widget.items.length < 2) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          unawaited(_controller.nextPage());
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          unawaited(_controller.previousPage());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CarouselSlider(
        carouselController: _controller,
        options: CarouselOptions(
          height: widget.layout.carouselHeight,
          viewportFraction: widget.layout.carouselViewportFraction,
          initialPage: widget.initialPage,
          enlargeFactor: 1,
          enlargeCenterPage: true,
          enlargeStrategy: CenterPageEnlargeStrategy.zoom,
          enableInfiniteScroll: false,
          onPageChanged: (index, reason) => widget.onPanelChanged(index),
        ),
        items: widget.items,
      ),
    );
  }
}
