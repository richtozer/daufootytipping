# Design: Backend Scoring via Firebase Cloud Functions

**Status:** Workstream A (fixture download) is ready to implement. Workstream B (full scoring migration) is deferred pending official Dart Cloud Functions support.
**Created:** 2025-03-21
**Last updated:** 2026-03-26

---

## Motivation

Scoring currently runs entirely on the Flutter client. `StatsViewModel` calculates round stats, writes them to Firebase RTDB, and manages a `ScoringUpdateQueue` to debounce rapid updates. This is fragile because:

- App can be backgrounded or killed mid-calculation
- Multiple clients can race to write scores simultaneously
- If no one opens the app, scores don't update
- Queue state is lost on app restart
- Live score submissions trigger recalculation only on the submitter's device
- Only admin clients download fixtures — if the admin doesn't open the app, official scores never arrive and rescoring never happens
- Stale `/Stats/{comp}/live_scores_v1/{game}` rows can outlive official fixture scores, which leaves warning UI visible unless readers defensively ignore them

## Target Architecture (End State)

**"Event-Driven Backend Scoring"** — Cloud Functions handle fixture downloads, official-score-triggered rescoring, and eventually all scoring. The client becomes a read-only consumer of scores.

```
                                writes tip/live score
┌──────────────┐ ──────────────────────────────→ ┌─────────────────────────┐
│  Flutter App  │                                 │  Firebase RTDB          │
│  (read-only   │ ←── listens to stats ────────── │                         │
│   for scores) │                                 └────────┬────────────────┘
└──────────────┘                                           │ DB triggers
                                                           ↓
                                              ┌────────────────────────────┐
             NRL/AFL fixture APIs             │  Cloud Functions            │
                    ↑                         │                            │
                    │ HTTP GET                │  Workstream A (TypeScript): │
                    └─────────────────────────│  - scheduledFixtureDownload│
                                              │  - adminFixtureDownload   │
                                              │                            │
                                              │  Workstream B (Dart):      │
                                              │  - onTipWritten            │
                                              │  - onLiveScoreWritten     │
                                              │  - scheduledRescore       │
                                              │  - adminRescore           │
                                              └────────────────────────────┘
```

---

## Two Independent Workstreams

The migration is split into two workstreams that can be implemented independently:

| | Workstream A: Fixture Download | Workstream B: Full Scoring Migration |
|---|---|---|
| **Scope** | Fixture download + fixture-triggered rescoring | Tip-triggered, live-score-triggered rescoring, admin rescore |
| **Language** | TypeScript (existing `functions/` project) | Dart (waiting for official Cloud Functions support) |
| **Blocker** | None — ready to implement now | Official Dart Cloud Functions support |
| **Value** | Automatic fixture updates, no admin dependency, reliable fixture-triggered rescoring | Fully authoritative backend scoring, client becomes read-only |
| **Client changes** | Admin "Download" button → callable; no other changes | Remove all scoring logic, switch to v2 paths |

**Why TypeScript for Workstream A:** Fixture download does not need to share scoring logic with the client. It fetches JSON from external APIs, writes game attributes to RTDB, and rescores affected rounds. The existing TypeScript Cloud Functions project (`functions/src/index.ts`) is already set up.

**Workstream A is not trivial.** While the fixture download itself is straightforward, the bundled fixture-triggered rescoring requires porting a substantial chunk of scoring logic to TypeScript: game result calculation, scoring lookup tables, round stats aggregation, game stats with paid/free cohorts, and DAU round resolution. This is a partial scoring migration, not just a file download. The effort estimate reflects this.

**Why Dart for Workstream B:** The scoring logic (DAU round resolution, live-score precedence, game stats with paid/free cohorts, round stats aggregation) is complex and already implemented in Dart. Porting to TypeScript would create a maintenance burden. With Dart Cloud Functions, the scoring logic can be a shared pure-Dart package — but this requires extracting it from Flutter-entangled code first (see Pre-requisites below).

---

# Workstream A: Backend Fixture Download (TypeScript)

## Cloud Functions

### 1. `scheduledFixtureDownload` — Scheduled Function

