import 'dart:developer';

import 'package:daufootytipping/pages/user_auth/user_auth_background.dart';
import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// Shown when startup cannot reach the server: the app icon, and the same red
/// banner the app uses for a lost connection, with a Retry button in it.
///
/// No signal and a connection the server has refused (such as a rejected App
/// Check token) look the same from the device, so the message covers both:
/// retry first, and reopen the app if that does not help.
///
/// While it is on screen it tells the monitor, which keeps the app-wide banner
/// from appearing on top of it.
class StartupConnectionScreen extends StatefulWidget {
  const StartupConnectionScreen({
    super.key,
    required this.onRetry,
    this.monitor,
  });

  /// Tries to connect and load again. The button shows progress until it
  /// completes.
  final Future<void> Function() onRetry;

  /// The monitor to step aside from; the app's own when not given.
  final ConnectionLossMonitor? monitor;

  static const String message =
      "Can't reach the server. Check you have signal, then tap Retry. If this "
      'keeps happening, close and reopen the app.';

  static const String retryLabel = 'Retry';

  /// Names this screen in the monitor's analytics.
  static const String surfaceName = 'startup_screen';

  @override
  State<StartupConnectionScreen> createState() =>
      _StartupConnectionScreenState();
}

class _StartupConnectionScreenState extends State<StartupConnectionScreen> {
  late final ConnectionLossMonitor _monitor =
      widget.monitor ?? di<ConnectionLossMonitor>();

  bool _registered = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    // Telling the monitor can change what the banner shows, which must not
    // happen in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _registered = true;
      _monitor.persistentSurfaceShown(StartupConnectionScreen.surfaceName);
    });
  }

  @override
  void dispose() {
    if (_registered) {
      _monitor.persistentSurfaceHidden();
    }
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } catch (error) {
      // The banner already says what to do when retrying does not help.
      log('Startup retry failed: $error');
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: UserAuthBackground(
        child: SafeArea(
          // Scrolls only when very large text will not fit, so the banner
          // otherwise sits at the bottom, in reach of a thumb.
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(kControlsEdgeMargin),
                  child: FormContentWidth(
                    child: Column(
                      children: [
                        const SizedBox(height: 38),
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: AppIcon(),
                        ),
                        const Spacer(),
                        NoticeBanner(
                          message: StartupConnectionScreen.message,
                          action: _RetryButton(
                            retrying: _retrying,
                            onPressed: _retry,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.retrying, required this.onPressed});

  final bool retrying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: NoticeBanner.foreground,
        disabledForegroundColor: NoticeBanner.foreground,
      ),
      onPressed: retrying ? null : onPressed,
      child: retrying
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: NoticeBanner.foreground,
                semanticsLabel: 'Retrying',
              ),
            )
          : const Text(StartupConnectionScreen.retryLabel),
    );
  }
}
