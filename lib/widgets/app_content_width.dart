import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// The width a form or message stays readable at. Sign-in, error and loading
/// screens keep this regardless of how much room the display offers.
const double kFormContentWidth = 500;

/// Caps content at the width a game card needs to lay itself out inline, and no
/// further: past that point extra width only stretches whitespace.
///
/// The bound comes from the same measurement the cards use, so the app cannot
/// sit at its own maximum width and still render a stacked card. It depends on
/// the competition and the text scale alone and never on live scores, so a
/// score changing during a round cannot resize the app. Where the display is
/// narrower than the bound, the content simply uses what is available.
class AppContentWidth extends StatelessWidget {
  const AppContentWidth({
    super.key,
    required this.daurounds,
    required this.child,
  });

  /// Read for the widest team name and venue the competition can show.
  final Iterable<DAURound> daurounds;
  final Widget child;

  /// Breathing room above the threshold, so the widest game is not laid out at
  /// exactly its minimum inline width.
  static const double gutter = 16;

  /// The widest the content should be drawn at the current text scale.
  static double maxContentWidth({
    required BuildContext context,
    required Iterable<DAURound> daurounds,
    required double availableWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final layout = TipsCardLayout.measure(
      width: availableWidth,
      textScaler: MediaQuery.textScalerOf(context),
      textTheme: textTheme,
      textDirection: Directionality.of(context),
      cards: [
        for (final card in tipsMeasurementCards(daurounds))
          card.content(textTheme),
      ],
    );
    return layout.wideMinWidth + gutter;
  }

  @override
  Widget build(BuildContext context) {
    // Horizontal display insets -- a folding phone's hinge side, a landscape
    // notch -- belong to the content, not to the background: the backdrop
    // bleeds under them while nothing interactive does.
    final insets = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - insets.left - insets.right;
        final maxWidth = maxContentWidth(
          context: context,
          daurounds: daurounds,
          availableWidth: available,
        );
        return Padding(
          padding: EdgeInsets.only(left: insets.left, right: insets.right),
          child: Center(
            child: SizedBox(
              width: available > maxWidth ? maxWidth : available,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Keeps a form or message at a readable width on a wide display.
class FormContentWidth extends StatelessWidget {
  const FormContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kFormContentWidth),
        child: child,
      ),
    );
  }
}

/// The content width for a page pushed on top of the home tabs, so a detail
/// page is laid out as wide as the tab it came from rather than stretching to
/// fill the display. Reads the selected competition itself, because a pushed
/// page is only reachable once one is loaded.
class AppPageWidth extends StatelessWidget {
  const AppPageWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final daurounds = di.isRegistered<DAUCompsViewModel>()
        ? di<DAUCompsViewModel>().selectedDAUComp?.daurounds ??
              const <DAURound>[]
        : const <DAURound>[];
    // The page is narrower than the display, so something has to fill the
    // sides. Bleed the same background the tabs use rather than leaving the
    // route's own backdrop showing as bars.
    final isDarkMode =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(
            child: Image(
              image: AssetImage('assets/grass_background_blurred.webp'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Pushed pages do not set their own scaffold colour, so overriding it
        // here lets the backdrop through with the same veil the tabs use,
        // rather than an opaque panel sitting on top of it.
        Theme(
          data: Theme.of(context).copyWith(
            scaffoldBackgroundColor: isDarkMode
                ? Colors.black54
                : Colors.white54,
          ),
          child: AppContentWidth(daurounds: daurounds, child: child),
        ),
      ],
    );
  }
}

/// A route whose page keeps the app's content width. Use in place of
/// [MaterialPageRoute] so detail pages match the tabs they were opened from.
MaterialPageRoute<T> appPageRoute<T>(WidgetBuilder builder) {
  return MaterialPageRoute<T>(
    builder: (context) => AppPageWidth(child: builder(context)),
  );
}
