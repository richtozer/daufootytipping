import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/connection_loss_notice.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// A card for the Profile page that says the connection is lost for as long as
/// it is. Unlike [ConnectionLossNotice] it has no way to dismiss it: the banner
/// is easy to wave away and then forget, and this is where someone looks to find
/// out why their data is not moving.
///
/// It takes the width of the column it sits in and the margin of the other
/// panel cards, and builds nothing while the connection is fine.
class ConnectionLossProfileCard extends StatelessWidget {
  const ConnectionLossProfileCard({super.key, this.monitor});

  /// The monitor to show; the app's own when not given.
  final ConnectionLossMonitor? monitor;

  static const String heading = 'Not connected';

  static const String detail =
      'What you see may be out of date, and changes you make may not have '
      'reached the server. If you have signal and this continues, restart the '
      'app.';

  @override
  Widget build(BuildContext context) {
    final ConnectionLossMonitor source = monitor ?? di<ConnectionLossMonitor>();
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        if (!source.connectionLost) {
          return const SizedBox.shrink();
        }
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          color: ConnectionLossNotice.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardCornerRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off, color: ConnectionLossNotice.foreground),
                SizedBox(width: 12),
                Expanded(child: _Message()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message();

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(color: ConnectionLossNotice.foreground);
    // The heading and the advice are announced together when the card appears;
    // there is nothing here to act on but the advice itself.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ConnectionLossProfileCard.heading,
            style: style.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(ConnectionLossProfileCard.detail, style: style),
        ],
      ),
    );
  }
}
