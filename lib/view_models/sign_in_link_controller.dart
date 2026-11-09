import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:daufootytipping/services/tipper_link_service.dart';
import 'package:flutter/foundation.dart';

/// Where the sign-in page is in linking the signed-in account to its tipper.
enum LinkPhase {
  /// Working it out.
  resolving,

  /// Linked (or a guest), and the tipper has been handed over: show the app.
  ready,

  /// No record matches this account: ask for an alias.
  needsAlias,

  /// Not now (the server is busy, or there is no connection): offer to try again.
  unavailable,

  /// Refused: [SignInLinkController.message] says why.
  refused,
}

/// Holds the sign-in page's linking state for one signed-in account, so the page
/// only has to draw it. Opens from the tipper kept on the device when there is one
/// and confirms the link in the background (a delay changes nothing; a refusal
/// does), asks for an alias only when the server says none matches, and shows the
/// server's reason when it refuses.
class SignInLinkController extends ChangeNotifier {
  SignInLinkController({
    required TipperLinkService service,
    required void Function(Tipper tipper) adoptTipper,
    required Future<void> Function(String? photoUrl) syncPhoto,
    required bool canCreateTippers,
  }) : _service = service,
       _adoptTipper = adoptTipper,
       _syncPhoto = syncPhoto,
       _canCreateTippers = canCreateTippers;

  final TipperLinkService _service;
  final void Function(Tipper tipper) _adoptTipper;
  final Future<void> Function(String? photoUrl) _syncPhoto;
  final bool _canCreateTippers;

  LinkPhase _phase = LinkPhase.resolving;
  LinkPhase get phase => _phase;

  String? _message;

  /// Why the account is [LinkPhase.unavailable] or [LinkPhase.refused].
  String? get message => _message;

  String? _aliasError;

  /// Why the last alias was not accepted, for the alias dialog.
  String? get aliasError => _aliasError;

  LinkAccount? _account;
  int _generation = 0;
  bool _disposed = false;

  static const String _noLongerLinked =
      'Your account is no longer linked to a tipper. Please sign out and sign in again.';
  static const String _unexpected =
      'Something went wrong signing you in. Please try again. If it keeps happening, tap Get help.';

  /// Starts linking [account]. Calling it again for the same account does
  /// nothing; for a different account it starts over.
  Future<void> start(LinkAccount account) async {
    if (_account?.uid == account.uid) {
      return;
    }
    _account = account;
    await _begin(account);
  }

  /// Tries again after [LinkPhase.unavailable].
  Future<void> retry() async {
    final account = _account;
    if (account == null) {
      return;
    }
    await _begin(account);
  }

  /// Creates the account's tipper with [alias], after [LinkPhase.needsAlias].
  /// Returns whether it worked; if not, [aliasError] says why and the phase stays.
  Future<bool> submitAlias(String alias) async {
    final account = _account;
    if (account == null || _phase != LinkPhase.needsAlias) {
      return false;
    }
    final generation = _generation;
    _aliasError = null;
    final LinkResolution resolution;
    try {
      resolution = await _service.createWithAlias(account, alias);
    } on Object catch (error) {
      log('SignInLinkController: creating the tipper failed: $error');
      return _aliasFailed(generation, _unexpected);
    }
    if (_stale(generation)) {
      return false;
    }
    switch (resolution.status) {
      case LinkStatus.linked:
        _adoptTipper(resolution.tipper!);
        unawaited(_syncPhoto(account.photoUrl));
        _set(LinkPhase.ready);
        return true;
      case LinkStatus.refused:
      case LinkStatus.unavailable:
        return _aliasFailed(generation, resolution.message ?? _unexpected);
      case LinkStatus.needsAlias:
        return _aliasFailed(generation, 'Please choose an alias.');
      case LinkStatus.guest:
        return _aliasFailed(generation, _unexpected);
    }
  }

  bool _aliasFailed(int generation, String message) {
    if (!_stale(generation)) {
      _aliasError = message;
      notifyListeners();
    }
    return false;
  }

  Future<void> _begin(LinkAccount account) async {
    final generation = ++_generation;
    _message = null;
    _aliasError = null;
    _set(LinkPhase.resolving);

    final LinkStart start;
    try {
      start = await _service.begin(account);
    } on Object catch (error) {
      log('SignInLinkController: linking failed: $error');
      if (!_stale(generation)) {
        _message = _unexpected;
        _set(LinkPhase.refused);
      }
      return;
    }
    if (_stale(generation)) {
      return;
    }

    final cached = start.cachedTipper;
    if (cached != null) {
      _adoptTipper(cached);
      _set(LinkPhase.ready);
      unawaited(_confirm(account, generation));
      return;
    }
    _apply(start.resolution!, account);
  }

  void _apply(LinkResolution resolution, LinkAccount account) {
    switch (resolution.status) {
      case LinkStatus.linked:
        _adoptTipper(resolution.tipper!);
        unawaited(_syncPhoto(account.photoUrl));
        _set(LinkPhase.ready);
      case LinkStatus.guest:
        _adoptTipper(resolution.tipper!);
        _set(LinkPhase.ready);
      case LinkStatus.needsAlias:
        if (_canCreateTippers) {
          _set(LinkPhase.needsAlias);
        } else {
          _message = 'New tippers cannot be added right now. Please try again later. If it keeps happening, tap Get help.';
          _set(LinkPhase.refused);
        }
      case LinkStatus.unavailable:
        _message = resolution.message;
        _set(LinkPhase.unavailable);
      case LinkStatus.refused:
        _message = resolution.message;
        _set(LinkPhase.refused);
    }
  }

  /// After opening from the kept tipper: the link is confirmed or it is not. A delay
  /// leaves the app open on what it has.
  Future<void> _confirm(LinkAccount account, int generation) async {
    final LinkResolution resolution;
    try {
      resolution = await _service.refreshCached(account);
    } on Object catch (error) {
      log('SignInLinkController: confirming the link failed: $error');
      return;
    }
    if (_stale(generation)) {
      return;
    }
    switch (resolution.status) {
      case LinkStatus.linked:
        _adoptTipper(resolution.tipper!);
        unawaited(_syncPhoto(account.photoUrl));
      case LinkStatus.unavailable:
      case LinkStatus.guest:
        break;
      case LinkStatus.needsAlias:
      case LinkStatus.refused:
        _message = resolution.status == LinkStatus.refused
            ? (resolution.message ?? _noLongerLinked)
            : _noLongerLinked;
        _set(LinkPhase.refused);
    }
  }

  /// Whether a later start or retry, or disposal, has overtaken [generation].
  bool _stale(int generation) => _disposed || generation != _generation;

  void _set(LinkPhase phase) {
    _phase = phase;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
