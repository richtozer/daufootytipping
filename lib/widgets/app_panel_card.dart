import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';

/// A card that floats over the backdrop on the see-through, green-tinted
/// surface the tips game cards use, with text and icons that read on it in
/// both light and dark mode.
///
/// With an [onTap] the whole card is a button.
class AppPanelCard extends StatelessWidget {
  const AppPanelCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final textColour = appPanelTextColor(context);
    final content = DefaultTextStyle.merge(
      style: TextStyle(color: textColour),
      child: IconTheme.merge(
        data: IconThemeData(color: textColour),
        child: child,
      ),
    );
    return Card(
      margin: margin,
      color: appPanelColor(context),
      surfaceTintColor: League.nrl.colour,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardCornerRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// The dark card that heads a page, in the style of the round headers on the
/// Tips tab. Its content should use light text.
class AppHeaderCard extends StatelessWidget {
  const AppHeaderCard({super.key, required this.child});

  final Widget child;

  /// The text style for the header's main text.
  static const TextStyle textStyle = TextStyle(
    color: Colors.white70,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: Colors.black54,
      surfaceTintColor: League.nrl.colour,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardCornerRadius),
      ),
      child: Padding(padding: const EdgeInsets.all(10), child: child),
    );
  }
}
