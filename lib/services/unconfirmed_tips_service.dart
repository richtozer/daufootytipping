import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:daufootytipping/services/serial_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tip the server has not confirmed yet: handed to the database, which holds it
/// on the device until it can be sent.
@immutable
class UnconfirmedTip {
  const UnconfirmedTip({
    required this.compKey,
    required this.tipperKey,
    required this.gameKey,
    required this.choice,
    required this.submittedUtcSeconds,
    required this.gameLabel,
    required this.kickoffUtcMs,
    required this.queuedAtUtcMs,
  });

  factory UnconfirmedTip.fromJson(Map<String, Object?> json) => UnconfirmedTip(
    compKey: json['compKey'] as String,
    tipperKey: json['tipperKey'] as String,
    gameKey: json['gameKey'] as String,
    choice: json['choice'] as String,
    submittedUtcSeconds: json['submittedUtcSeconds'] as int,
    gameLabel: json['gameLabel'] as String,
    kickoffUtcMs: json['kickoffUtcMs'] as int,
    queuedAtUtcMs: json['queuedAtUtcMs'] as int,
  );

  final String compKey;
  final String tipperKey;
  final String gameKey;

  /// The result tipped, as the stored letter (`GameResult.name`).
  final String choice;

  /// When the tip was made, in the whole seconds the database stores with it. A
  /// stored tip made later than this is a newer tip, not this one.
  final int submittedUtcSeconds;

  /// Words for the user: "Home v Away".
  final String gameLabel;
  final int kickoffUtcMs;
  final int queuedAtUtcMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'compKey': compKey,
    'tipperKey': tipperKey,
    'gameKey': gameKey,
    'choice': choice,
    'submittedUtcSeconds': submittedUtcSeconds,
    'gameLabel': gameLabel,
    'kickoffUtcMs': kickoffUtcMs,
    'queuedAtUtcMs': queuedAtUtcMs,
  };

  /// Whether [other] is a tip for the same game by the same tipper in the same
  /// competition, whatever was tipped.
  bool isForSameGameAs(UnconfirmedTip other) =>
      compKey == other.compKey &&
      tipperKey == other.tipperKey &&
      gameKey == other.gameKey;

  @override
  bool operator ==(Object other) =>
      other is UnconfirmedTip &&
      isForSameGameAs(other) &&
      choice == other.choice &&
      queuedAtUtcMs == other.queuedAtUtcMs;

  @override
  int get hashCode =>
      Object.hash(compKey, tipperKey, gameKey, choice, queuedAtUtcMs);
}

/// A tip as the device's tips listener shows it: the result and when it was made.
///
/// This is what the device believes, not what the server holds. The database
/// applies a write it has not yet sent to what it shows, so a tip queued on the
/// device appears here whether or not the server ever accepts it.
typedef ShownTip = ({String choice, int submittedUtcSeconds});

