import 'package:daufootytipping/models/league.dart';
import 'package:flutter/material.dart';

/// The red banner the app uses to say it cannot reach the server, floated near
/// the bottom of the screen where a thumb can reach it.
///
/// It carries either a dismiss control beside the message ([onDismiss]) or an
/// action on its own row under the message ([action]), such as Retry.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.action,
  });

  final String message;

  /// Shows a close control beside the message when given.
  final VoidCallback? onDismiss;

  /// A control shown at the bottom right, under the message.
  final Widget? action;

  /// The app's AFL red, so the banner reads as part of the app and stands out
  /// against the green theme. It is the same in the light and dark themes.
  static final Color background = League.afl.colour;

  /// White on [background] has a contrast of about 4.7:1 (WCAG AA needs 4.5:1
  /// for text this size); a test pins it.
  static const Color foreground = Colors.white;

  /// Names the dismiss control for screen readers.
  static const String dismissLabel = 'Dismiss';

  @override
  Widget build(BuildContext context) {
    final VoidCallback? dismiss = onDismiss;
    final Widget? trailingAction = action;
    final Widget messageRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, color: foreground),
        const SizedBox(width: 10),
        Flexible(
          child: Padding(
            // Without a close button the message needs its own room above and
            // to the right.
            padding: dismiss == null
                ? const EdgeInsetsDirectional.fromSTEB(0, 8, 10, 0)
                : EdgeInsets.zero,
            // Only the message is announced when it appears; the controls stay
            // reachable for screen readers.
            child: Semantics(
              liveRegion: true,
              child: Text(message, style: const TextStyle(color: foreground)),
            ),
          ),
        ),
        if (dismiss != null)
          // No tooltip: the banner can sit above the Navigator, where no
          // Overlay exists to show one. Screen readers get the label instead.
          Semantics(
            button: true,
            label: dismissLabel,
            onTap: dismiss,
            excludeSemantics: true,
            child: IconButton(
              icon: const Icon(Icons.close, color: foreground),
              onPressed: dismiss,
            ),
          ),
      ],
    );
    return Material(
      color: background,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          14,
          4,
          4,
          trailingAction == null ? 4 : 0,
        ),
        child: trailingAction == null
            ? messageRow
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [messageRow, trailingAction],
              ),
      ),
    );
  }
}
