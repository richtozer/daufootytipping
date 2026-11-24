import 'dart:math' as math;

import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

const double _ribbonThickness = 12.0;
const double _yearInnerDistance = 44.0;
const double _ribbonGap = 6.0;
const double _godModeInnerDistance =
    _yearInnerDistance + _ribbonThickness + _ribbonGap;
const double _shadowBlur = 6.0;
const BoxShadow _ribbonShadow = BoxShadow(
  color: Color(0x7F000000),
  blurRadius: _shadowBlur,
);

/// The diagonal corner banners in the window's bottom-left corner: the year
/// of a past comp being viewed in orange (inner stripe), and in god mode the
/// tipper being viewed in red stacked parallel above it (outer stripe) for a
/// longer diagonal span.
///
/// Wrap a full-width layer, so the banners sit in the window's bottom-left
/// corner even when the page itself is a narrower column on a wide display:
/// the home tabs, and the backdrop of a page opened with `appPageRoute`. They
/// are part of the page, so a dialog or sheet opened over it covers them.
class AppBanners extends StatelessWidget {
  /// Creates a diagonal corner banner overlay around [child].
  const AppBanners({super.key, required this.child});

  /// The full-width page content shown beneath the banners.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!di.isRegistered<DAUCompsViewModel>() ||
        !di.isRegistered<TippersViewModel>()) {
      return child;
    }
    final comps = di<DAUCompsViewModel>();
    final tippers = di<TippersViewModel>();
    // The page keeps one slot whatever the banners do, so one coming or going
    // never rebuilds it.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([comps, tippers]),
              builder: (context, _) => _banners(comps, tippers),
            ),
          ),
        ),
      ],
    );
  }

  Widget _banners(DAUCompsViewModel comps, TippersViewModel tippers) {
    final selectedComp = comps.selectedDAUComp;
    final children = <Widget>[
      if (selectedComp != null && !comps.isSelectedCompActiveComp())
        _CornerRibbon(
          message: _compYear(selectedComp.name),
          color: Colors.orange,
          textColor: Colors.black,
          innerDistance: _yearInnerDistance,
        ),
      // God mode sits above the year slot in red in the bottom-left corner so
      // longer tipper names get more diagonal room and never collide with the
      // year. It needs a signed-in tipper to compare the selected one with.
      if (tippers.authenticatedTipper != null && tippers.inGodMode)
        _CornerRibbon(
          message: tippers.selectedTipper.name,
          color: Colors.red,
          textColor: Colors.white,
          innerDistance: _godModeInnerDistance,
        ),
    ];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: children,
    );
  }

  String _compYear(String compName) =>
      RegExp(r'\d{4}').firstMatch(compName)?.group(0) ?? compName;
}

class _CornerRibbon extends StatelessWidget {
  const _CornerRibbon({
    required this.message,
    required this.color,
    required this.textColor,
    required this.innerDistance,
  });

  final String message;
  final Color color;
  final Color textColor;
  final double innerDistance;

  @override
  Widget build(BuildContext context) {
    final center = (innerDistance + _ribbonThickness / 2) * math.sqrt1_2;
    final length = (innerDistance + _ribbonThickness) * 2 + _shadowBlur * 4;
    return Positioned(
      left: center - length / 2,
      bottom: center - _ribbonThickness / 2,
      width: length,
      height: _ribbonThickness,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            boxShadow: const [_ribbonShadow],
          ),
          child: Center(
            child: SizedBox(
              width: innerDistance * 2 - 8,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: textColor,
                  fontSize: _ribbonThickness * 0.85,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  decoration: TextDecoration.none,
                  fontFamily: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.fontFamily,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
