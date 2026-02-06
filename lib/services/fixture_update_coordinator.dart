import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/services/fixture_update_policy.dart';

class FixtureUpdateCoordinator {
  final FixtureUpdatePolicy _policy;
  final DateTime Function() _now;

  const FixtureUpdateCoordinator({
    FixtureUpdatePolicy policy = const FixtureUpdatePolicy(),
    DateTime Function()? now,
  })  : _policy = policy,
        _now = now ?? _defaultNow;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  bool shouldStartDailyTimer({
    required bool isWeb,
    required bool isAdminMode,
    required dynamic authenticatedRole,
  }) {
    return _policy.shouldStartDailyTimer(
      isWeb: isWeb,
      isAdminMode: isAdminMode,
      authenticatedRole: authenticatedRole,
    );
  }

  Future<bool> maybeTriggerUpdate({
    required DAUComp? activeComp,
    required DAUComp? selectedComp,
    required Duration threshold,
    required bool Function() isSelectedCompActive,
    required bool Function(DAUComp comp) isCompOver,
    required Future<DAUComp?> Function(String key) refreshActiveByKey,
    required Future<void> Function(String name, Map<String, dynamic> parameters) logAnalytics,
    required Future<String> Function(DAUComp comp) runFixtureUpdate,
    required Future<void> Function() afterUpdate,
  }) async {
    if (activeComp == null) return false;

    // Always refresh active from DB before deciding
    final refreshed = await refreshActiveByKey(activeComp.dbkey!);
    final comp = refreshed ?? activeComp;

    final shouldTrigger = _policy.shouldTriggerFixtureUpdate(
      activeComp: comp,
      now: _now(),
      threshold: threshold,
    );
    if (!shouldTrigger) return false;

    // Only update if the selected comp is the active comp
    if (!isSelectedCompActive()) return false;

    // Do not run if competition is over
    if (isCompOver(comp)) return false;

    await logAnalytics('fixture_trigger', {
      'comp': comp.name,
      // tipper name can be injected by caller if needed
      'tipperHandlingUpdate': 'unknown tipper',
    });

    await runFixtureUpdate(comp);
    await afterUpdate();
    return true;
  }
}