**Trigger:** Cron schedule during season (e.g. every 4 hours during game days, daily otherwise)

**Behaviour:**
- Reads the current DAUComp config from `/AppConfig/currentDAUComp`
- Reads the fixture URLs (`nrlFixtureJsonURL`, `aflFixtureJsonURL`) from the DAUComp
- Downloads fixture data from the external NRL/AFL JSON APIs (same URLs the client uses today)
- Compares fetched data against current game records in RTDB
- If this is a new comp with no DAU rounds defined, bootstraps combined rounds from the fixture data (see "Combined Rounds Bootstrap" below)
- Batch-writes ALL changed game attributes (scores, times, venues, etc.) in a single `db.update()` call
- After the batch write completes, collects the set of affected DAU rounds (any round containing a game whose score changed)
- Performs ONE full rescore per affected round (not per game, not per score field)
- Deletes any stale `/Stats/{comp}/live_scores_v1/{game}` rows for games that now have both official scores, as part of the same backend flow that writes those official scores
- Updates `lastFixtureUpdateTimestampUTC` on the DAUComp
- Writes rescored stats to v1 paths (same paths the client writes to today)

**Why batch-then-rescore:** Individual DB triggers on `HomeTeamScore`/`AwayTeamScore` would fire up to 32 times per round (16 games × 2 scores), each triggering a full round rescore with incomplete intermediate data. This causes scores to flip-flop until the last write lands. By owning the entire download-and-rescore pipeline, the function writes all scores first, then rescores once with complete data.

**Distributed lock:** Uses the same lock mechanism as today (`/AllDAUComps/{compKey}/downloadLock`) to prevent concurrent downloads from the scheduled function and admin-triggered downloads.

### 2. `adminFixtureDownload` — HTTP Callable

**Trigger:** HTTP callable, auth-gated to admin users

**Behaviour:**
- Same logic as `scheduledFixtureDownload` but triggered on-demand by the admin
- Replaces the current admin "Download" button which calls `getNetworkFixtureData()` on the client
- Returns status to the caller (number of games updated, rounds rescored)
- Uses the same distributed lock to prevent overlap with the scheduled download

**Why keep admin-triggered downloads?** The scheduled download covers normal operations, but admins sometimes need to force an immediate refresh (e.g. after a fixture change, or during a live round when they want scores updated now rather than waiting for the next scheduled run).

## Combined Rounds Bootstrap

The current client fixture-import path includes a "bootstrap combined rounds if missing" step: when a new competition has no DAU round definitions, the client creates them from the fixture data by grouping games into rounds based on date proximity. This happens in `FixtureImportApplier.computeCombinedRoundsIfMissing()`.

The backend fixture download must replicate this behaviour:
- After downloading fixtures, check if the DAUComp has existing rounds (`combinedRounds2` path)
- If no rounds exist, compute combined rounds from the fetched game data (same grouping logic as `computeCombinedRoundsIfMissing`)
- Write the computed rounds to the database before proceeding with rescoring
- If rounds already exist, skip this step (existing behaviour)

This is a one-time-per-competition operation, not a recurring concern. But without it, the backend fixture download is not a complete replacement for the client flow during new-comp initialization.

## Admin Authorization

The app's admin concept currently lives in RTDB as `tipperRole` on the `/AllTippers/{tipperId}` record, not in Firebase Auth custom claims. The `adminFixtureDownload` callable needs to verify admin status server-side.

**Options:**
1. **RTDB lookup (simplest):** The callable reads the caller's `auth.uid`, looks up their tipper record via the `authuid` index on `/AllTippers`, and checks `tipperRole == 'admin'`. This is a single indexed read per callable invocation — cheap and straightforward.
2. **Custom claims (better long-term):** Sync `tipperRole` to Firebase Auth custom claims via a Cloud Function trigger on `/AllTippers/{tipperId}/tipperRole`. Callables then check `context.auth.token.admin == true` without any DB read. More robust but requires an additional sync function.

**Recommendation:** Start with option 1 (RTDB lookup). Migrate to custom claims later if needed — the callable interface doesn't change, only the internal auth check.

