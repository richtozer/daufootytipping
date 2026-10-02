import 'dart:async';
import 'dart:math' as math;
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'adaptive_tips_samples.dart';

/// Temporary entry point: flutter run -d web-server -t lib/dev/adaptive_tips_prototype.dart
/// The normal application entry point does not import this harness.
void main() => runApp(const AdaptiveTipsPrototypeApp());

class AdaptiveTipsPrototypeApp extends StatelessWidget {
  const AdaptiveTipsPrototypeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Adaptive Tips prototype', debugShowCheckedModeBanner: false,
    theme: FlexThemeData.light(scheme: FlexScheme.green, fontFamily: appFontFamily),
    home: const AdaptiveTipsPrototype(),
  );
}

class AdaptiveTipsPrototype extends StatefulWidget {
  const AdaptiveTipsPrototype({super.key});
  @override
  State<AdaptiveTipsPrototype> createState() => _AdaptiveTipsPrototypeState();
}

class _AdaptiveTipsPrototypeState extends State<AdaptiveTipsPrototype> {
  double _width = 390;
  double _height = 740;
  double _scale = 1;
  bool _percent = false;
  bool _loading = false;
  bool _longNames = false;
  bool _kickoff = false;
  final _scroll = ScrollController();
  final _selected = <String, GameResult>{};
  final _saving = <String>{};
  final _panels = <String, TipsPanel>{};
  final _timers = <Timer>[];
  TipsCardLayout? _previousLayout;
  double _previousHeader = 0;
  int _geometryRevision = 0;

  @override
  void dispose() {
    for (final timer in _timers) { timer.cancel(); }
    _scroll.dispose();
    super.dispose();
  }

  double _gameTop(int index, double extent, double header) =>
      (index ~/ 4) * (4 * extent + header) + header + (index % 4) * extent;

