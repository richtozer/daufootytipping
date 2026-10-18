import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_scopes.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_placement.dart';
import 'package:daufootytipping/widgets/app_under_controls_area.dart';
import 'package:flutter/material.dart';

/// Whether the page is short enough, as in landscape, that its padding is
/// better spent on content.
bool appAdminIsShort(BuildContext context) =>
    MediaQuery.sizeOf(context).height < kShortPaneHeight;

/// The padding round an admin page's body, trimmed where height is scarce.
EdgeInsets appAdminBodyPadding(BuildContext context) => appAdminIsShort(context)
    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
    : const EdgeInsets.all(8);

/// The shell every admin page shares: a plain title, then the page.
///
/// Back comes from the floating controls, and so do any [actions], such as Add
/// on a list or Save on a form, which keeps the whole set in the bottom-right
/// corner under the thumb instead of in an app bar at the top.
class AppAdminPage extends StatelessWidget {
  const AppAdminPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.scrollsUnderControls = false,
  });

  final String title;
  final Widget body;

  /// Shown beside Back, in order, ahead of it.
  final List<AppGlassAction> actions;

  /// Whether the body scrolls under the floating controls, which fade away at
  /// its end. For lists. A form keeps clear of them instead, because its Save
  /// lives in the controls and has to stay reachable.
  final bool scrollsUnderControls;

  Widget _area({required Widget child}) => scrollsUnderControls
      ? AppUnderControlsArea(child: child)
      : SafeArea(child: child);

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    // With the keyboard up the actions float above it, so the page ends above
    // them rather than running underneath.
    final controlsRoom = keyboardUp && actions.isNotEmpty
        ? kGlassHorizontalThickness + 2 * kControlsEdgeMargin
        : 0.0;
    return AppPageActions(
      actions: actions,
      child: Scaffold(
        body: _area(
          child: Column(
            children: [
              Padding(
                padding: appAdminIsShort(context)
                    ? const EdgeInsets.fromLTRB(16, 4, 16, 0)
                    : const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: controlsRoom),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
