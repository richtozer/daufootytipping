import 'package:flutter/material.dart';

class UserAuthBackground extends StatelessWidget {
  final Widget child;
  final Color? overlayColor;

  const UserAuthBackground({
    super.key,
    required this.child,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final Color effectiveOverlayColor =
        overlayColor ??
        (isDarkMode ? Colors.transparent : const Color(0x8AFFFFFF));

    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter:
              isDarkMode
                  ? const ColorFilter.matrix(<double>[
                    1.08,
                    0,
                    0,
                    0,
                    -46,
                    0,
                    1.08,
                    0,
                    0,
                    -46,
                    0,
                    0,
                    1.08,
                    0,
                    -46,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ])
                  : const ColorFilter.mode(
                    Colors.transparent,
                    BlendMode.srcOver,
                  ),
          child: Image.asset(
            'assets/grass_background_blurred.webp',
            fit: BoxFit.cover,
          ),
        ),
        ColoredBox(color: effectiveOverlayColor),
        child,
      ],
    );
  }
}
