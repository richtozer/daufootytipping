import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';

class FixtureUpdatePolicy {
  const FixtureUpdatePolicy();

  bool shouldStartDailyTimer({
    required bool isWeb,
    required bool isAdminMode,
    required TipperRole? authenticatedRole,
  }) {
    if (isWeb) return false;
    if (isAdminMode) return false;
    if (authenticatedRole != TipperRole.admin) return false;
    return true;
  }

  bool shouldTriggerFixtureUpdate({
    required DAUComp? activeComp,
    required DateTime now,
    required Duration threshold,
  }) {
    if (activeComp == null) return false;
    final last = activeComp.lastFixtureUpdateTimestampUTC;
    if (last == null) return false;
    return now.difference(last).inHours >= threshold.inHours;
  }
}

