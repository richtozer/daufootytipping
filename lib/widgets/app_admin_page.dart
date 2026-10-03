import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_scopes.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:flutter/material.dart';

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
  });

  final String title;
  final Widget body;

  /// Shown beside Back, in order, ahead of it.
  final List<AppGlassAction> actions;

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
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
