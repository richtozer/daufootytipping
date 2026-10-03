import 'package:flutter/material.dart';

/// The corner radius of the app's cards and panels: the tips game card, its
/// choice panel, the app table and the floating controls all take it, so the
/// surfaces read as one family.
const double kCardCornerRadius = 8;

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
