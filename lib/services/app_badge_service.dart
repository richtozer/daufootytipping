import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class BadgeCountWriter {
  Future<bool> setCount(int count);
}

class AppBadgeService implements BadgeCountWriter {
  AppBadgeService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'coach.interview.daufootytipping/app_badge';
  final MethodChannel _channel;

  @override
  Future<bool> setCount(int count) async {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative');
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('setCount', <String, int>{
            'count': count,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

class OutstandingTipsAppBadgeController {
  OutstandingTipsAppBadgeController(
    this._badgeWriter, {
    void Function(String message)? logMessage,
  }) : _logMessage = logMessage ?? _defaultLogMessage;

  final BadgeCountWriter _badgeWriter;
  final void Function(String message) _logMessage;
  int? _lastRequestedCount;

  Future<bool> sync({
    required Tipper tipper,
    required DAUComp? comp,
    required int outstandingCount,
  }) async {
    final isEligible =
        !tipper.isAnonymous && comp != null && tipper.paidForComp(comp);
    final requestedCount = isEligible ? outstandingCount : 0;
    if (_lastRequestedCount == requestedCount) {
      return true;
    }

    _lastRequestedCount = requestedCount;
    final didSetCount = await _badgeWriter.setCount(requestedCount);
    if (!didSetCount) {
      if (_lastRequestedCount == requestedCount) {
        _lastRequestedCount = null;
      }
      _logMessage('Could not update the app badge to $requestedCount');
    }
    return didSetCount;
  }

  static void _defaultLogMessage(String message) => log(message);
}