## Scoring Within Fixture Download

The fixture download function needs to rescore affected rounds after writing official scores. This means it needs scoring logic — but only the subset needed for fixture-triggered rescoring:

- Game result calculation from official scores (margin thresholds per league)
- Tip score lookup table
- Round stats aggregation per tipper
- Game stats calculation (paid/free cohorts)
- DAU round resolution (which round does this game belong to?)

This scoring logic is **ported to TypeScript within the fixture download function** — it does not need to be shared with the client. The client continues to do its own tip-triggered and live-score-triggered rescoring using the existing Dart code until Workstream B.

**Risk of drift:** The TypeScript scoring logic could diverge from the Dart client logic. This is mitigated by:
- The scoring lookup tables are static data, not complex logic
- Game result calculation (margin thresholds) is straightforward
- The fixture download function is the authoritative writer — if its scores are "correct" by definition, drift only matters if users see different scores inline vs on the leaderboard, which is unlikely given the lookup tables are trivial
- Comprehensive test vectors generated from the Dart implementation validate the TypeScript port

## Workstream A: Migration Plan

### Phase A1: Shadow Deploy, Validate

**Goal:** Backend fixture download runs in shadow mode. It writes rescored stats to **v2 paths only** — never to v1. The client continues writing v1 as usual, providing a clean baseline for comparison.

1. Deploy `scheduledFixtureDownload` writing fixture data (game attributes) to production RTDB paths (these are shared — games are games), but writing **rescored stats to v2 paths only** (`round_stats_v2`, `game_stats_v2`)
2. Admin continues to trigger client-side fixture downloads and rescoring to v1 as usual
3. Deploy a comparison function (scheduled, e.g. after each round completes) that reads both v1 (client-written) and v2 (backend-written) and logs discrepancies in both round_stats and game_stats (including paid/free cohorts)
4. v1 remains a clean client-written baseline — the backend does not touch it, so any difference is a genuine logic discrepancy between the TypeScript and Dart scoring implementations
5. Run for 1-2 rounds, monitoring for drift
6. Fix any discrepancies in the TypeScript logic before proceeding

**Client changes:** None. Zero risk. Clients are unaware of v2.

**Why shadow mode matters:** If the backend wrote directly to v1 during validation, any scoring bug would land in the live paths that all clients read. There would also be no independent baseline to compare against — the backend's own writes would mask discrepancies. Writing to v2 keeps the validation truly independent.

**Test vectors to validate during shadow mode:**
- Standard tip scoring across all game result combinations
- Margin-based scoring (AFL narrow/wide margins, NRL margins)
- Games with no official scores yet (should not affect round stats)
- Games transitioning from live scores to official scores
- Stale `live_scores_v1` rows lingering after official scores exist (must be ignored and deleted)
- DAU round resolution with combined rounds
- Game stats for both paid and free cohorts
- Rounds with partial results (some games complete, some not)

### Phase A2: Promote to Production, Client Switch

**Goal:** Backend shadow results are validated. Backend starts writing to both v1 and v2. Updated clients switch to use the backend for fixture downloads.

Backend changes:
- Enable v1 writes in the fixture download function (dual-write v1+v2 for rescored stats)
- This ensures old clients on v1 get backend-authoritative scores for fixture-triggered rescoring, especially important since admin clients may no longer trigger local fixture downloads after upgrading

Client changes:
- Admin "Download" button calls `adminFixtureDownload` callable instead of `getNetworkFixtureData()`
- Remove client-side fixture download logic:
  - `FixtureDownloadService` — no longer needed on client
  - `FixtureImportApplier` — no longer needed on client
  - `FixtureUpdateService` and `FixtureUpdatePolicy` — no longer needed on client
  - `_processFetchedFixtures()` in `DAUCompsViewModel` — no longer needed
- Remove score-change detection and rescore triggering from `GamesViewModel.updateGameAttribute()` / `saveBatchOfGameAttributes()` — the backend handles fixture-triggered rescoring now
- `GamesViewModel` continues to listen to `/DAUCompsGames/` for game data — it still sees score updates (written by the backend), it just doesn't trigger rescoring anymore

