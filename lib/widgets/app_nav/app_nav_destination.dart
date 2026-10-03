import 'package:flutter/material.dart';

/// A destination described once and rendered by whichever navigation control
/// the layout calls for.
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.shortLabel,
    this.enabled = true,
  });

  final Widget icon;

  /// Shown under the icon in the pill.
  final String shortLabel;

  final bool enabled;
}
