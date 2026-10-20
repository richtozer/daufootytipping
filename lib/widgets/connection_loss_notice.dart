import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:flutter/material.dart';

/// Tells the user that the app has lost its connection to the database and
/// that restarting is the way back, shown only while [ConnectionLossMonitor]
/// says the loss has gone on long enough to matter.
///
/// The wording covers two cases that look the same from here: a connection the
/// server has ended, which only a restart repairs, and having no signal, which
/// needs nothing from the user.
class ConnectionLossNotice extends StatelessWidget {
  const ConnectionLossNotice({super.key, required this.monitor});

  final ConnectionLossMonitor monitor;

  static const String message =
      'Not connected. If you have signal and this continues, restart the app.';

  /// Names the dismiss control for screen readers.
  static const String dismissLabel = 'Dismiss';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        if (!monitor.noticeVisible) {
          return const SizedBox.shrink();
        }
        final colors = Theme.of(context).colorScheme;
        return Material(
          color: colors.tertiaryContainer,
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, color: colors.onTertiaryContainer),
                const SizedBox(width: 10),
                Flexible(
                  // Only the message is announced when it appears; the Dismiss
                  // button stays reachable for screen readers.
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      style: TextStyle(color: colors.onTertiaryContainer),
                    ),
                  ),
                ),
                // No tooltip: the notice sits above the Navigator, where no
                // Overlay exists to show one (the same constraint as the
                // floating controls). Screen readers get the label instead.
                Semantics(
                  button: true,
                  label: dismissLabel,
                  onTap: monitor.dismiss,
                  excludeSemantics: true,
                  child: IconButton(
                    icon: Icon(Icons.close, color: colors.onTertiaryContainer),
                    onPressed: monitor.dismiss,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
