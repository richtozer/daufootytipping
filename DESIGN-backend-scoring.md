# Design: Dart-Only Backend Migration for Fixture Download and Scoring

## Status
- Production fixture download now uses a TypeScript scheduler wrapper that forwards to a Dart HTTP endpoint.
- The Dart-side scheduled entrypoint is production-safe HTTP, not Dart `onSchedule`.
- Full Dart trigger migration for scoring remains a future phase.

## Summary
The project will move fixture download and scoring to Firebase Cloud Functions only in Dart.

We will not build:
- a partial TypeScript fixture-download backend
- duplicated scoring logic across TypeScript and Dart
- a temporary mixed-language backend that must later be unwound

Instead, we will:
- extract the current scoring and round-resolution logic into a pure-Dart shared package
- preserve current production behaviour on the client for now
- migrate to backend execution once Firebase Dart Functions support is sufficient for the required deployed triggers

## Why This Direction
Current client-side scoring is fragile because:
- scoring depends on the app being open
- multiple clients can race to write scores
- fixture updates depend on admin-client activity
- queue state is local and ephemeral

However, a mixed TypeScript/Dart backend would create:
- duplicate business logic
- long-term drift risk
- unnecessary maintenance burden

A Dart-only backend keeps the long-term architecture simpler.

## Current Firebase Constraint
As of the current Firebase Dart Functions docs:
- Dart Functions support is public but experimental
- deployed support currently covers HTTP and callable functions
- the trigger types needed for the full migration are not yet ready for production use

Implication:
- the full Dart trigger migration is still not ready
- cron-driven fixture download can be implemented safely through an HTTP endpoint
- event-triggered production migration should still wait

## End-State Architecture
When Firebase supports the required Dart triggers, the end state is:

- backend-owned fixture download
- backend-owned official-score-triggered rescoring
- backend-owned tip-triggered rescoring
- backend-owned live-score-triggered rescoring
- backend-owned admin rescore
- client becomes a read-only consumer of scores and stats

### Architectural Simplifications
- **Removal of Grace Period Checks:** The league-specific grace period checks (mandating official scores after a certain duration to prevent stale writes) are not required on the backend. Because backend functions run with real-time server-side database access (no local offline cache lag) and act as the sole writer of aggregates, there is no risk of a client overwriting correct server stats with stale calculations. The backend can simply compute stats using the best available data on the server (official scores if present, falling back to live scores).
- **Removal of Client-Side Scoring Queue:** The client-side `ScoringUpdateQueue` (which queues and triggers rescoring tasks when tips or scores change) will be completely obsoleted. The client will simply write tips or live scores to their respective paths, and server-side cloud triggers (`onWrite`) will automatically initiate rescoring.
- **Obsoletion of Local Concurrency Locks:** Complex client-side concurrency guards (like `_isUpdateScoringRunning`, `_updateLock`, and single-flight flags) will be removed. The backend handles event execution, and concurrency conflicts on writes are resolved using standard database transactions.
- **Removal of UI Progress Tracking for Scoring:** Client-side progress tracking states (such as `_scoringProgressMessage`, `_scoringProgressValue`, and step-by-step reporting hooks) will be removed from the view models. The client will simply display read-only stats and leaderboards.
- **Simplification of Precedence and Merging Logic:** The client will no longer need to manage complex merging and precedence rules between live crowdsourced scores and official fixture scores (e.g., `_gamesWithLiveScores` cleanup, `_deleteStaleLiveScores`). The backend will write the computed stats, and the client will consume them directly.
- **Centralized Audit Logging:** Device-specific audit logging from the client (`_writeScoringAuditEvent` which logs app version, build number, and platform) will be replaced by server-side system logs or centralized database entries structured directly by the Cloud Function.

## Work Plan

### Phase 0: Preparation Now
Goal: remove technical blockers without changing production behaviour.

Deliverables:
- extract a pure-Dart shared package
- move these concerns into the shared package:
  - scoring lookup tables
  - game result calculation
  - round stats aggregation
  - game stats aggregation
  - DAU round resolution
  - live-score precedence rules
  - combined-round bootstrap logic
- remove Flutter-only dependencies from shared logic
- add characterization tests and golden test vectors from current behaviour
- document admin authorization approach for future callables

Non-goals:
- no production backend scoring
- no scheduled backend fixture automation
- no TypeScript scoring implementation

### Phase 1: Optional Experimental Dart Callable
Goal: validate Dart Functions tooling in a narrow, reversible way.

Optional only:
- add `adminFixtureDownload` as a Dart callable
- keep it admin-only
- use it only for manual backend-triggered fixture refresh
- keep scheduled fixture download on the client
- keep all scoring on the client

Guardrails:
- this is infrastructure validation, not the production architecture
- if Firebase experimental behaviour is unstable, remove it

### Phase 2: Full Dart Backend Migration
Start only when Firebase supports deployable Dart triggers needed for production.

Implement in Dart:
- `scheduledFixtureDownload`
- `onTipWritten`
- `onLiveScoreWritten`
- `scheduledRescore`
- `adminRescore`

Then:
- shadow-write to a new backend-owned scoring branch
- validate against current client behaviour
- switch updated clients to the new backend-owned scoring branch
- dual-write to legacy and new scoring branches during coexistence
- remove client scoring and client fixture download
- lock the legacy branch after old-client usage drops to zero

## Database Strategy
When full migration begins:
- keep existing legacy stats paths for old clients
- use a new backend-owned scoring branch as the authoritative validation target
- dual-write only after validation
- preserve `/Stats/.../live_scores_v3/` as the client-owned live-score input path unless redesigning that path explicitly

## Server-to-Client Status Broadcast (UI Progress Tracking)
To replace the legacy client-side local progress state and support admin actions (like manual fixture downloads or full rescores), the backend will write real-time status updates to a dedicated path in the database:

Path: `/Stats/<comp_id>/scoring_status/`
Fields:
- `status`: `'idle' | 'downloading_fixture' | 'calculating' | 'completed' | 'failed'`
- `inProgress`: boolean (convenience flag to toggle UI overlays or lock submit buttons)
- `startedAt`: ServerValue.timestamp
- `message`: optional progress details (e.g., "Downloading NRL Round 12...", "Averages recalculated...")
- `percentComplete`: float (0.0 to 1.0) for active runs
- `triggeredBy`: `tipperId` / `'system_timer'`
- `error`: optional error details if status is `'failed'`

### Benefits:
- **Global Visibility:** All active users (not just the admin/tipper who triggered the action) see a unified status. For example, if an admin triggers a fixture refresh, other users' leaderboards will display "Refreshing scores..." rather than showing stale numbers or silently changing layout.
- **Persistent State:** If the app is closed and reopened during an expensive calculation, the correct state displays immediately.

## Admin Authorization
Future admin callables should verify admin status server-side.

Recommended first implementation:
- RTDB lookup by `auth.uid`
- resolve caller’s tipper record
- require `tipperRole == admin`

Optional later improvement:
- sync role to Firebase Auth custom claims

## Risks
- Firebase Dart trigger support may take longer than expected
- extracting a pure-Dart package may expose more coupling than expected
- optional experimental callable support may be unstable
- delaying backend migration means current client-side fragility remains for now

## Mitigations
- keep current client flow stable while preparing shared logic
- build strong characterization coverage now
- avoid temporary mixed-language architecture
- only begin production migration once Dart trigger support is sufficient

## Recommendation
Approve a Dart-only deferred roadmap:
- prepare now
- optionally experiment with a narrow admin callable
- do the real migration only once Dart-trigger support is ready