**What the client still does:**
- Tip-triggered rescoring (via `ScoringUpdateQueue` — unchanged)
- Live-score-triggered rescoring (via `StatsViewModel.updateStats()` — unchanged)
- All read/listen logic for stats (unchanged, still reading v1)
- Admin "Re-score" button still calls `updateStats()` directly (unchanged — moves to backend in Workstream B)

**Old client coexistence:** Old clients may still trigger their own fixture downloads and write v1 stats alongside the backend. This is manageable because:
- The distributed lock prevents concurrent fixture downloads
- Rescoring is idempotent — same inputs produce same outputs
- However, an old client rescoring from stale cached game data could temporarily overwrite v1 with stale scores. The backend's next scheduled run will correct this. This narrow window is no worse than today's behaviour where client scoring is already racy.

### Phase A3: Remove Client Fixture Download (When Old Clients Gone)

Not time-bound. When analytics show no old clients:
- Remove any remaining fixture download code kept for backwards compatibility
- Stop dual-writing v1 from the fixture download function (v2 only)
- The scheduled download is now the sole source of fixture updates

### Workstream A: Estimated Effort

Workstream A is not just a fixture download — it includes a partial scoring migration to TypeScript. The effort estimate reflects the full scope: fixture download, import mapping, combined-round bootstrap, scoring logic, and shadow validation infrastructure.

| Task | Effort |
|------|--------|
| `scheduledFixtureDownload` (fetch, import mapping, lock, combined-round bootstrap) | 2-3 days |
| Scoring logic in TypeScript (game result calc with margin thresholds per league, scoring lookup tables, round stats aggregation, game stats with paid/free cohorts) | 2-3 days |
| DAU round resolution in TypeScript (date windows, combined rounds) | 1 day |
| Live score cleanup logic (delete stale crowd-sourced scores when both official scores exist) | 0.5 day |
| `adminFixtureDownload` callable + admin auth (RTDB lookup) | 1 day |
| Test vectors generated from Dart implementation + comprehensive TS tests | 1-2 days |
| Shadow comparison function (v1 vs v2 diff logging) | 0.5 day |
| Phase A1 shadow validation period | 1-2 rounds |
| Client: admin button → callable, remove fixture download + fixture-triggered rescore code | 1 day |
| **Total** | **~10-13 days + 1-2 rounds monitoring** |

### Workstream A: Key Files

**TypeScript to create (in `functions/src/`):**
- `services/fixture_download_service.ts` — HTTP fetch from NRL/AFL APIs
- `services/fixture_import_service.ts` — Map fetched data to game updates, combined-round bootstrap
- `services/scoring_service.ts` — Scoring logic (lookup tables, game result calc, round stats, game stats)
- `services/dau_round_service.ts` — DAU round resolution from date windows

**Client files to port from:**
- `lib/services/fixture_download_service.dart` — HTTP fetch logic
- `lib/services/fixture_import_applier.dart` — Import mapping, combined-round computation
- `lib/services/fixture_update_service.dart` — Distributed lock
- `lib/models/scoring.dart` — Scoring lookup tables, game result calculation
- `lib/view_models/stats_viewmodel.dart` — Round stats aggregation, game stats calculation

**Client files to modify in Phase A2:**
- `lib/pages/admin_daucomps_edit_buttons.dart` — Download button → callable
- `lib/view_models/daucomps_viewmodel.dart` — Remove `_processFetchedFixtures()`, `getNetworkFixtureData()`
- `lib/view_models/games_viewmodel.dart` — Remove score-change detection and `_roundsThatNeedScoringUpdate`

**Test vectors to generate from:**
- `test/game_scoring_test.dart`
- `test/scoring_roundscores_test.dart`
- `test/daucomps_viewmodel_test.dart` (combined rounds computation)

---

# Workstream B: Full Scoring Migration (Dart — Deferred)

**Blocker:** Official Dart support for Firebase Cloud Functions.

## Why Dart for Scoring

