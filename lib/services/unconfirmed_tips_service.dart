import 'dart:convert';
import 'dart:developer';

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
    required this.gameLabel,
    required this.kickoffUtcMs,
    required this.queuedAtUtcMs,
  });

  factory UnconfirmedTip.fromJson(Map<String, Object?> json) => UnconfirmedTip(
    compKey: json['compKey'] as String,
    tipperKey: json['tipperKey'] as String,
    gameKey: json['gameKey'] as String,
    choice: json['choice'] as String,
    gameLabel: json['gameLabel'] as String,
    kickoffUtcMs: json['kickoffUtcMs'] as int,
    queuedAtUtcMs: json['queuedAtUtcMs'] as int,
  );

  final String compKey;
  final String tipperKey;
  final String gameKey;

  /// The result tipped, as the stored letter (`GameResult.name`).
  final String choice;

  /// Words for the user: "Home v Away".
  final String gameLabel;
  final int kickoffUtcMs;
  final int queuedAtUtcMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'compKey': compKey,
    'tipperKey': tipperKey,
    'gameKey': gameKey,
    'choice': choice,
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

/// Remembers the tips the server has not confirmed, and tells the user when one
/// turns out not to have counted.
///
/// A tip made without a connection is queued by the database, which sends it when
/// it can. The rules refuse a tip that arrives after kickoff, so a queued tip can
/// be rejected long after the screen that made it has gone, or in a later run of
/// the app, where the original write has no one left to tell. This keeps the
/// queued tips on the device so that either way the user hears about it, instead
/// of finding the game scored against a tip they believe they made.
class UnconfirmedTipsService extends ChangeNotifier {
  UnconfirmedTipsService({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now;

  static const String storageKey = 'unconfirmed_tips';

  /// A queued tip is forgotten this long after it was made, whatever happened to
  /// it, so the list cannot grow without end.
  static const Duration keepFor = Duration(days: 14);

  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _clock;
  final List<String> _notices = <String>[];

  /// What the user should be told, oldest first, until [takeNotices].
  List<String> get notices => List<String>.unmodifiable(_notices);

  /// The tips now waiting for the server.
  Future<List<UnconfirmedTip>> pending() => _load();

  /// [tip] has been handed to the database but not confirmed. A newer tip for the
  /// same game replaces an older one.
  Future<void> queued(UnconfirmedTip tip) async {
    final List<UnconfirmedTip> all = await _load();
    all
      ..removeWhere(tip.isForSameGameAs)
      ..add(tip);
    await _save(all);
  }

  /// The server confirmed [tip] after all.
  Future<void> accepted(UnconfirmedTip tip) async {
    await _forget(tip);
  }

  /// The server refused [tip] after the screen had stopped waiting. A tip that a
  /// newer one for the same game has replaced says nothing: the newer one will
  /// report for itself.
  Future<void> rejected(UnconfirmedTip tip) async {
    if (!await _forget(tip)) {
      return;
    }
    _notices.add(
      'Your tip for ${tip.gameLabel} was not counted. The server did not accept '
      'it, most likely because the game had started before it arrived.',
    );
    notifyListeners();
  }

  /// Settles the tips queued in an earlier run, for [compKey] and [tipperKey]
  /// only. [storedChoice] gives what the server holds for a game (the stored
  /// letter, or null if no tip). A queued tip the server now holds is forgotten.
  /// One it does not hold, for a game that has started, never arrived in time: the
  /// user is told. One for a game still to start stays queued, because it may yet
  /// be sent.
  Future<void> reconcile({
    required String compKey,
    required String tipperKey,
    required String? Function(String gameKey) storedChoice,
  }) async {
    final int nowMs = _clock().toUtc().millisecondsSinceEpoch;
    final List<UnconfirmedTip> all = await _load();
    final List<UnconfirmedTip> keep = <UnconfirmedTip>[];
    var told = false;
    for (final UnconfirmedTip tip in all) {
      if (tip.compKey != compKey || tip.tipperKey != tipperKey) {
        keep.add(tip);
        continue;
      }
      if (storedChoice(tip.gameKey) == tip.choice) {
        continue;
      }
      if (tip.kickoffUtcMs <= nowMs) {
        _notices.add(
          'Your tip for ${tip.gameLabel} never reached the server before the '
          'game started, so it was not counted.',
        );
        told = true;
        continue;
      }
      keep.add(tip);
    }
    if (keep.length != all.length) {
      await _save(keep);
    }
    if (told) {
      notifyListeners();
    }
  }

  /// Hands over the notices and clears them, so each is shown exactly once and one
  /// that arrives while the others are on screen is kept for the next time.
  List<String> takeNotices() {
    final List<String> taken = List<String>.of(_notices);
    _notices.clear();
    return taken;
  }

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
