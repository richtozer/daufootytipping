# Temporary mechanisms

Anything built to be removed later is listed here with the condition that removes it. Add an entry in
the same change that adds the mechanism, and delete the entry in the change that removes it. The list is
reviewed each off-season.

A mechanism is temporary if it exists for a migration, a coexistence period, a platform limit or a
deferred upgrade, and the code would be simpler without it.

| Mechanism | Where | Remove when |
| --- | --- | --- |
| TypeScript Realtime Database and scheduled triggers that hand their work to the Dart HTTPS functions | `functions/src/` | Firebase supports Realtime Database and scheduled triggers for Dart functions in production. See `DESIGN-backend-scoring-wrapper-dart.md`. |
| Identity coexistence with 1.4.x clients: the `pilot` and `coexist` server modes, the legacy public tipper shape they write, the backfill tool, and the rulesets that precede R2 | `functions_dart/lib/identity/`, `functions_dart/bin/identity_backfill.dart`, `config/generated/` | The rollback to R1-compat is retired. The trigger and the full list of what goes are in `DESIGN-database-rules-phase4.md`, section 13. |
| `deprecated_member_use: ignore` for the whole app | `analysis_options.yaml` | The dependencies named beside it in that file no longer bind to `package:flutter/material.dart` types, so the app can move to `material_ui`. |
| `prefer_initializing_formals: false` | `analysis_options.yaml` | The existing constructors are migrated. |
| Golden images are not compared on CI runners (`SKIP_GOLDEN_COMPARISON`) | `test/flutter_test_config.dart`, `.github/workflows/checks.yml`, `.github/workflows/android-play.yml` | Golden tests render the same pixels on a runner as on the Mac, for example by generating the goldens on the runner. |
| Firestore `tipLogs` to `tipLogs2` migration script | `tools/firestore/migrate_tip_logs_to_tip_logs2.js`, `migrate:tiplogs` in `package.json`, its section in `README.md` | The owner confirms the old `tipLogs` collection is migrated or no longer wanted. |
| Comparison of backend scoring with the retired client-computed `round_stats_v3` and `game_stats_v3` | `scripts/compare_backend_round_stats.mjs`, its test, `compare:backend-scoring` in `package.json` | Those two nodes are deleted from the database, or the owner no longer wants the comparison. |
| Files that only re-export `dau_shared` | `lib/models/` (every file but `league.dart`, which also adds the league colours), the re-exports in `lib/services/`, the first line of `lib/constants/paths.dart` | The app imports `package:dau_shared` directly. |
| iOS builds on the `xcode-27` preview runner, selecting Xcode 27.3 or 27.2 by name | `.github/workflows/ios-testflight.yml` | `macos-latest` ships Xcode 27.2 or later as its default, so the job can go back to `macos-latest` and the image default. |