/// Remembers the tips the server has not confirmed, and tells the user when one
/// turns out not to have counted.
///
/// A tip made without a connection is queued by the database, which sends it when
/// it can. The rules refuse a tip that arrives after kickoff, so a queued tip can
/// be rejected long after the screen that made it has gone, or in a later run of
/// the app, where the original write has no one left to tell. This keeps the
/// queued tips on the device so that either way the user hears about it, instead
/// of finding the game scored against a tip they believe they made.
///
/// The device cannot see from the data alone whether the server has accepted a
/// queued tip: a tip waiting to be sent and a tip the server holds look the same.
/// So a tip is never settled as counted from what the listener shows. Only the
/// write's own answer says that (in the run that made it). What the listener can
/// show is that a tip is no longer there: the database drops a refused write and
/// the tip disappears. That is believed only while the connection is up, and only
/// once it has held for [settleFor], because a tip that was in fact accepted can
/// vanish for an instant when the database replays and refuses a write it had
/// already sent.
class UnconfirmedTipsService extends ChangeNotifier {
  UnconfirmedTipsService({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? clock,
    Stream<bool?>? connectionStates,
    this.settleFor = const Duration(seconds: 3),
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now,
       _connected = connectionStates == null {
    _connectionSubscription = connectionStates?.listen(
      _connectionChanged,
      onError: (Object error, StackTrace stackTrace) =>
          _connectionChanged(false),
    );
  }

  static const String storageKey = 'unconfirmed_tips';

  /// A queued tip is forgotten this long after it was made, whatever happened to
  /// it, so the list cannot grow without end.
  static const Duration keepFor = Duration(days: 14);

  /// How long a queued tip must have been missing from the listener, with the
  /// connection up, before the user is told it did not count.
  final Duration settleFor;

  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _clock;
  final List<({String message, bool confirmed})> _notices =
      <({String message, bool confirmed})>[];
  StreamSubscription<bool?>? _connectionSubscription;

  /// Whether the database reports a live connection. Without a source of
  /// connection states (tests only) the connection is taken to be up.
  bool _connected;

  final SerialQueue _queue = SerialQueue();
  _Look? _look;
  Timer? _settleTimer;

  /// What the user should be told, oldest first, until [takeNotices].
  List<String> get notices => <String>[
    for (final ({String message, bool confirmed}) notice in _notices)
      notice.message,
  ];

  /// The tips now waiting for the server.
  Future<List<UnconfirmedTip>> pending() => _queue.run(_load);

  /// [tip] is about to be handed to the database, which holds it on the device
  /// until it can be sent. Call it before the write, so that a process that ends
  /// before the write is answered still leaves the record behind. A newer tip for
  /// the same game replaces an older one.
  Future<void> queued(UnconfirmedTip tip) => _queue.run(() async {
    final List<UnconfirmedTip> all = await _load();
    all
      ..removeWhere(tip.isForSameGameAs)
      ..add(tip);
    await _save(all);
  });

  /// The write for [tip] has been answered where the user can see it (accepted,
  /// or refused while the screen was still waiting and so reported there), or
  /// accepted after the screen stopped waiting. Nothing is outstanding, and
  /// nothing is said.
  Future<void> answered(UnconfirmedTip tip) => _queue.run(() => _forget(tip));

  /// The server refused [tip] after the screen had stopped waiting. A tip that a
  /// newer one for the same game has replaced says nothing: the newer one will
  /// report for itself.
  Future<void> rejected(UnconfirmedTip tip) => _queue.run(() async {
    if (!await _forget(tip)) {
      return;
    }
    _notices.add((message: _refusedNotice(tip), confirmed: true));
    notifyListeners();
  });

  /// Looks at what the tips listener now shows ([shown], for a game key; null if
  /// no tip) for [tipperKey] in [compKey], against the tips queued earlier. Call
  /// it whenever that changes.
  ///
  /// A queued tip shown as queued stays queued: that says nothing about the
  /// server. One replaced by a newer tip is forgotten, silently. One that is not
  /// shown at all is believed lost only if it stays missing for [settleFor] with
  /// the connection up (see the class comment); then the user is told, and the
  /// tip forgotten.
  Future<void> observe({
    required String compKey,
    required String tipperKey,
    required ShownTip? Function(String gameKey) shown,
  }) {
    _look = _Look(compKey: compKey, tipperKey: tipperKey, shown: shown);
    return _queue.run(() => _review(announce: false));
  }

  /// Stops looking at the listener: the screen it belongs to has gone.
  void stopObserving() {
    _look = null;
    _settleTimer?.cancel();
    _settleTimer = null;
  }

  /// Hands over the notices and clears them, so each is shown exactly once and one
  /// that arrives while the others are on screen is kept for the next time.
  /// [allConfirmed] is true only if every notice reports a write the server
  /// actually refused; any other notice is an inference from the tips the device
  /// shows, and is worded as one.
  ({List<String> messages, bool allConfirmed}) takeNotices() {
    final taken = (
      messages: notices,
      allConfirmed: _notices.every(
        (({String message, bool confirmed}) notice) => notice.confirmed,
      ),
    );
    _notices.clear();
    return taken;
  }

  @override
  void dispose() {
    stopObserving();
    unawaited(_connectionSubscription?.cancel());
    super.dispose();
  }

  void _connectionChanged(bool? connected) {
    _connected = connected == true;
    if (!_connected) {
      // The wait is for time spent connected: a drop, however brief, starts it
      // again once the connection is back.
      _settleTimer?.cancel();
      _settleTimer = null;
      return;
    }
    unawaited(_queue.run(() => _review(announce: false)));
  }

  /// With [announce] false, forgets tips that newer ones have replaced and starts
  /// the wait for those that are missing. With it true (the wait is over), tells
  /// the user about the tips still missing.
  Future<void> _review({required bool announce}) async {
    final _Look? look = _look;
    if (look == null) {
      return;
    }
    final List<UnconfirmedTip> all = await _load();
    final List<UnconfirmedTip> keep = <UnconfirmedTip>[];
    var anyMissing = false;
    var told = false;
    for (final UnconfirmedTip tip in all) {
      if (tip.compKey != look.compKey || tip.tipperKey != look.tipperKey) {
        keep.add(tip);
        continue;
      }
      switch (_standing(tip, look.shown(tip.gameKey))) {
        case _Standing.shown:
          keep.add(tip);
        case _Standing.replaced:
          break;
        case _Standing.missing when !_connected:
          keep.add(tip);
        case _Standing.missing when announce:
          _notices.add((
            message: _couldNotConfirmNotice(tip),
            confirmed: false,
          ));
          told = true;
        case _Standing.missing:
          anyMissing = true;
          keep.add(tip);
      }
    }
    if (keep.length != all.length) {
      await _save(keep);
    }
    if (anyMissing && !(_settleTimer?.isActive ?? false)) {
      _settleTimer = Timer(settleFor, () {
        unawaited(_queue.run(() => _review(announce: true)));
      });
    } else if (!anyMissing) {
      _settleTimer?.cancel();
      _settleTimer = null;
    }
    if (told) {
      notifyListeners();
    }
  }

  _Standing _standing(UnconfirmedTip tip, ShownTip? shown) {
    if (shown == null) {
      return _Standing.missing;
    }
    if (shown.choice == tip.choice) {
      return _Standing.shown;
    }
    return shown.submittedUtcSeconds > tip.submittedUtcSeconds
        ? _Standing.replaced
        : _Standing.missing;
  }

  String _refusedNotice(UnconfirmedTip tip) =>
      'Your tip for ${tip.gameLabel} was not counted. The server did not accept '
      'it, most likely because the game had started before it arrived.';

  /// For a tip the device no longer shows, which is an inference: the database
  /// may simply not have caught up, so it is not said to have been refused.
  String _couldNotConfirmNotice(UnconfirmedTip tip) =>
      tip.kickoffUtcMs <= _clock().toUtc().millisecondsSinceEpoch
      ? 'We could not confirm your tip for ${tip.gameLabel}. It may not have '
            'reached the server before the game started. Please check it on the '
            'Tips page.'
      : 'We could not confirm your tip for ${tip.gameLabel}. Please check it on '
            'the Tips page, and tip again if it is missing.';

  Future<bool> _forget(UnconfirmedTip tip) async {
    final List<UnconfirmedTip> all = await _load();
    final int before = all.length;
    all.removeWhere((UnconfirmedTip other) => other == tip);
    if (all.length == before) {
      return false;
    }
    await _save(all);
    return true;
  }

  Future<List<UnconfirmedTip>> _load() async {
    try {
      final SharedPreferences prefs = await _preferences();
      final String? text = prefs.getString(storageKey);
      if (text == null) {
        return <UnconfirmedTip>[];
      }
      final int oldestMs = _clock()
          .toUtc()
          .subtract(keepFor)
          .millisecondsSinceEpoch;
      return <UnconfirmedTip>[
        for (final Object? entry in jsonDecode(text) as List<Object?>)
          if (UnconfirmedTip.fromJson(Map<String, Object?>.from(entry as Map))
              case final UnconfirmedTip tip when tip.queuedAtUtcMs >= oldestMs)
            tip,
      ];
    } on Object catch (error) {
      log('UnconfirmedTipsService: could not read the queued tips: $error');
      return <UnconfirmedTip>[];
    }
  }

  Future<void> _save(List<UnconfirmedTip> tips) async {
    try {
      final SharedPreferences prefs = await _preferences();
      if (tips.isEmpty) {
        await prefs.remove(storageKey);
        return;
      }
      await prefs.setString(
        storageKey,
        jsonEncode(<Object?>[
          for (final UnconfirmedTip tip in tips) tip.toJson(),
        ]),
      );
    } on Object catch (error) {
      log('UnconfirmedTipsService: could not keep the queued tips: $error');
    }
  }
}

/// How a queued tip stands against what the listener shows.
enum _Standing {
  /// The listener shows this very tip: queued or accepted, the device cannot say.
  shown,

  /// The listener shows a newer tip for the game, so this one is history.
  replaced,

  /// The listener shows no tip for the game, or only an older one.
  missing,
}

class _Look {
  const _Look({
    required this.compKey,
    required this.tipperKey,
    required this.shown,
  });

  final String compKey;
  final String tipperKey;
  final ShownTip? Function(String gameKey) shown;
}
