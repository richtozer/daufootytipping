import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_functions/firebase_functions.dart' hide DataSnapshot;
import 'package:firebase_admin/firebase_admin.dart';
import 'package:firebase_admin/src/database.dart';
import 'package:firebase_dart/database.dart';
import 'package:firebase_dart/standalone_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:intl/intl.dart';

void main(List<String> args) async {
  await runFunctions((firebase) {
    firebase.https.onCall(
      name: 'adminFixtureDownload',
      (request, response) async {
        // 1. Verify caller authentication
        final auth = request.auth;
        if (auth == null) {
          throw UnauthenticatedError('User must be authenticated');
        }

        final uid = auth.uid;

        // 2. Initialize Firebase Admin SDK using Application Default Credentials
        final credential = Credentials.applicationDefault();
        if (credential == null) {
          throw InternalError('Failed to load application default credentials');
        }

        final adminApp = FirebaseAdmin.instance.initializeApp(
          AppOptions(
            credential: credential,
          ),
        );

        final db = adminApp.database();

        try {
          final data = request.data as Map<String, dynamic>?;
          final compKey = data?['compKey'] as String?;
          if (compKey == null || compKey.isEmpty) {
            throw InvalidArgumentError('Missing required parameter: compKey');
          }

          final resultMsg = await executeFixtureDownload(
            authUid: uid,
            compKey: compKey,
            db: db,
            fetchFixtureJson: _fetchFixtureJson,
            now: DateTime.now().toUtc(),
          );

          return CallableResult({
            'success': true,
            'message': resultMsg,
          });
        } finally {
          // Dispose of admin app
          await adminApp.delete();
        }
      },
    );
  });
}

