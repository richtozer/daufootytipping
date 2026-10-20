import 'dart:async';

import 'package:daufootytipping/services/analytics_service.dart';
import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:flutter/foundation.dart';

/// How long the connection must stay down, in the foreground, before the user
/// is told. The Realtime Database normally reconnects within a second or two of
/// a resume, so this is well clear of a routine reconnect.
const Duration defaultConnectionLossThreshold = Duration(seconds: 30);

/// Notices when the Realtime Database connection stays down while the app is in
/// the foreground.
///
/// A database client that the server has killed (for example after a failed
/// App Check token refresh at resume) never reconnects until the app is
/// restarted, and nothing the app can do clears it. This tells the user so,
/// instead of leaving them looking at stale data. The same notice also covers
/// having no signal, so its wording is the caller's to choose carefully.
///
/// Being disconnected while the app is in the background is normal and is
/// ignored: coming back to the foreground starts the wait again from zero.
///
/// When an [analytics] service is given, the monitor logs when the notice is
/// shown, dismissed, and when the connection returns after it was shown, so the
/// frequency and length of these outages can be seen. The same events go to the
/// resume diagnostics log in diagnostics builds.
class ConnectionLossMonitor extends ChangeNotifier {
  ConnectionLossMonitor({
    required Stream<bool?> connectionStates,
    this.threshold = defaultConnectionLossThreshold,
    bool foreground = true,
    AnalyticsService? analytics,
    DateTime Function() clock = DateTime.now,
  }) : _foreground = foreground,
       _analytics = analytics,
       _clock = clock {
    _subscription = connectionStates.listen(
      (connected) {
        _connected = connected == true;
        _update();
      },
      onError: (Object error, StackTrace stackTrace) {
        _connected = false;
        _update();
      },
    );
    _update();
  }

  /// The notice appeared after the connection had been down for the threshold.
  static const String noticeShownEvent = 'connection_lost_notice_shown';

  /// The user dismissed the notice.
  static const String noticeDismissedEvent = 'connection_lost_notice_dismissed';

  /// The connection returned after the notice had been shown.
  static const String restoredEvent = 'connection_restored_after_notice';

  final Duration threshold;
  final AnalyticsService? _analytics;
  final DateTime Function() _clock;

  late final StreamSubscription<bool?> _subscription;
  DateTime? _downSince;
  DateTime? _shownAt;
  bool _shownThisOutage = false;
  Timer? _timer;
  bool _foreground;
  bool _connected = false;
  bool _dismissed = false;
  bool _connectionLost = false;

  /// Whether the connection has been down, in the foreground, for the
  /// threshold. For places that must keep saying so however often the user has
  /// dismissed the banner, such as a card on the Profile page.
  bool get connectionLost => _connectionLost;

  /// Whether the dismissible banner should be on screen now: the connection is
  /// lost and the user has not dismissed it for this outage.
  bool get noticeVisible => _connectionLost && !_dismissed;

  /// Tells the monitor whether the app is in the foreground.
  void setForeground(bool foreground) {
    if (foreground == _foreground) {
      return;
    }
    _foreground = foreground;
    if (!foreground) {
      // Each trip to the background starts the outage over.
      _dismissed = false;
    }
    _update();
  }

  /// Hides the notice for the rest of this outage. A later outage shows it
  /// again.
  void dismiss() {
    if (!noticeVisible) {
      return;
    }
    _dismissed = true;
    notifyListeners();
    _report(noticeDismissedEvent, <String, Object>{
      'visible_seconds': _secondsSince(_shownAt),
    });
  }

  void _update() {
    final bool down = _foreground && !_connected;
    if (!down) {
      _timer?.cancel();
      _timer = null;
      if (_connected && _shownThisOutage) {
        _report(restoredEvent, <String, Object>{
          'outage_seconds': _secondsSince(_downSince),
        });
      }
      if (_connected) {
        _dismissed = false;
      }
      _downSince = null;
      _shownAt = null;
      _shownThisOutage = false;
      _setConnectionLost(false);
      return;
    }
    _downSince ??= _clock();
    if (_connectionLost || _timer != null) {
      return;
    }
    _timer = Timer(threshold, () {
      _timer = null;
      if (_foreground && !_connected) {
        _shownAt = _clock();
        _shownThisOutage = true;
        _setConnectionLost(true);
        _report(noticeShownEvent, <String, Object>{
          'down_seconds': _secondsSince(_downSince),
        });
      }
    });
  }

  int _secondsSince(DateTime? start) =>
      start == null ? 0 : _clock().difference(start).inSeconds;

  /// Logs to analytics and the diagnostics log. A failure to log is never the
  /// user's problem and must not disturb the notice.
  void _report(String name, Map<String, Object> parameters) {
    AppResumeDiagnostics.record(name, details: parameters);
    final AnalyticsService? analytics = _analytics;
    if (analytics == null) {
      return;
    }
    try {
      unawaited(
        analytics
            .logEvent(name, parameters: parameters)
            .catchError(
              (Object error) => debugPrint('$name not logged: $error'),
            ),
      );
    } catch (error) {
      debugPrint('$name not logged: $error');
    }
  }

  void _setConnectionLost(bool lost) {
    if (_connectionLost == lost) {
      return;
    }
    _connectionLost = lost;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