The scoring logic that remains on the client after Workstream A is:
- Tip-triggered rescoring (fires on every tip submission via `ScoringUpdateQueue`)
- Live-score-triggered rescoring (fires when a user submits a crowd-sourced live score)
- Admin rescore (full round rescore via the "Re-score" button)

This involves DAU round resolution, live-score precedence rules (latest per team, one-sided assumes zero, cleanup only when both official scores exist), game stats with paid/free cohorts, and round stats aggregation. This logic is complex and already correct in Dart. Porting to TypeScript would mean maintaining duplicate scoring logic in two languages — an ongoing maintenance burden for a solo developer.

**Pre-requisite: Extract a backend-compatible Dart package.** Several models currently have Flutter-only dependencies:
- `League` imports `dart:ui` (for `Color`)
- `DAUComp` depends on `watch_it` and ViewModel references

Before writing Dart Cloud Functions, these need refactoring to separate pure-Dart logic from Flutter UI concerns:
- Extract scoring, game result, round resolution logic into a pure-Dart package (no Flutter imports)
- Keep Flutter-specific concerns (colors, UI helpers) in the client only
- The shared package becomes the single source of truth; client and backend both depend on it

This is a meaningful prerequisite that adds ~2-3 days.

## Cloud Functions (Workstream B)

### 1. `onTipWritten` — Database Trigger

**Trigger:** `/AllTips/{compDBKey}/{tipperId}/{gameKey}` (onValueWritten)

**Behaviour:**
- Reads the game to determine its DAU round (via DAURound date windows, not fixture round number)
- Reads the game's current score (official or crowd-sourced)
- If game has a result, calculates the tip score using the scoring lookup table
- Recalculates that tipper's `RoundStats` for the affected round
- Writes updated stats to v2 (shadow mode) or both v1+v2 (after validation)
- Recalculates game stats (% tipped each result) for both paid and free cohorts

**Note:** The client currently does trigger rescoring on tip submission (via `ScoringUpdateQueue.queueScoringUpdate()` in `GameTipViewModel`). This function replaces that client-side behaviour.

### 2. `onLiveScoreWritten` — Database Trigger

**Trigger:** `/Stats/{compDBKey}/live_scores_v1/{gameDBKey}` (onValueWritten)

**Behaviour:**
- Reads the updated score data
- Applies live-score precedence rules exactly as today:
  - Uses latest crowd-sourced score per team
  - Prefers official scores when present
  - Treats one-sided live update as other team = 0
  - If BOTH official fixture scores already exist, treats the live-score row as stale: ignore it for scoring, delete it, and exit
  - Otherwise only deletes live scores once BOTH official fixture scores exist
- Determines the game's DAU round
- Reads ALL tips for that round across ALL tippers
- Recalculates every tipper's `RoundStats` for the round
- Batch-writes all updated stats
- Recalculates game stats for both paid and free cohorts

### 3. `scheduledRescore` — Scheduled Function

**Trigger:** Cron, e.g. every 15 minutes during game windows (similar pattern to existing `sendReminders`)

**Behaviour:**
- Safety net: rescores any rounds with games that have ended but whose stats look stale
- Idempotent — recalculating already-correct scores produces the same result
- Catches edge cases where a trigger might have failed or been throttled

### 4. `adminRescore` — HTTP Callable

**Trigger:** HTTP callable, auth-gated to admin users

**Behaviour:**
- Replaces the current admin "Re-score" button that calls `updateStats()` directly
- Accepts parameters: comp, round (optional — defaults to all rounds)
- Performs a full rescore for the specified scope
- Returns status to the caller

## Workstream B: Database Path Strategy

| Path | Shadow mode writer | Post-validation writer | Readers |
|------|-------------------|----------------------|---------|
| `/Stats/{comp}/round_stats_v1/{round}/{tipper}` | Clients only | Cloud Functions + old clients | Old clients |
| `/Stats/{comp}/game_stats_v1/{paid\|free}/{game}` | Clients only | Cloud Functions + old clients | Old clients |
| `/Stats/{comp}/round_stats_v2/{round}/{tipper}` | Cloud Functions | Cloud Functions (authoritative) | Updated clients |
| `/Stats/{comp}/game_stats_v2/{paid\|free}/{game}` | Cloud Functions | Cloud Functions (authoritative) | Updated clients |
| `/Stats/{comp}/live_scores_v1/{game}` | All clients | All clients (unchanged) | Cloud Functions + all clients |

