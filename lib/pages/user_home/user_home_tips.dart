import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_geometry.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/services.dart';
import 'package:watch_it/watch_it.dart';

typedef _TipsScrollTarget = ({double offset, int sectionIndex});

class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  TipsTabState createState() => TipsTabState();
}

/// The tips list, built once its comp's games are in their rounds and the
/// tipper's tips have loaded, and opened at where the tipper belongs.
///
/// Every extent in the list is fixed, so the list's layout is known before it
/// is laid out: it opens at its target on its first frame, and a relayout --
/// cards remeasured, games arriving -- keeps the reader's game in place in the
/// frame that makes it.
class TipsTabState extends State<TipsTab> {
  final DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();
  final FocusNode focusNode = FocusNode();

  ScrollController? _scrollController;

  /// What the list was placed for: the comp, the tipper's tips and the last
  /// round completed. When it changes, a new list opens at the new target.
  String? _placementKey;

  /// The sections and scroll extent the list was last built with.
  List<TipsLeagueSection> _laidOutSections = const [];
  double _laidOutMaxScrollExtent = 0;

  /// Whether a finger is moving the list, which a correction leaves alone.
  bool _dragging = false;
  TipsCardLayout? _cardLayout;
  String? _cardLayoutKey;

  /// The list's controller, once it has been placed.
  ScrollController? get scrollController => _scrollController;

