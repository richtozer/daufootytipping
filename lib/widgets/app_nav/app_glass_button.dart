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
      selectedFill: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kGlassOuterRadius),
      ),
      child: SizedBox.square(
        dimension: size,
        child: _ActionIcon(action: action, iconSize: 28),
      ),
    );
  }
}

/// Several actions side by side, such as Add and Back on an admin list. Each is
/// its own glass button, with a little of the backdrop showing between them so
/// they read as separate controls that belong together.
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
    final size = horizontal ? kGlassHorizontalThickness : kGlassSideThickness;
    final buttons = [
      for (var index = 0; index < actions.length; index++) ...[
        if (index > 0)
          SizedBox(
            width: horizontal ? kGlassButtonGap : 0,
            height: horizontal ? 0 : kGlassButtonGap,
          ),
        AppGlassButton(action: actions[index], size: size),
      ],
    ];
    return horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: buttons)
        : Column(mainAxisSize: MainAxisSize.min, children: buttons);
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