**Note:** The RTDB root for stats is `/Stats` (capital S), as defined in `constants/paths.dart`.

**Shadow mode:** Backend writes v2 only. v1 remains exclusively client-written, providing a clean baseline for comparison. This avoids the backend's own writes masking discrepancies during validation.

**Post-validation:** Backend writes both v1 and v2. This is necessary because once updated clients stop writing v1, old clients would see stale data without backend v1 writes.

**Old client write contention:** Old clients may continue writing to v1 alongside the backend. This is mostly safe since calculations are idempotent. However, there is a narrow window where an old client could temporarily overwrite v1 with stale data (e.g. if it recalculates from cached game scores before the latest fixture download has propagated). The backend's next write will correct this. This is acceptable — it's no worse than today's behaviour where client scoring is already racy.

## Workstream B: Migration Plan

### Phase B1: Deploy, Validate (Shadow Mode)

**Goal:** Backend writes to v2 paths only. v1 remains exclusively client-written. Compare v2 against v1 to validate backend logic.

1. Deploy all trigger functions writing to **v2 paths only**
2. Add a comparison function (scheduled, e.g. after each round) that reads both v1 (client-written) and v2 (backend-written) and logs discrepancies in both round_stats and game_stats (including paid/free cohorts)
3. v1 remains a clean client-written baseline — the backend does not touch it, so any difference is a genuine logic discrepancy
4. Run for 1-2 rounds, monitoring for drift
5. Fix any discrepancies before proceeding

**Client changes:** None. Clients are unaware of v2.

**Test vectors to validate:**
- Standard tip scoring across all game result combinations
- Partial live scores (one team only, assumes other = 0)
- Live score → official score transition and cleanup
- DAU round resolution with admin overrides and combined rounds
- Game stats for both paid and free cohorts
- Concurrent tip submissions

### Phase B2: Update Client to Read from v2, Enable Dual-Write

**Goal:** Backend starts dual-writing to v1+v2. New client version stops calculating scores and reads from v2 instead.

Backend changes:
- Enable v1 writes in all Cloud Functions (dual-write v1+v2)

Client changes:
- `StatsViewModel` listeners switch from `round_stats_v1` → `round_stats_v2` and `game_stats_v1` → `game_stats_v2`
- Remove client-side scoring calculation and write logic:
  - Delete `ScoringUpdateQueue`
  - Remove `_calculateRoundStatsForTipper()` from `StatsViewModel`
  - Remove `updateStats()` write path from `StatsViewModel`
  - Remove game stats calculation and write logic (both paid and free cohorts)
- Replace admin "Re-score" button → calls `adminRescore` callable
- Keep scoring lookup table on client for instant inline tip-score display
- Keep all read/listen logic (just pointed at v2 paths)
- All UI code: No changes — it reads from StatsViewModel which now sources from v2

### Phase B3: Cleanup (When Old Client Usage Drops to Zero)

Not time-bound — when analytics show no more v1 client traffic.

1. Remove comparison/monitoring code
2. Stop backend writing to v1 paths
3. Lock v1 paths via security rules:
   ```json
   "round_stats_v1": { ".write": false },
   "game_stats_v1": { ".write": false }
   ```
4. Optionally remove v1 data to save storage

### Coexistence Diagram (Workstream B)

```
                    Phase B1             Phase B2                  Phase B3
                    (shadow/validate)    (gradual rollover)        (cleanup)

Old clients:        write v1, read v1    write v1, read v1        gone
Updated clients:    write v1, read v1    read v2 (no writes)      read v2
Backend:            write v2 only        write v1+v2               write v2 only
v1 paths:           client-written only  backend + old clients     locked / removed
v2 paths:           backend-written      backend-written           backend-written
Comparison:         v1 vs v2 logged      n/a                       n/a
```

## Workstream B: Estimated Effort

