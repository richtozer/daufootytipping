import 'dart:async';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Opens the stream of raw `/TeamLogos` values the view model listens to.
typedef TeamLogosSource = Stream<Object?> Function();

/// Holds every team's logo as SVG text, keyed by team database key.
///
/// Logos live in the database at `/TeamLogos/{teamDbKey}` so they can change
/// without an app release. The node is read once a user is signed in and kept
/// in sync by a listener; on mobile the database's offline persistence keeps
/// the last copy for the next cold start.
class TeamLogosViewModel extends ChangeNotifier {
  /// Listens to `/TeamLogos`, or to [source] when one is given (tests).
  TeamLogosViewModel({TeamLogosSource? source})
    : _source = source ?? _databaseSource {
    _subscription = _source().listen(_handleValue);
  }

  final TeamLogosSource _source;
  late final StreamSubscription<Object?> _subscription;
  Map<String, String> _svgByTeamKey = const {};

  static Stream<Object?> _databaseSource() => authAwareStream<DatabaseEvent>(
    signedIn: firebaseSignedInStream,
    open: () => configuredDatabaseRef().child(p.teamLogosPathRoot).onValue,
  ).map((event) => event.snapshot.value);

  /// The SVG text for [teamDbKey], or null when the team has no logo yet.
  ///
  /// Team keys are matched case-insensitively, like `TeamsViewModel.findTeam`.
  String? svgFor(String teamDbKey) => _svgByTeamKey[teamDbKey.toLowerCase()];

  void _handleValue(Object? value) {
    final Map<String, String> svgByTeamKey = {};
    if (value is Map) {
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final Object? logo = entry.value;
        if (logo is! Map) continue;
        final Object? svg = logo[teamLogoSvgKey];
        if (svg is String && svg.isNotEmpty) {
          svgByTeamKey['${entry.key}'.toLowerCase()] = svg;
        }
      }
    }
    _svgByTeamKey = svgByTeamKey;
    notifyListeners();
  }

  /// Stores [svg] as the logo for [teamDbKey]. Admin only under the rules.
  ///
  /// The UI updates when the listener receives the change.
  Future<void> saveLogo({
    required String teamDbKey,
    required String svg,
  }) async {
    await configuredDatabaseRef()
        .child('${p.teamLogosPathRoot}/$teamDbKey')
        .set(<String, String>{
          teamLogoSvgKey: svg,
          teamLogoUpdatedUtcKey: DateTime.now().toUtc().toIso8601String(),
        });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// Field holding the SVG text under `/TeamLogos/{teamDbKey}`.
const String teamLogoSvgKey = 'svg';

/// Field holding when the logo was last uploaded, as an ISO 8601 UTC string.
const String teamLogoUpdatedUtcKey = 'updatedUtc';

/// The largest logo the database rules accept, in characters.
const int maxTeamLogoSvgLength = 65536;