Future<String> executeFixtureDownload({
  required String authUid,
  required String compKey,
  required Database db,
  required Future<List<dynamic>> Function(Uri url) fetchFixtureJson,
  required DateTime now,
}) async {
  // 3. Verify user has admin role by querying AllTippers indexed by authuid
  final DatabaseReference tippersRef = db.ref('/AllTippers');
  final Query roleQuery = tippersRef.orderByChild('authuid').equalTo(authUid);
  final DataSnapshot roleSnapshot = await roleQuery.once();
  final roleVal = roleSnapshot.value;
  if (roleVal == null || roleVal is! Map || roleVal.isEmpty) {
    throw PermissionDeniedError('User is not authorized as admin');
  }
  final tipperData = Map<String, dynamic>.from(roleVal).values.first;
  final role = (tipperData as Map)['tipperRole'] as String?;
  if (role != 'admin') {
    throw PermissionDeniedError('User is not authorized as admin');
  }

  // 5. Fetch DAUComp configuration from DB
  final DatabaseReference compRef = db.ref('/AllDAUComps/$compKey');
  final DataSnapshot compSnapshot = await compRef.once();
  final compRaw = compSnapshot.value;
  if (compRaw == null) {
    throw NotFoundError('DAUComp not found for key: $compKey');
  }

  final compData = Map<String, dynamic>.from(compRaw as Map);
  
  // Deserialize DAUComp without rounds first (rounds will be filled/parsed if present)
  final dauroundsList = <DAURound>[];
  final rawRounds = compData['combinedRounds2'];
  if (rawRounds != null) {
    if (rawRounds is List) {
      for (var i = 0; i < rawRounds.length; i++) {
        if (rawRounds[i] != null) {
          dauroundsList.add(DAURound.fromJson(Map<String, dynamic>.from(rawRounds[i] as Map), i + 1));
        }
      }
    } else if (rawRounds is Map) {
      rawRounds.forEach((key, val) {
        final idx = int.tryParse(key.toString()) ?? 0;
        if (val != null) {
          dauroundsList.add(DAURound.fromJson(Map<String, dynamic>.from(val as Map), idx + 1));
        }
      });
    }
  }

  final comp = DAUComp.fromJson(compData, compKey, dauroundsList);

  // 6. Attempt to acquire distributed download lock (with 24h TTL)
  final DatabaseReference lockRef = db.ref('/AllDAUComps/$compKey/downloadLock');
  final DataSnapshot lockSnapshot = await lockRef.once();
  if (lockSnapshot.value != null) {
    DateTime? lockTimestamp;
    if (lockSnapshot.value is String) {
      lockTimestamp = DateTime.tryParse(lockSnapshot.value as String);
    }
    if (lockTimestamp != null) {
      if (now.difference(lockTimestamp) < const Duration(hours: 24)) {
        throw AbortedError('Fixture download is already in progress.');
      }
    }
  }

  // Acquire lock (simple timestamp string matching client)
  await lockRef.set(now.toIso8601String());

  try {
    // Helper to log status updates
    Future<void> logStatus(String status, {String? error}) async {
      final DatabaseReference statusRef = db.ref('/Stats/$compKey/scoring_status');
      final statusData = <String, dynamic>{
        'status': status,
        'updatedAt': now.toIso8601String(),
      };
      if (error != null) {
        statusData['error'] = error;
      }
      await statusRef.set(statusData);
    }

    await logStatus('fetching_fixtures');

    // 7. Perform HTTP GET to AFL and NRL fixture URLs
    final nrlGames = await fetchFixtureJson(comp.nrlFixtureJsonURL);
    final aflGames = await fetchFixtureJson(comp.aflFixtureJsonURL);

    await logStatus('applying_updates');

    // Build and apply per-game updates
    final importApplier = const FixtureImportApplier();
    final ops = importApplier.buildGameUpdates(nrlGames, aflGames);

    final dbUpdates = <String, dynamic>{};

    // Fetch existing teams to ensure they exist in /Teams
    final DatabaseReference teamsRef = db.ref('/Teams');
    final DataSnapshot teamsSnapshot = await teamsRef.once();
    final Map<String, dynamic> existingTeams = teamsSnapshot.value != null
        ? Map<String, dynamic>.from(teamsSnapshot.value as Map)
        : {};

    void ensureTeamExists(String teamName, String league) {
      final teamKey = '$league-${teamName.toLowerCase()}';
      if (!existingTeams.containsKey(teamKey)) {
        dbUpdates['/Teams/$teamKey'] = {
          'name': teamName,
          'league': league,
          'logoURI': null,
        };
        existingTeams[teamKey] = true;
      }
    }

    for (final op in ops) {
      for (final entry in op.attributes.entries) {
        dbUpdates['/DAUCompsGames/$compKey/${op.dbkey}/${entry.key}'] = entry.value;
      }
      final homeTeam = op.attributes['HomeTeam'] as String?;
      final awayTeam = op.attributes['AwayTeam'] as String?;
      if (homeTeam != null) ensureTeamExists(homeTeam, op.league);
      if (awayTeam != null) ensureTeamExists(awayTeam, op.league);
    }

    // Tag games with league in-place to calculate combined rounds if missing
    importApplier.tagGamesWithLeagueInPlace(nrlGames, 'nrl');
    importApplier.tagGamesWithLeagueInPlace(aflGames, 'afl');

    final allGames = [...nrlGames, ...aflGames];
    final combined = importApplier.computeCombinedRoundsIfMissing(comp, allGames);
    if (combined != null) {
      for (var i = 0; i < combined.length; i++) {
        final round = combined[i];
        final startDateStr = '${DateFormat('yyyy-MM-dd HH:mm:ss').format(round.firstGameKickOffUTC)}Z';
        final endDateStr = '${DateFormat('yyyy-MM-dd HH:mm:ss').format(round.lastGameKickOffUTC)}Z';
        dbUpdates['/AllDAUComps/$compKey/combinedRounds2/$i/roundStartDate'] = startDateStr;
        dbUpdates['/AllDAUComps/$compKey/combinedRounds2/$i/roundEndDate'] = endDateStr;
      }
    }

    // Update last fixture update timestamp
    dbUpdates['/AllDAUComps/$compKey/lastFixtureUTC'] = now.toIso8601String();

    // Perform multi-path update in the database
    await db.ref('/').update(dbUpdates);

    // Log status success
    await logStatus('success');

    return 'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
  } finally {
    // Release lock
    await lockRef.set(null);
  }
}

Future<List<dynamic>> _fetchFixtureJson(Uri url) async {
  final response = await http.get(url, headers: {'Content-Type': 'application/json; charset=UTF-8'});
  if (response.statusCode == 200) {
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is List) {
      return decoded;
    }
    throw Exception('Expected list, got ${decoded.runtimeType}');
  }
  throw Exception('Failed to fetch fixture from $url: ${response.statusCode}');
}
