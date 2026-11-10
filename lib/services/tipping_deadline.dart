import 'package:daufootytipping/services/server_clock.dart';
import 'package:daufootytipping/services/tipping_policy.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

export 'package:daufootytipping/services/tipping_policy.dart';

/// The grace period now in force: the administrator's setting, or the default
/// before it has been read.
int get configuredTipGracePeriodSeconds => di.isRegistered<ConfigViewModel>()
    ? di<ConfigViewModel>().tipGracePeriodSeconds
    : defaultTipGracePeriodSeconds;

/// The time to judge a tipping deadline by: the server's, which is what the
/// database rules use, so a phone with a fast or slow clock is not shut out early
/// (or shown a game as open that the server has closed).
DateTime tippingNow() =>
    di.isRegistered<ServerClock>() ? di<ServerClock>().now() : DateTime.now();

DateTime tippingDeadline(DateTime kickoff, {int? graceSeconds}) =>
    tipDeadlineFor(kickoff, graceSeconds ?? configuredTipGracePeriodSeconds);

bool tippingIsOpen(DateTime kickoff, {DateTime? now, int? graceSeconds}) =>
    !tippingHasClosed(
      kickoff,
      now ?? tippingNow(),
      graceSeconds ?? configuredTipGracePeriodSeconds,
    );
