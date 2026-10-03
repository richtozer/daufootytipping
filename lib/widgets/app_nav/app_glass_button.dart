import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_surface.dart';
import 'package:flutter/material.dart';

/// One symbol-only action. [label] names it for screen readers, since
/// the symbol carries no text of its own. There is no tooltip: the controls sit
/// above the Navigator, where no Overlay exists to show one.
@immutable
class AppGlassAction {
  const AppGlassAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

/// A single action as a floating glass square, such as Back.
class AppGlassButton extends StatelessWidget {
  const AppGlassButton({
    super.key,
    required this.action,
    this.size = kGlassHorizontalThickness,
  });

  final AppGlassAction action;

  /// Matches the thickness of the pill it replaces or sits beside.
  final double size;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kGlassOuterRadius),
      ),
      child: SizedBox.square(
        dimension: size,
        child: _ActionIcon(action: action, iconSize: 26),
      ),
    );
  }
}

/// Several actions sharing one glass pill so they read as a set, such as Add
/// and Back on an admin list.
class AppGlassGroup extends StatelessWidget {
  const AppGlassGroup({
    super.key,
    required this.actions,
    this.axis = Axis.horizontal,
  });

  final List<AppGlassAction> actions;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    final extent = horizontal ? kGlassItemExtent : kGlassSideItemWidth;
    final items = [
      for (final action in actions)
        SizedBox.square(
          dimension: extent,
          child: _ActionIcon(action: action, iconSize: 24),
        ),
    ];
    return AppGlassSurface(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kGlassOuterRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kGlassPadding),
        child: horizontal
            ? Row(mainAxisSize: MainAxisSize.min, children: items)
            : Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.action, required this.iconSize});

  final AppGlassAction action;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final style = AppGlassStyle.of(context);
    return Semantics(
      button: true,
      enabled: action.onPressed != null,
      label: action.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kGlassItemRadius),
          ),
          onTap: action.onPressed,
          child: Center(
            child: Opacity(
              opacity: action.onPressed == null ? 0.4 : 1,
              child: Icon(action.icon, size: iconSize, color: style.foreground),
            ),
          ),
        ),
      ),
    );
  }
}