  /// The measured row height every scroll offset in this tab is built from.
  /// Exposed so navigation tests assert against the same value the list uses
  /// rather than a constant that no longer describes the row.
  double get cardExtent => _cardLayout?.cardExtent ?? Game.gameCardHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: daucompsViewModel,
      builder: (context, child) {
        final selectedComp = daucompsViewModel.selectedDAUComp;
        final tipsLoaded =
            daucompsViewModel
                .selectedTipperTipsViewModel
                ?.isInitialLoadComplete ??
            false;
        // Before the games are in their rounds every round reads as empty,
        // and a list placed then would be placed against games it does not
        // have.
        if (selectedComp == null ||
            !daucompsViewModel.gamesLinked ||
            !tipsLoaded) {
          return Center(
            child: CircularProgressIndicator(color: League.afl.colour),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) =>
              _buildList(context, constraints, selectedComp),
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    BoxConstraints constraints,
    DAUComp selectedComp,
  ) {
    final layout = _syncCardLayout(context, constraints.maxWidth, selectedComp);
    final sections = buildTipsLeagueSections(
      selectedComp: selectedComp,
      cardExtent: layout.cardExtent,
      headerExtent: layout.headerExtent,
    );
    final topInset = MediaQuery.paddingOf(context).top;
    // Every offset here is measured from just below the status bar: the
    // spacer under it moves the list down by the inset and the line its
    // headers pin to down by the same, so the two cancel. Only the room the
    // list has to show itself in is the inset less.
    final maxScrollExtent = tipsMaxScrollExtent(
      sections: sections,
      leadingExtent: WelcomeHeader.height,
      footerExtent: EndFooter.extentIn(context),
      viewportExtent: constraints.maxHeight - topInset,
    );
    final controller = _place(selectedComp, sections, maxScrollExtent);
    final sectionTops = [
      for (var index = 0; index < sections.length; index++)
        tipsSectionHeaderTop(
          sections: sections,
          sectionIndex: index,
          leadingExtent: WelcomeHeader.height,
        ),
    ];
    _laidOutSections = sections;
    _laidOutMaxScrollExtent = maxScrollExtent;
    final currentTipper = di<TippersViewModel>().selectedTipper;

    return KeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Theme(
        data: myTheme,
        child: NotificationListener<ScrollNotification>(
          onNotification: _trackDrag,
          child: CustomScrollView(
            key: ValueKey(_placementKey),
            controller: controller,
            slivers: [
              // The status bar's height, pinned and see-through: the cards
              // scroll up under the status bar, and every round's header
              // pins below it. Taps there do not reach a card that has
              // scrolled past; a drag from there still scrolls.
              PinnedHeaderSliver(
                child: AbsorbPointer(child: SizedBox(height: topInset)),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: WelcomeHeader.height,
                  child: WelcomeHeader(
                    daucompsViewmodelConsumer: daucompsViewModel,
                  ),
                ),
              ),
              for (final (index, section) in sections.indexed)
                buildRoundLeagueSection(
                  section: section,
                  dauCompsViewModel: daucompsViewModel,
                  currentTipper: currentTipper,
                  isPercentStatsPage: false,
                  layout: layout,
                  pinnedIn: (
                    controller: controller,
                    sectionTop: sectionTops[index],
                  ),
                ),
              const SliverToBoxAdapter(child: EndFooter()),
            ],
          ),
        ),
      ),
    );
  }

  /// The controller for a list laid out as [sections].
  ///
  /// A list placed for something else gets a new controller that opens at
  /// the target. Otherwise, when the layout has moved under the reader, the
  /// offset moves with it before the list is laid out, so the frame that
  /// changes the layout already shows the reader's game where it was.
  ScrollController _place(
    DAUComp selectedComp,
    List<TipsLeagueSection> sections,
    double maxScrollExtent,
  ) {
    final placementKey =
        '${selectedComp.dbkey}:'
        '${identityHashCode(daucompsViewModel.selectedTipperTipsViewModel)}:'
        '${selectedComp.latestsCompletedRoundNumber()}';
    final current = _scrollController;
    if (current == null || placementKey != _placementKey) {
      final target = _defaultScrollTarget(selectedComp, sections).offset;
      final next = ScrollController(
        initialScrollOffset: target.clamp(0.0, maxScrollExtent),
        // The list's position is where it was placed, not one remembered from
        // the list it replaces.
        keepScrollOffset: false,
      );
      _placementKey = placementKey;
      _scrollController = next;
      if (current == null) {
        // The first list this tab has placed is the one startup opens on.
        StartupProfiling.instant('startup.tips_placed');
        StartupProfiling.end('startup.tips_page_stable');
        return next;
      }
      // The list it replaces lets go of it as this frame is built.
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
      return next;
    }

    final moved =
        !sameTipsLayout(_laidOutSections, sections) ||
        (maxScrollExtent - _laidOutMaxScrollExtent).abs() > 0.5;
    if (!moved || !current.hasClients) {
      return current;
    }
    final position = current.position;
    // A reader at the end of a list that scrolled stays at its end.
    final atEnd =
        _laidOutMaxScrollExtent > 0 &&
        position.pixels >= _laidOutMaxScrollExtent - 0.5;
    final offset = atEnd
        ? maxScrollExtent
        : anchoredTipsScrollOffset(
                before: _laidOutSections,
                after: sections,
                leadingExtent: WelcomeHeader.height,
                scrollOffset: position.pixels,
              ) ??
              _defaultScrollTarget(selectedComp, sections).offset;
    position.correctPixels(offset.clamp(0.0, maxScrollExtent));
    _stopAfterCorrection(position);
    return current;
  }

  /// A running animation or fling carries on in the old layout's offsets and
  /// would take the reader straight back out of place on its next tick, so it
  /// stops where the correction put them. A finger on the list keeps it. Done
  /// after the frame, not during this build: stopping one sends scroll
  /// notifications.
  void _stopAfterCorrection(ScrollPosition position) {
    if (!position.isScrollingNotifier.value || _dragging) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (position.isScrollingNotifier.value && !_dragging) {
        // Releasing a hold settles the list where it is.
        position.hold(() {}).cancel();
      }
    });
  }

  /// Follows whether a finger is moving the list.
  bool _trackDrag(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _dragging = notification.dragDetails != null;
    } else if (notification is ScrollEndNotification) {
      _dragging = false;
    }
    return false;
  }

  /// Each tap of the selected TIPS tab moves to the next of: where startup
  /// put the reader, the current round's NRL, then its AFL.
  void scrollToNextNavigationPosition() {
    final selectedComp = daucompsViewModel.selectedDAUComp;
    final controller = _scrollController;
    final sections = _laidOutSections;
    if (selectedComp == null ||
        controller == null ||
        !controller.hasClients ||
        sections.isEmpty) {
      return;
    }

    final defaultTarget = _defaultScrollTarget(selectedComp, sections);
    final targetRoundIndex = sections[defaultTarget.sectionIndex].roundIndex;
    final leagueTargets = <_TipsScrollTarget>[
      for (final (sectionIndex, section) in sections.indexed)
        if (section.roundIndex == targetRoundIndex)
          (
            offset: tipsSectionHeaderTop(
              sections: sections,
              sectionIndex: sectionIndex,
              leadingExtent: WelcomeHeader.height,
            ),
            sectionIndex: sectionIndex,
          ),
    ];
    final defaultMatchesLeagueTarget = leagueTargets.any(
      (target) => (target.offset - defaultTarget.offset).abs() <= 8,
    );
    final cycleTargets = defaultMatchesLeagueTarget
        ? leagueTargets
        : [defaultTarget, ...leagueTargets];

    final maxScrollExtent = controller.position.maxScrollExtent;
    final currentTargetIndex = cycleTargets.indexWhere((target) {
      final reachableOffset = target.offset.clamp(0.0, maxScrollExtent);
      return (controller.offset - reachableOffset).abs() <= 8;
    });
    final nextTarget = currentTargetIndex == -1
        ? cycleTargets.first
        : cycleTargets[(currentTargetIndex + 1) % cycleTargets.length];
    controller.jumpTo(nextTarget.offset.clamp(0.0, maxScrollExtent));
  }

  _TipsScrollTarget _defaultScrollTarget(
    DAUComp selectedComp,
    List<TipsLeagueSection> sections,
  ) {
    final isCompComplete =
        selectedComp.latestsCompletedRoundNumber() >=
            selectedComp.daurounds.length &&
        sections.isNotEmpty;
    if (isCompComplete) {
      return (
        offset: tipsEndFooterOffset(
          sections: sections,
          leadingExtent: WelcomeHeader.height,
        ),
        sectionIndex: sections.length - 1,
      );
    }

    final targetSectionIndex = targetStartupSectionIndex(
      selectedComp,
      sections,
    );
    final tipsViewModel = daucompsViewModel.selectedTipperTipsViewModel;
    final tipper = di<TippersViewModel>().selectedTipper;
    final refinement = sections.isEmpty || tipsViewModel == null
        ? 0.0
        : intraRoundScrollRefinement(
            selectedComp: selectedComp,
            sections: sections,
            targetSectionIndex: targetSectionIndex,
            firstUntippedGameIndex: (games) =>
                tipsViewModel.firstUntippedGameIndex(games, tipper),
            cardExtent: cardExtent,
          );
    // Round 1 opens on the welcome until a game in it starts, unless a later
    // game in it is the one to tip. A live game is somewhere to go.
    final roundUnderway =
        sections.isNotEmpty &&
        selectedComp.daurounds[sections[targetSectionIndex].roundIndex].games
            .any(
              (game) =>
                  game.gameState == GameState.startedResultNotKnown ||
                  game.gameState == GameState.startedResultKnown,
            );
    if (targetSectionIndex == 0 && refinement == 0 && !roundUnderway) {
      return (offset: 0.0, sectionIndex: 0);
    }
    return (
      offset:
          tipsSectionHeaderTop(
            sections: sections,
            sectionIndex: targetSectionIndex,
            leadingExtent: WelcomeHeader.height,
          ) +
          refinement,
      sectionIndex: targetSectionIndex,
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final distance = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 100.0,
      LogicalKeyboardKey.arrowUp => -100.0,
      LogicalKeyboardKey.space => 300.0,
      LogicalKeyboardKey.pageDown => viewportHeight,
      LogicalKeyboardKey.pageUp => -viewportHeight,
      _ => null,
    };
    final controller = _scrollController;
    if (distance == null || controller == null || !controller.hasClients) {
      return;
    }
    controller.animateTo(
      controller.offset + distance,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Measures once per competition, width, text scale and set of names. The
  /// width comes from the list's own constraints and never from MediaQuery:
  /// the app shell caps the content, so the window is a different box from
  /// the card. The names and grounds the cards are measured for arrive with
  /// the games, and a finals placeholder gives way to a team's name.
  TipsCardLayout _syncCardLayout(
    BuildContext context,
    double width,
    DAUComp selectedComp,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textTheme = Theme.of(context).textTheme;
    final key =
        '${selectedComp.dbkey}:$width:${textScaler.scale(16)}:'
        '${_measuredTextKey(selectedComp)}';
    final current = _cardLayout;
    if (key == _cardLayoutKey && current != null) {
      return current;
    }
    _cardLayoutKey = key;
    return _cardLayout = TipsCardLayout.measure(
      width: width,
      textScaler: textScaler,
      textTheme: textTheme,
      textDirection: Directionality.of(context),
      cards: [
        for (final card in tipsMeasurementCards(selectedComp.daurounds))
          card.content(textTheme),
      ],
    );
  }

  /// Folded in one game at a time: the tab builds on every notification, and
  /// listing every name first allocated a list as long as the season.
  int _measuredTextKey(DAUComp selectedComp) {
    var key = 0;
    for (final dauRound in selectedComp.daurounds) {
      for (final game in dauRound.games) {
        key = Object.hash(
          key,
          dauRound.dAUroundNumber,
          game.homeTeam.name,
          game.awayTeam.name,
          game.location,
        );
      }
    }
    return key;
  }

  @override
  void dispose() {
    focusNode.dispose();
    _scrollController?.dispose();
    super.dispose();
  }
}

/// The last card of the list.
///
/// Taller by the room the floating controls take along the bottom, so the card
/// can scroll clear of them. Its content stays where it was, at the top, and the
/// extra is simply card below it.
class EndFooter extends StatelessWidget {
  const EndFooter({super.key});

  static const double height = kTipsEndFooterHeight;

  /// The footer's height here, the room for the floating controls included.
  static double extentIn(BuildContext context) =>
      height + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final controlsRoom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: extentIn(context),
      child: _CompBoundaryCard(
        iconSize: 46,
        title: 'End of regular competition',
        body: 'Hope to see you again next year.',
        bottomRoom: controlsRoom,
      ),
    );
  }
}

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({required this.daucompsViewmodelConsumer, super.key});

  final DAUCompsViewModel daucompsViewmodelConsumer;

  static const double height = kTipsWelcomeHeaderHeight;

  @override
  Widget build(BuildContext context) {
    return _CompBoundaryCard(
      iconSize: 64,
      title:
          'Start of competition\n${daucompsViewmodelConsumer.selectedDAUComp!.name}',
      body: 'New here? You will find instructions and scoring information in the [Help...] section on the Profile Tab.',
    );
  }
}

class _CompBoundaryCard extends StatelessWidget {
  const _CompBoundaryCard({
    required this.iconSize,
    required this.title,
    this.body,
    this.bottomRoom = 0,
  });

  final double iconSize;
  final String title;
  final String? body;

  /// Extra card kept empty below the content.
  final double bottomRoom;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardCornerRadius),
      ),
      color: Colors.black38,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.0, 10.0, 18.0, 10.0 + bottomRoom),
        child: Row(
          children: [
            SizedBox(
              width: iconSize + 8,
              child: Center(child: AppIcon(size: iconSize, borderRadius: 12)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: body == null
                  ? Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            height: 1.1,
                          ),
                          softWrap: true,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            body!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.15,
                            ),
                            softWrap: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
