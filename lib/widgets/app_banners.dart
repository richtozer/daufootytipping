import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// The diagonal corner banners: the year of a past comp being viewed, in
/// orange bottom-left, and in god mode the tipper being viewed, in red
/// bottom-right.
///
/// Wrap a full-width layer, so the banners sit in the window's corners even
/// when the page itself is a narrower column on a wide display: the home tabs,
/// and the backdrop of a page opened with `appPageRoute`. They are part of the
/// page, so a dialog or sheet opened over it covers them.
class AppBanners extends StatelessWidget {
  const AppBanners({super.key, required this.child});

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
        // Inside the room the page is given, which leaves out the floating
        // nav controls' strip, so the tab pill or Back never covers a ribbon.
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([comps, tippers]),
              builder: (context, _) => Padding(
                padding: MediaQuery.paddingOf(context),
                child: _banners(comps, tippers),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _banners(DAUCompsViewModel comps, TippersViewModel tippers) {
    Widget banners = const SizedBox.expand();
    final selectedComp = comps.selectedDAUComp;
    if (selectedComp != null && !comps.isSelectedCompActiveComp()) {
      banners = Banner(
        message: _compYear(selectedComp.name),
        textStyle: const TextStyle(color: Colors.black),
        location: BannerLocation.bottomStart,
        color: Colors.orange,
        child: banners,
      );
    }
    // God mode is the tipper being viewed, in red, in the other bottom corner,
    // so it never covers the year. It needs a signed-in tipper to compare the
    // selected one with.
    if (tippers.authenticatedTipper != null && tippers.inGodMode) {
      banners = Banner(
        message: tippers.selectedTipper.name,
        location: BannerLocation.bottomEnd,
        color: Colors.red,
        child: banners,
      );
    }
    return banners;
  }

  String _compYear(String compName) =>
      RegExp(r'\d{4}').firstMatch(compName)?.group(0) ?? compName;
}
