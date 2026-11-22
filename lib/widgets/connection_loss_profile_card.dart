import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/connection_loss_notice.dart';
import 'package:daufootytipping/widgets/notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// A card for the Profile page that says the connection is lost for as long as
/// it is. Unlike [ConnectionLossNotice] it has no way to dismiss it: the banner
/// is easy to wave away and then forget, and this is where someone looks to find
/// out why their data is not moving.
///
/// It takes the width of the column it sits in and the margin of the other
/// panel cards, and builds nothing while the connection is fine.
///
/// While it is on screen it tells the monitor, which keeps the banner off the
/// screen so the two do not sit on top of each other.
class ConnectionLossProfileCard extends StatefulWidget {
  const ConnectionLossProfileCard({super.key, this.monitor});

  /// The monitor to show; the app's own when not given.
  final ConnectionLossMonitor? monitor;

  static const String heading = 'Not connected';

  static const String detail =
      'Your tips are kept on this phone and will be lodged when you are back '
      'online, but what you see may be out of date. If you have signal and '
      'this continues, restart the app.';

  @override
  State<ConnectionLossProfileCard> createState() =>
      _ConnectionLossProfileCardState();
}

class _ConnectionLossProfileCardState extends State<ConnectionLossProfileCard> {
  late final ConnectionLossMonitor _source =
      widget.monitor ?? di<ConnectionLossMonitor>();

  /// Whether the card is on screen: its page is the one showing, not covered by
  /// another pushed over it.
  bool _onScreen = false;

  /// Whether the monitor has been told the card is on screen.
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onScreen = ModalRoute.of(context)?.isCurrent ?? true;
    // Telling the monitor can change what the banner shows, which must not
    // happen in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncWithMonitor();
      }
    });
  }

  @override
  void dispose() {
    _onScreen = false;
    _syncWithMonitor();
    super.dispose();
  }

  /// While the card is on screen the banner steps aside, since the card says the
  /// same thing and cannot be dismissed.
  void _syncWithMonitor() {
    if (_onScreen == _registered) {
      return;
    }
    _registered = _onScreen;
    if (_onScreen) {
      _source.persistentSurfaceShown('profile_card');
    } else {
      _source.persistentSurfaceHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _source,
      builder: (context, _) {
        if (!_source.connectionLost) {
          return const SizedBox.shrink();
        }
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          color: NoticeBanner.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardCornerRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off, color: NoticeBanner.foreground),
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
    const TextStyle style = TextStyle(color: NoticeBanner.foreground);
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
