import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/services/serial_queue.dart';

/// Tells the server which push tokens belong to the signed-in tipper.
///
/// A token belongs to one device, so to one tipper at a time. Moving it is the
/// server's job (`register-device-token` takes it from whoever held it), and the
/// server expects one client's register and unregister calls for a token to be
/// sent in order, since a pair sent out of order defeats itself. So every call
/// goes through one queue.
class DeviceTokenRegistrar {
  DeviceTokenRegistrar({
    required IdentityService identity,
    this.retryDelays = const <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 30),
    ],
    Future<void> Function(Duration delay)? wait,
    String? Function()? currentAccount,
  }) : _identity = identity,
       _wait = wait ?? Future<void>.delayed,
       _currentAccount = currentAccount ?? (() => null);

  /// How long to wait before each further try after the server could not be
  /// reached; when they run out the registration is given up until the next time
  /// it is asked for.
  final List<Duration> retryDelays;

  final IdentityService _identity;
  final Future<void> Function(Duration delay) _wait;
  final String? Function() _currentAccount;
  final SerialQueue _queue = SerialQueue();

  /// For each token, how many times it has been taken off the tipper. A
  /// registration that was asked for before the latest removal is void, so a
  /// retry waiting out a delay cannot undo a removal made in the meantime.
  final Map<String, int> _removals = <String, int>{};

  /// Registers [token] with the signed-in tipper. True if the server did it.
  ///
  /// A server that could not be reached is tried again after each of
  /// [retryDelays]; the waits are not in the queue, so a later [unregister] is
  /// not held up behind them. A removal of the token, or a change of signed-in
  /// account, after this was asked for voids it: a waiting retry, or an attempt
  /// still queued, gives up rather than reverse what came after. Any other
  /// refusal (not linked, switched off) is final for now. Nothing is thrown:
  /// notifications are not worth stopping the app for, so a failure is logged and
  /// the next start tries again.
  Future<bool> register(String token) async {
    final int removals = _removals[token] ?? 0;
    final String? account = _currentAccount();
    bool stillWanted() =>
        (_removals[token] ?? 0) == removals && _currentAccount() == account;

    for (var attempt = 0; ; attempt++) {
      if (!stillWanted()) {
        log('DeviceTokenRegistrar: token ${_tail(token)} registration dropped');
        return false;
      }
      try {
        final bool sent = await _queue.run(() async {
          // Asked for while an earlier call was running, this may have been
          // voided by the time its turn comes.
          if (!stillWanted()) {
            return false;
          }
          await _identity.registerDeviceToken(token);
          return true;
        });
        return sent;
      } on IdentityFailure catch (failure) {
        final bool canTryAgain =
            failure.kind == IdentityFailureKind.transient &&
            attempt < retryDelays.length;
        log(
          'DeviceTokenRegistrar: token ${_tail(token)} not registered '
          '(${failure.reason ?? failure.code})'
          '${canTryAgain ? ', trying again' : ''}',
        );
        if (!canTryAgain) {
          return false;
        }
        await _wait(retryDelays[attempt]);
      }
    }
  }

  /// Removes [token] from the signed-in tipper, and voids any registration of it
  /// still waiting to be retried. A token the tipper does not hold is not an
  /// error. If the signed-in account changes before the removal gets its turn it
  /// is not sent: the token is no longer that account's to remove, and whoever
  /// signed in next registers it for themselves. Throws the [IdentityFailure] if
  /// the server cannot be asked or refuses, because callers such as account
  /// deletion must not carry on as if it were done.
  Future<void> unregister(String token) async {
    _removals[token] = (_removals[token] ?? 0) + 1;
    final String? account = _currentAccount();
    await _queue.run(() async {
      if (_currentAccount() != account) {
        log('DeviceTokenRegistrar: token ${_tail(token)} removal dropped');
        return;
      }
      await _identity.unregisterDeviceToken(token);
      log('DeviceTokenRegistrar: token ${_tail(token)} removed');
    });
  }

  /// The end of a token, which is enough to tell tokens apart in a log without
  /// printing a credential.
  String _tail(String token) =>
      token.length <= 4 ? token : token.substring(token.length - 4);
}
