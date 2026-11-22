import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/widgets/notice_banner.dart';
import 'package:flutter/material.dart';

/// Tells the user that the app has lost its connection to the database, that
/// their tips are kept and will be lodged when it returns, and that restarting is
/// the way back, shown only while [ConnectionLossMonitor]
/// says the loss has gone on long enough to matter.
///
/// The wording covers two cases that look the same from here: a connection the
/// server has ended, which only a restart repairs, and having no signal, which
/// needs nothing from the user.
class ConnectionLossNotice extends StatelessWidget {
  const ConnectionLossNotice({super.key, required this.monitor});

  final ConnectionLossMonitor monitor;

  static const String message =
      'Not connected. Your tips are kept on this phone and will be lodged when '
      'you are back online. If you have signal and this continues, restart the '
      'app.';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        if (!monitor.noticeVisible) {
          return const SizedBox.shrink();
        }
        return NoticeBanner(message: message, onDismiss: monitor.dismiss);
      },
    );
  }
}
