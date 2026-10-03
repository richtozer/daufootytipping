import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_surface.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:flutter/material.dart';

/// The tab destinations grouped in one floating glass pill: horizontal along
/// the bottom, vertical down the side. The selected tab carries a green chip.
class AppGlassPill extends StatelessWidget {
  const AppGlassPill({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.axis = Axis.horizontal,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Axis axis;

  bool get _horizontal => axis == Axis.horizontal;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (var index = 0; index < destinations.length; index++)
        _PillTab(
          destination: destinations[index],
          selected: index == selectedIndex,
          horizontal: _horizontal,
          onTap: () => onSelected(index),
        ),
    ];
    return AppGlassSurface(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kGlassOuterRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kGlassPadding),
        child: _horizontal
            ? Row(mainAxisSize: MainAxisSize.min, children: tabs)
            : Column(mainAxisSize: MainAxisSize.min, children: tabs),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.destination,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppGlassStyle.of(context);
    final foreground = selected ? style.selectedForeground : style.foreground;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kGlassItemRadius),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: destination.enabled,
      label: destination.shortLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: shape,
          onTap: destination.enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: horizontal ? kGlassHorizontalTabWidth : kGlassSideItemWidth,
            height: kGlassItemExtent,
            decoration: ShapeDecoration(
              color: selected ? style.selectedFill : Colors.transparent,
              shape: shape,
            ),
            child: ExcludeSemantics(
              child: Opacity(
                opacity: destination.enabled ? 1 : 0.4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Every icon gets the same slot, so a destination whose icon
                    // carries a badge does not push its label out of line.
                    SizedBox.square(
                      dimension: kGlassIconSlot,
                      child: Center(
                        child: IconTheme(
                          data: IconThemeData(color: foreground, size: 24),
                          child: destination.icon,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        destination.shortLabel,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