| Task | Effort |
|------|--------|
| Extract pure-Dart shared package (decouple from Flutter deps: dart:ui, watch_it) | 2-3 days |
| Set up Dart Cloud Functions infrastructure | 1 day |
| `onTipWritten` function + tests | 1 day |
| `onLiveScoreWritten` function (with full precedence logic) + tests | 1-2 days |
| `scheduledRescore` function | 0.5 day |
| `adminRescore` callable | 0.5 day |
| Phase B1 monitoring + comparison logging | 0.5 day |
| Phase B1 validation period | 1-2 rounds |
| Client: switch listeners to v2, remove scoring writes | 1-2 days |
| Admin rescore button → callable | 0.5 day |
| Phase B3 cleanup (when ready) | 0.5 day |
| **Total** | **~9-12 days + 1-2 rounds monitoring** |

---

# Cross-Cutting Concerns

## What Stays on the Client (End State)

| Operation | Details |
|-----------|---------|
| Tip submission | Client writes to `/AllTips/` (unchanged) |
| Live score submission | Client writes to `/Stats/{comp}/live_scores_v1/` (unchanged) |
| Listening to scores | `_listenToScores`, `_handleEventRoundScores` etc. (pointed at v2 paths) |
| Listening to games | `GamesViewModel` still listens to `/DAUCompsGames/` for game data, times, scores (unchanged) |
| Leaderboard/rankings | Derived client-side from stored round_stats — not persisted, not duplicated |
| Rank, rank change, round winners | Derived client-side from round_stats (unchanged) |
| Inline tip score display | Keep the scoring lookup table on the client for instant display (~20 lines, essentially never changes) |
| All UI rendering | Unchanged |

Reader rule: clients should continue to prefer official fixture scores and ignore any lingering `live_scores_v1` row once both official scores exist. The backend should make this state short-lived, but clients should still be defensive.

## What Moves to the Backend (End State)

| Operation | Before | After |
|-----------|--------|-------|
| Fixture download | Admin client calls external NRL/AFL APIs | `scheduledFixtureDownload` (automatic) + `adminFixtureDownload` (on-demand) — Workstream A |
| Fixture-triggered rescore | Client detects score changes, rescores locally | Fixture download function rescores once after batch write — Workstream A |
| Tip-triggered rescore | Client queues rescore via `ScoringUpdateQueue` on tip submission | `onTipWritten` trigger rescores on backend — Workstream B |
| Live-score-triggered rescore | Submitting client rescores all tippers locally | `onLiveScoreWritten` trigger rescores on backend — Workstream B |
| Admin rescore | Client calls `updateStats()` directly | `adminRescore` callable — Workstream B |

## Code Duplication

After Workstream A, there will be **substantial** scoring logic in both TypeScript (fixture-triggered rescoring) and Dart (tip/live-score rescoring on client). This includes game result calculation, scoring lookup tables, round stats aggregation, game stats with paid/free cohorts, and DAU round resolution. This is a real maintenance cost — if scoring rules change, both implementations need updating.

This is acceptable because:
- The scoring lookup tables and margin thresholds change rarely (if ever)
- DAU round resolution is data-driven from the same RTDB definitions
- Comprehensive test vectors validate both implementations against the same expected outputs
- The window of dual-maintenance is bounded — Workstream B replaces the client-side scoring with backend-only scoring

After Workstream B, the TypeScript scoring logic in the fixture download can optionally be replaced by calling the shared Dart scoring package (if the infrastructure supports it), or kept as-is since it's well-tested, stable, and validated against the same test vectors. Having two validated implementations is actually redundant safety, not a liability, once both are locked down.

## Security Rules (End State)

```json
"Stats": {
  "$comp": {
    "round_stats_v2": {
      ".read": "auth != null",
      ".write": false
    },
    "game_stats_v2": {
      "$cohort": {
        ".read": "auth != null",
        ".write": false
      }
    },
    "live_scores_v1": {
      ".read": "auth != null",
      ".write": "auth != null"
    }
  }
}
```

Cloud Functions use the Admin SDK, which bypasses security rules. v1 paths can be locked once old clients are gone.

## Concurrency & Idempotency

