import 'package:flutter/material.dart';

class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    this.size = 110,
    this.borderRadius = 15,
  });

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: Image.asset('assets/icon/AppIcon.png', fit: BoxFit.cover),
      ),
    );
  }
}
