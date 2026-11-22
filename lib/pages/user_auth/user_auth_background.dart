import 'package:daufootytipping/widgets/app_backdrop.dart';
import 'package:flutter/material.dart';

/// The backdrop behind the startup and sign-in screens: the grass under the
/// same veil the home page lays over it, so moving from one to the other does
/// not change the background.
class UserAuthBackground extends StatelessWidget {
  final Widget child;

  const UserAuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        const AppBackdrop(),
        ColoredBox(color: isDarkMode ? Colors.black54 : Colors.white54),
        child,
      ],
    );
  }
}
