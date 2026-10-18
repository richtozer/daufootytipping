import 'package:flutter/material.dart';

/// The corner radius of the app's cards and panels: the tips game card, its
/// choice panel, the app table and the floating controls all take it, so the
/// surfaces read as one family.
const double kCardCornerRadius = 12;

/// The green that marks a selected or highlighted thing, such as the selected
/// nav tab and a winning score, with the text colour that goes on it. In light
/// mode the pale grass green; in dark mode the tips choice chips' green at 60%,
/// so it sits on dark glass.
const Color kSelectionLightColor = Color(0xF2C5E1A5);
const Color kOnSelectionLightColor = Color(0xFF14200C);
const Color kSelectionDarkColor = Color(0x998BC34A);
const Color kOnSelectionDarkColor = Color(0xFFFFFFFF);

/// The heading row of a table, in the dark, see-through style of the league
/// and round headers, with the text that reads on it.
const Color kTableHeaderColor = Colors.black54;
const Color kTableHeaderTextColor = Colors.white70;

Color appSelectionColor(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.dark
    ? kSelectionDarkColor
    : kSelectionLightColor;

Color appOnSelectionColor(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.dark
    ? kOnSelectionDarkColor
    : kOnSelectionLightColor;

/// The surface cards and panels sit on over the backdrop in light mode.
const Color kPanelLightColor = Colors.white70;

/// White at about 14%, so the dark backdrop reads through it instead of the
/// panel glowing against it.
const Color kPanelDarkColor = Color(0x24FFFFFF);

/// The translucent surface the tips cards, the stats panel and similar panels
/// share, following the system brightness as the app's other custom surfaces do.
Color appPanelColor(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.dark
    ? kPanelDarkColor
    : kPanelLightColor;

/// The surface of the panels laid inside a see-through panel, such as a tips
/// card's result, choices and info. Opaque and dark in dark mode, where the
/// forced light theme would otherwise leave them bright; null in light mode,
/// to keep the card's own colour.
const Color kInnerPanelDarkColor = Color(0xFF141A11);

Color? appInnerPanelColor(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.dark
    ? kInnerPanelDarkColor
    : null;

/// The text colour on a panel that [appPanelColor] makes see-through, or null
/// to leave the theme's own. In dark mode the theme's text is dark, since the
/// tips page forces the light theme, and would sink into the dark panel.
Color? appPanelTextColor(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.dark
    ? Colors.white
    : null;

/// The text theme for text laid straight on an [appPanelColor] panel.
TextTheme appPanelTextTheme(BuildContext context) {
  final base = Theme.of(context).textTheme;
  final colour = appPanelTextColor(context);
  return colour == null
      ? base
      : base.apply(displayColor: colour, bodyColor: colour);
}

/// Gives every button the card corner, so the profile, admin and dialog buttons
/// match the cards they sit beside instead of the stadium shape Material uses.
///
/// A button that sets its own shape, such as a branded sign-in button or the
/// live-score keypad, still wins over this.
ThemeData withCardCornerButtons(ThemeData theme) {
  final shape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kCardCornerRadius),
    ),
  );
  ButtonStyle withShape(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(shape: shape);
  return theme.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: withShape(theme.elevatedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: withShape(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: withShape(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: withShape(theme.textButtonTheme.style),
    ),
  );
}

/// The bundled font family used on every platform, so layouts measure the
/// same on iOS as on Android and web.
const String appFontFamily = 'Roboto';

final ThemeData myTheme = ThemeData(
  fontFamily: appFontFamily,
  primaryColor: const Color(0xFF335522),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF335522)),
);

//NRL AFL gradients
var nrlAflColourGradient = const LinearGradient(
  colors: [Color(0xff04cf5d), Color(0xffe21e31)],
  stops: [0.25, 0.75],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

var nrlColourGradient = const LinearGradient(
  colors: [Color(0xff04cf5d), Color(0xffffffff)],
  stops: [0.05, 0.2],
  begin: Alignment.bottomRight,
  end: Alignment.topLeft,
);