- All calculations are **idempotent** — recalculating the same round twice produces the same result
- Use Firebase transactions for all score writes
- `onValueWritten` (not `onCreate`) ensures functions run on creates AND updates
- `scheduledRescore` handles any missed triggers
- `maxInstances` cap prevents runaway scaling
- Distributed lock prevents concurrent fixture downloads

Recommended function settings:
- Region: `australia-southeast1` (closest to users)
- Memory: 256MiB
- Max instances: 10

## Cost Impact

At current scale (~80 tippers, ~16 games/round, 52 rounds/year):

- **Cloud Functions:** Well within 2M/month free tier invocations
- **RTDB:** Net change approximately zero or slightly negative (moving from N clients racing to write → 1 authoritative function)
- **Scales comfortably** to 500+ tippers within free tier
- **No `minInstances` needed** — accept occasional 3-5s cold start; scores update in background

## DAU Round Resolution

**Critical detail:** This codebase scores by DAU round date windows, including admin overrides and combined rounds — not by fixture round numbers. Both workstreams must resolve games to DAU rounds using the same date-window logic.

For Workstream A (TypeScript), this means porting the DAU round resolution logic. For Workstream B (Dart), the shared package includes this logic directly.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Dart Cloud Functions support delayed | Workstream A delivers value independently; Workstream B waits without blocking |
| TypeScript scoring logic drifts from Dart | Lookup tables are static data; comprehensive test vectors validate both; Workstream B eventually consolidates |
| Combined-round bootstrap missed in backend | Explicitly included in Workstream A design; test with new comp setup |
| Old clients linger for months | v1 and v2 coexist indefinitely; no pressure to force updates |
| Old clients temporarily overwrite v1 with stale data | Backend's next write corrects it; window is narrow and no worse than today |
| Shared package extraction harder than expected | Flutter deps are entangled; budget 2-3 days (Workstream B only) |
| Cloud Function cold starts | Accept 3-5s delay; scores update in background |
| Trigger storms (many tips at once) | `maxInstances` cap + idempotent calculations |
| Admin auth not enforced server-side | Implement RTDB lookup before deploying callables |

## Key Files (Current Client Implementation)

**Scoring logic:**
- `lib/models/scoring.dart` — Core scoring algorithms, lookup tables, game result calculation
- `lib/models/scoring_roundstats.dart` — RoundStats model
- `lib/models/scoring_gamestats.dart` — GameStatsEntry model
- `lib/models/crowdsourcedscore.dart` — Live score data structure

**Fixture download logic (Workstream A):**
- `lib/services/fixture_download_service.dart` — HTTP fetch from NRL/AFL APIs
- `lib/services/fixture_import_applier.dart` — Maps fetched data to game updates, combined-round computation
- `lib/services/fixture_update_service.dart` — Orchestrates download with distributed lock
- `lib/services/fixture_update_policy.dart` — Scheduling policy (daily timer logic)
- `lib/view_models/daucomps_viewmodel.dart` — `_processFetchedFixtures()`, `getNetworkFixtureData()`

**Client scoring logic (Workstream B):**
- `lib/view_models/stats_viewmodel.dart` — `_calculateRoundStatsForTipper()`, `updateStats()`, game stats writes
- `lib/view_models/games_viewmodel.dart` — Score-change detection and `_roundsThatNeedScoringUpdate` logic
- `lib/view_models/gametip_viewmodel.dart` — Tip submission queues rescore via `ScoringUpdateQueue`
- `lib/services/scoring_update_queue.dart` — Entire file (delete in Workstream B)

**Client listeners to retarget (Workstream B):**
- `lib/view_models/stats_viewmodel.dart` — `_listenToScores()` paths switch from v1 → v2

**Admin UI:**
- `lib/pages/admin_daucomps_edit_buttons.dart` — Download button → callable (Workstream A), Rescore button → callable (Workstream B)

**Existing tests to generate test vectors from:**
- `test/game_scoring_test.dart`
- `test/scoring_roundscores_test.dart`
- `test/scoring_race_condition_test.dart`
- `test/daucomps_viewmodel_test.dart` (combined rounds computation)
