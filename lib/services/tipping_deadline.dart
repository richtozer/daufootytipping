import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/services/tipping_policy.dart';
import 'package:watch_it/watch_it.dart';

export 'package:daufootytipping/services/tipping_policy.dart';

int get configuredTipGracePeriodSeconds => di.isRegistered<ConfigViewModel>()
    ? di<ConfigViewModel>().tipGracePeriodSeconds
    : defaultTipGracePeriodSeconds;

DateTime tippingDeadline(DateTime kickoff, {int? graceSeconds}) =>
    kickoff.add(Duration(seconds: graceSeconds ?? configuredTipGracePeriodSeconds));

bool tippingIsOpen(DateTime kickoff, {DateTime? now, int? graceSeconds}) =>
    (now ?? DateTime.now()).isBefore(tippingDeadline(kickoff, graceSeconds: graceSeconds));
