// Deployed Cloud Functions endpoint ids, shared by the Flutter client and the
// Dart functions runtime so both bind to one definition.
//
// These strings are a WIRE CONTRACT, not internal identifiers. They are the
// deployed Cloud Run service names, and they are referenced by:
//   - the Flutter client, which invokes the admin callables by name
//   - functions_dart/bin/server.dart, which declares them as `name:`
//   - the TypeScript wrapper functions, which call the Dart functions over
//     HTTP (functions/src/backend_scoring.ts, app_badge.ts,
//     fixture_download_scheduler.ts) - those cannot import this file, so keep
//     them in sync by hand
//   - scripts/start_local_backend.sh
//
// Renaming any of these renames a deployed function. Already-installed app
// versions call the old name forever, so treat them as frozen.
//
// Cloud Run service names must be lowercase and hyphenated. firebase_functions
// 0.7 lowercases the declared `name:` as-is (0.6 kebab-cased camelCase for
// you), so these are written in their final hyphenated form.

/// Admin callable: downloads the fixture for a competition.
const String adminFixtureDownloadEndpoint = 'admin-fixture-download';

/// Admin callable: rebuilds backend scoring for a competition.
const String adminScoringRescoreEndpoint = 'admin-scoring-rescore';

/// Admin callable: checks whether a fixture URL is reachable.
const String adminCheckFixtureUrlEndpoint = 'admin-check-fixture-url';

/// Invoked by the TypeScript RTDB triggers to run backend scoring.
const String backendScoringCommandEndpoint = 'backend-scoring-command';

/// Invoked by the TypeScript pubsub scheduler to download fixtures.
const String scheduledFixtureDownloadEndpoint = 'scheduled-fixture-download';

/// Invoked by the TypeScript triggers to recalculate app badge counts.
const String appBadgeCountEndpoint = 'app-badge-count';
