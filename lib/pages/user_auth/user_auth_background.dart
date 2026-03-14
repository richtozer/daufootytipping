import 'package:flutter/material.dart';

class UserAuthBackground extends StatelessWidget {
  final Widget child;
  final Color overlayColor;

  const UserAuthBackground({
    super.key,
    required this.child,
    this.overlayColor = const Color(0x8AFFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/grass_background_blurred.webp', fit: BoxFit.cover),
        ColoredBox(color: overlayColor),
        child,
      ],
    );
  }
}