  void _restoreGeometry(TipsCardLayout next, double header, int count) {
    final previous = _previousLayout;
    if (previous != null && _scroll.hasClients &&
        (previous.cardExtent != next.cardExtent || _previousHeader != header)) {
      final visibleTop = _scroll.offset + _previousHeader;
      var index = 0;
      while (index < count - 1 &&
          _gameTop(index, previous.cardExtent, _previousHeader) + previous.cardExtent <= visibleTop) {
        index++;
      }
      final relative = _gameTop(index, previous.cardExtent, _previousHeader) - visibleTop;
      final target = _gameTop(index, next.cardExtent, header) - header - relative;
      final revision = ++_geometryRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || revision != _geometryRevision) return;
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      });
    }
    _previousLayout = next;
    _previousHeader = header;
  }

  void _jumpToGame(int index) {
    final layout = _previousLayout;
    if (layout == null || !_scroll.hasClients) return;
    _scroll.jumpTo((_gameTop(index, layout.cardExtent, _previousHeader) - _previousHeader)
        .clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _tip(String id, GameResult result) {
    setState(() { _selected[id] = result; _saving.add(id); });
    _timers.add(Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _saving.remove(id));
    }));
  }

  @override
  Widget build(BuildContext context) {
    final cards = tipsSamples(selections: _selected, saving: _saving,
      loading: _loading, longNames: _longNames, kickoff: _kickoff);
    return Scaffold(
      appBar: AppBar(title: const Text('Adaptive Tips · sample data')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(
          spacing: 12, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 230, child: Row(children: [
              Text('Width ${_width.round()}'),
              Expanded(child: Slider(key: const Key('width'), min: 240, max: 1600,
                value: _width, onChanged: (v) => setState(() => _width = v))),
            ])),
            SizedBox(width: 210, child: Row(children: [
              Text('Text ${_scale.toStringAsFixed(1)}×'),
              Expanded(child: Slider(key: const Key('text-scale'), min: 1, max: 3.2,
                divisions: 22, value: _scale, onChanged: (v) => setState(() => _scale = v))),
            ])),
            TextButton.icon(key: const Key('rotate'), icon: const Icon(Icons.screen_rotation),
              label: const Text('Rotate'), onPressed: () => setState(() {
                if (_width < 700) { _width = 844; _height = 390; }
                else { _width = 390; _height = 740; }
              })),
            FilterChip(label: const Text('Percentage tipped'), selected: _percent,
              onSelected: (value) => setState(() => _percent = value)),
            FilterChip(label: const Text('Loading'), selected: _loading,
              onSelected: (value) => setState(() => _loading = value)),
            FilterChip(label: const Text('Long names'), selected: _longNames,
              onSelected: (value) => setState(() => _longNames = value)),
            FilterChip(label: const Text('Simulate kickoff'), selected: _kickoff,
              onSelected: (value) => setState(() => _kickoff = value)),
            for (final (label, index) in [('Round 24', 0), ('Round 25', 4), ('Round 27', 8), ('First tippable', 10)])
              TextButton(onPressed: () => _jumpToGame(index), child: Text(label)),
          ],
        )),
        Expanded(child: LayoutBuilder(builder: (context, bounds) => Center(
          child: SizedBox(width: math.min(_width, bounds.maxWidth),
            height: math.min(_height, bounds.maxHeight),
            child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_scale)),
              child: Builder(builder: (context) {
                final width = math.min(_width, bounds.maxWidth);
                final layout = TipsCardLayout.measure(width: width,
                  textScaler: MediaQuery.textScalerOf(context), textTheme: Theme.of(context).textTheme,
                  textDirection: Directionality.of(context),
                  cards: [for (final card in cards) card.content(Theme.of(context).textTheme)],
                  percentStats: _percent,
                );
                final headerHeight = 80.0 * _scale;
                _restoreGeometry(layout, headerHeight, cards.length);
                return Column(children: [
                  // Harness diagnostics keep their own normal text size.
                  MediaQuery.withNoTextScaling(child: Padding(padding: const EdgeInsets.all(4),
                    child: Text('${layout.mode.name} · ${layout.choices.name} · '
                      '${width.round()} px · card ${layout.cardExtent.ceil()} px\n'
                      'Measured minimums: standard ${layout.standardMinWidth.ceil()}, '
                      'wide ${layout.wideMinWidth.ceil()}', textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)))),
                  Expanded(child: RepaintBoundary(key: const Key('sample-list-visual'),
                    child: ColoredBox(color: const Color(0xffd9e5d7),
                    child: CustomScrollView(key: const Key('sample-list'), controller: _scroll,
                      slivers: [for (var round = 0; round < 3; round++)
                        SliverMainAxisGroup(slivers: [
                          SliverPersistentHeader(pinned: true, delegate: _SampleHeader(
                            height: headerHeight, round: [24, 25, 27][round],
                            league: round == 0 ? 'AFL' : 'NRL')),
                          SliverFixedExtentList(itemExtent: layout.cardExtent,
                            delegate: SliverChildBuilderDelegate((context, index) {
                              final card = cards[round * 4 + index];
                              return AdaptiveTipsCard(key: ValueKey(card.id), data: card,
                                layout: layout, percentStats: _percent,
                                activePanel: _panels[card.id] ??
                                    (card.hasResult ? TipsPanel.result : TipsPanel.tips),
                                onPanelChanged: (panel) => _panels[card.id] = panel,
                                onTip: (result) => _tip(card.id, result),
                                onMatchup: () => showDialog<void>(context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('${card.home.name} v ${card.away.name}'),
                                    content: const Text('Sample interaction only. Live score editing and team comparison remain owned by the live application.'),
                                    actions: [TextButton(onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'))],
                                  )),
                              );
                            }, childCount: 4)),
                        ]),
                      ],
                    ),
                  ))),
                ]);
              }),
            ),
          ),
        ))),
      ]),
    );
  }
}

class _SampleHeader extends SliverPersistentHeaderDelegate {
  _SampleHeader({required this.height, required this.round, required this.league});
  final double height;
  final int round;
  final String league;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  bool shouldRebuild(covariant _SampleHeader oldDelegate) =>
      height != oldDelegate.height || round != oldDelegate.round || league != oldDelegate.league;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox.expand(child: Card(color: const Color(0xff34453b), child: Padding(
        padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Round\n'),
            TextSpan(text: '$round', style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: Colors.white)),
          ]), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white))),
          Expanded(flex: 2, child: Text('Points: 7 / 12\nMargins: 1 / 5\nRank: 7 ↑ 21',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white))),
          Expanded(child: Text(league, textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.lightGreenAccent))),
        ]),
      )));
}
