# Design: Backend Scoring with 1st Gen RTDB Wrappers and Dart HTTPS Workers

## Status
- Alternative migration option to `DESIGN-backend-scoring.md`.
- Production RTDB event triggers remain on 1st gen TypeScript functions.
- Scoring and fixture business logic moves to Dart HTTPS functions where possible.
- The TypeScript layer is intentionally thin and must not contain scoring rules.
- Current implementation covers `tipWritten`, `officialScoreWritten`, and
  `liveScoreWritten` RTDB wrappers, plus `adminRescore` for single-round and
  all-round backend shadow rebuilds.

## Summary
The project can move scoring toward backend execution before Firebase supports
production-ready Dart Realtime Database triggers by using a small wrapper
architecture:

- 1st gen TypeScript Realtime Database triggers observe RTDB writes.
- Each wrapper normalizes the event into a small command payload.
- The wrapper invokes a 2nd gen Dart HTTPS function.
- The Dart function reads the authoritative RTDB state, calculates scoring, and
  writes aggregate results.

This keeps the production trigger surface stable while avoiding a duplicate
TypeScript scoring implementation.

## Why This Direction
Current client-side scoring is fragile because:
- scoring depends on the app being open
- multiple clients can race to write scores
- fixture updates depend on admin-client activity
- queue state is local and ephemeral

The deferred Dart-only design avoids mixed-language infrastructure, but it also
keeps those client-side risks in place until Dart supports the required trigger
types.

This wrapper design is a pragmatic intermediate option:
- TypeScript owns only RTDB trigger plumbing.
- Dart owns scoring, fixture, and round-resolution behaviour.
- The wrapper can be deleted later when Dart RTDB triggers are production-ready.

## Current Firebase Constraint
As of the current Firebase Dart Functions docs:
- Dart Functions support is public but experimental
- deployed support currently covers HTTP and callable functions
- production RTDB triggers are available through the established TypeScript/Node
  1st gen API
- 2nd gen RTDB triggers exist for Node/TypeScript, but are still a less
  conservative choice while marked preview

Implication:
- use 1st gen TypeScript only for RTDB trigger attachment
- use Dart 2nd gen HTTPS functions for wrapper-invoked backend business logic
- use Dart callables only for admin/client initiated commands where the callable
  protocol is useful
- do not implement scoring logic in TypeScript

## End-State Architecture
The transitional backend architecture is:

- backend-owned fixture download via Dart HTTPS/callable function
- backend-owned official-score-triggered rescoring via TypeScript RTDB wrapper
  calling Dart
- backend-owned tip-triggered rescoring via TypeScript RTDB wrapper calling Dart
- backend-owned live-score-triggered rescoring via TypeScript RTDB wrapper
  calling Dart
- backend-owned admin rescore via Dart HTTPS/callable function
- client becomes a read-mostly consumer of backend-owned scores and stats after
  validation

Event flow:

1. A client writes a tip, live score, or official score to RTDB.
2. A 1st gen TypeScript `functions.database.ref(...).onWrite(...)` wrapper
   receives the event.
3. The wrapper sends a compact command to the Dart HTTPS worker, including:
   - affected RTDB path
   - comp key
   - round number, when known
   - game key or tipper key, when known
   - command type and intended recalculation scope
   - Firebase event id
   - event timestamp
4. The Dart worker re-reads the required state from RTDB.
5. The Dart worker calculates and writes aggregate scoring output.
6. The Dart worker writes audit/status records for observability.

### Command Scope
Wrappers should send the narrowest command that preserves current client
behaviour:

- `tipWritten`: recalculate only the affected
  `round_stats_backend_v1/<round>/<tipperId>` entry. Tip writes are still
  required because current round stats include missing-tip counts and margin-tip
  counts before games start.
- `officialScoreWritten`: recalculate the affected round for all relevant
  tippers, and rebuild affected game stats where needed.
- `liveScoreWritten`: recalculate the affected round for all relevant tippers
  using the current live-score precedence rules.
- `adminRescore`: recalculate the requested comp, round, or full scoring scope.
  Full-comp admin rescoring skips empty/unpopulated rounds and records them in
  backend scoring status rather than aborting the batch.
  All-tipper round rebuilds only include tippers with at least one submitted tip
  in the comp, matching the legacy client scoring cohort; missed started games
  still receive the legacy default-away tip for those active tippers.
  Game-stat rebuilds write games with known results, plus started/unscored games
  when a paid/free cohort has at least one submitted tip. Future games are not
  written just because users have pre-tipped. Paid/free cohorts are calculated
  from all tippers rather than only the active round-stat cohort.
  Full-comp admin rescoring replaces `game_stats_backend_v1` after rebuilding so
  stale shadow rows for future/unscored games are removed.

Tip-write commands must not trigger full-comp or full-round rescoring unless a
later rule explicitly requires it.

### Architectural Simplifications
- **No TypeScript Scoring Rules:** The TypeScript wrapper must not calculate
  winners, round points, ladders, live-score precedence, combined rounds, or
  fallback behaviour. It only maps RTDB events to Dart commands.
- **Removal of Client-Side Scoring Queue:** Once backend scoring is validated,
  the client-side `ScoringUpdateQueue` becomes obsolete. The client writes tips
  or live scores; backend triggers initiate rescoring.
- **Obsoletion of Local Concurrency Locks:** Client-side guards like
  `_isUpdateScoringRunning`, `_updateLock`, and single-flight flags can be
  removed after backend ownership is complete. Backend writes should use
  idempotent commands and transactions where needed.
- **Removal of UI Progress Tracking for Local Scoring:** Client-side progress
  fields such as `_scoringProgressMessage` and `_scoringProgressValue` can be
  replaced by server-written status records.
- **Centralized Audit Logging:** Device-specific audit logging from the client
  should move to backend audit records keyed by event id, command id, comp,
  round, trigger path, and worker result.

## Work Plan

### Phase 0: Preparation Foundation Mostly Implemented
Goal: remove technical blockers without changing production behaviour.

Status:
- substantially implemented in the current repo
- pure-Dart scoring models/calculators now live in `packages/dau_shared`
- current client scoring already consumes shared Dart scoring logic
- remaining work is to formalize backend command payloads, idempotency keys, and
  audit record shapes for the wrapper architecture

Deliverables:
- keep extracted pure-Dart scoring logic in the shared package
- keep these concerns in shared Dart logic:
  - scoring lookup tables
  - game result calculation
  - round stats aggregation
  - game stats aggregation
  - DAU round resolution
  - live-score precedence rules
  - combined-round bootstrap logic
- maintain characterization tests and golden test vectors from current client
  behaviour
- define backend command payloads and response contracts
- define idempotency keys and audit record shapes

Non-goals:
- no TypeScript scoring implementation
- no client behaviour change until shadow output is validated
- no hardcoded secrets in tracked config

### Phase 1: Dart Worker Behind Manual/Admin Entry Points Partly Implemented
Goal: validate Dart Functions tooling and shared scoring code.

Status:
- initial Dart Functions codebase is present in `functions_dart`
- admin fixture download through a Dart function path is already represented in
  the repo
- Dart admin rescore and backend validation branch writes are implemented for
  single-round and all-round shadow rebuilds
- comparison against current client-written v3 output is still needed before
  client cutover
- the currently implemented backend command surface is `tipWritten`,
  `officialScoreWritten`, `liveScoreWritten`, and `adminRescore`

Deliverables:
- keep or extend the existing Dart function surface for admin fixture download
- add a Dart admin rescore HTTPS/callable function
- keep admin-only authorization server-side
- write scoring output to a backend-owned validation branch
- compare backend output with the current client-written v3 branch

### Phase 2: Thin 1st Gen RTDB Trigger Wrappers
Goal: connect production-stable RTDB events to Dart workers.

Implement TypeScript wrappers for:
- official score writes
- tip writes
- live score writes

Wrapper responsibilities:
- extract path params
- ignore irrelevant/no-op writes
- create a stable command id from `context.eventId`
- include the narrowest safe recalculation scope
- call the Dart worker with a compact payload
- throw on retryable failures so Firebase retries the event
- log non-retryable validation failures with enough context to replay manually
- the current implementation covers `tipWritten`, `officialScoreWritten`, and
  `liveScoreWritten`

Wrapper non-responsibilities:
- no scoring calculations
- no aggregate writes
- no round winner logic
- no fixture parsing
- no fallback or precedence rules

Deferred optimizations to revisit after security and correctness hardening:
- sort `combinedRounds2` before materializing round objects when the source map
  is unordered
- reduce `/Teams` reads if the current scoring path does not need full team
  metadata
- narrow game reads to the target round or date range instead of loading every
  game for the comp
- reuse backend admin connections where the runtime model makes that safe

### Phase 3: Shadow Backend Scoring
Goal: prove backend output matches current client behaviour.

During this phase:
- clients continue writing and reading the current v3 scoring branch
- Dart workers write to a backend-owned shadow branch
- audit records compare v3 client output with backend output
- mismatches are logged with comp, round, game, tipper, and command id

Promotion criteria:
- clean analyzer and tests for Dart shared logic and functions
- deterministic replay tests for representative historical rounds
- no unexplained mismatches across a meaningful scoring window
- operational dashboard/log query can identify stuck or failed commands

Deployment readiness checklist:
- deploy both Cloud Functions codebases together when wrapper contracts change:
  `functions:default` for TypeScript RTDB wrappers and `functions:dart_functions`
  for Dart HTTPS/callable workers
- configure the TypeScript wrapper runtime with
  `BACKEND_SCORING_COMMAND_URL` pointing at the deployed Dart
  `backend-scoring-command` HTTPS URL
- configure both runtimes with the same `BACKEND_SCORING_COMMAND_SECRET`
  or `DART_BACKEND_SCORING_COMMAND_SECRET`
- keep those values in Firebase/Google runtime configuration or ignored local
  `.env` files; never commit actual secret values
- verify a deployed wrapper can call the Dart worker before switching clients
  to backend-owned scoring reads

### Phase 4: Backend-Owned Scoring
Goal: make backend scoring authoritative for updated clients.

Then:
- switch updated clients to read backend-owned scoring output
- stop updated clients from writing aggregate scoring
- keep old clients on the existing v3 branch during coexistence
- optionally dual-write backend results to v3 only if old clients require it
- lock down client aggregate writes after old-client usage drops to zero

## Database Strategy
Current clients write scoring to the v3 branch:
- `round_stats_v3`
- `game_stats_v3`
- `live_scores_v3`
- `scoring_audit_v3`

The migration should not mutate that contract until validation is complete.

Recommended backend-owned branches:
- `round_stats_backend_v1`
- `game_stats_backend_v1`
- `live_scores_backend_v1`
- `leaderboard_backend_v1`
- `round_winners_backend_v1`
- `scoring_audit_backend_v1`
- `scoring_idempotency_backend_v1`
- `scoring_status`

Rules:
- treat current v3 output as the legacy/client-owned production branch
- write backend results to shadow branches first
- version backend-owned branches independently; for example,
  `live_scores_backend_v1` can coexist with `game_stats_backend_v2`
- compare backend shadow output against v3 before client cutover
- when comparing round stats, remember that `round_stats_v3` is zero-indexed
  by list position while `round_stats_backend_v1` is keyed by the 1-based
  DAU round number; compare backend round `N` with v3 round `N - 1`
- use `npm run compare:backend-scoring -- --comp-key <compKey>` for read-only
  backend-v1 versus v3 round-stat comparisons after admin rescoring
- use `npm run compare:backend-scoring -- --comp-key <compKey> --type game-stats`
  for paid/free game-stat shadow comparisons
- preserve `live_scores_v3` as a client-owned input unless explicitly
  redesigning live scoring
- never let TypeScript wrappers write aggregate scoring branches

## Server-to-Client Status Broadcast
To replace legacy local progress state and support admin actions, the backend
will write real-time status updates to a dedicated path:

Path: `/Stats/<comp_id>/scoring_status/`

Fields:
- `status`: `'idle' | 'queued' | 'calculating' | 'completed' | 'failed'`
- `inProgress`: boolean
- `startedAt`: server timestamp
- `completedAt`: optional server timestamp
- `message`: optional progress details
- `triggeredBy`: `'rtdb_trigger' | 'admin' | 'system_timer'`
- `commandId`: stable command id
- `sourceEventId`: Firebase trigger event id, when available
- `sourcePath`: RTDB path that caused the command
- `error`: optional error details if status is `'failed'`

## Things to Be Careful About

### Idempotency and Retries
RTDB triggers are at-least-once. The Dart worker must tolerate repeated calls for
the same source event.

Requirements:
- pass the TypeScript `context.eventId` to Dart
- derive a stable `commandId`
- record command start/completion by id
- make aggregate writes deterministic
- skip or safely replay already-completed commands

Recommended idempotency path:
`/Stats/<comp_id>/scoring_idempotency_backend_v1/<commandId>`

Fields:
- `sourceEventId`
- `sourcePath`
- `commandType`
- `scopeKey`
- `status`: `'started' | 'completed' | 'failed'`
- `startedAt`
- `completedAt`
- `expiresAt`

Completed command records should be pruned after a short retention window, for
example 7 days, unless they are referenced by a failed audit investigation.

### Failure Semantics
The wrapper controls Firebase retry behaviour.

Guidance:
- throw from TypeScript when the Dart call fails with a retryable error
- do not throw forever for invalid payloads or unsupported paths
- classify Dart responses as `success`, `retryableFailure`, or
  `permanentFailure`
- log enough context to replay a failed command manually

### Concurrency Management
Multiple RTDB events can invoke multiple Dart workers at the same time. The
backend must preserve scoped writes and avoid stale aggregate overwrites.

Requirements:
- use per-command scope keys such as `<comp>:<round>:<tipper>` for tip updates
  and `<comp>:<round>:all_tippers` for score updates
- merge tipper-level round stats with RTDB transactions, matching the current
  client behaviour that preserves untouched tippers in `round_stats_v3`
- use transactions or compare-and-set writes for shared aggregate nodes such as
  game stats, leaderboards, and round winners
- coalesce duplicate in-flight commands with the same scope key
- avoid one global scoring lock unless a full admin rescore is running

Optional implementation choices:
- RTDB lock nodes with short TTLs for each comp/round/scope
- Cloud Tasks queues when command serialization is required
- 2nd gen worker concurrency limits for the Dart worker if shared writes remain
  hard to make safe

### Payload Size
The wrapper should not forward large snapshots.

Send only:
- path params
- before/after existence flags
- small changed primitive fields, when useful
- event id and timestamp

The Dart worker should read authoritative RTDB state itself.

### Security
The Dart HTTP worker must not be an open public scoring endpoint.

Preferred options:
- restrict invocation with IAM if the Firebase Dart deploy path supports it
- have the TypeScript wrapper call the Dart worker with a Google-signed OIDC ID
  token for the worker audience, then verify the token in Dart
- use a secret-bearing internal header or signed token only as a fallback when
  IAM/OIDC is not practical
- store secrets in Firebase/Google Secret Manager or ignored local config
- never commit secrets to tracked files

The Dart worker must also validate:
- source wrapper identity
- command shape
- comp and round paths
- admin authorization for manual endpoints

### Region and Latency
The TypeScript wrapper and Dart worker should be deployed in compatible regions.
The RTDB instance is regional; this repo currently points at the
`asia-southeast1` RTDB URL. Avoid cross-region wrapper-to-worker calls unless
there is a clear reason.

### Cold Starts and Cost
The wrapper adds an extra HTTPS hop and can introduce two cold starts.

Mitigations:
- keep wrapper code tiny
- batch/debounce rescoring by comp/round where practical
- have the Dart worker coalesce duplicate in-flight commands
- avoid triggering full comp rescoring for single-game or single-tip changes
- consider a minimum Dart worker instance only if production latency justifies
  the standing cost

### Event Loops
Backend aggregate writes must not retrigger the same wrappers indefinitely.

Rules:
- wrappers should only watch input paths
- backend output branches must be excluded from trigger patterns
- audit/status writes must not trigger scoring commands

### Ordering and Race Conditions
Different trigger events may arrive out of order.

Mitigations:
- Dart workers should re-read current state before calculating
- writes should be scoped to affected comp/round/game/tipper
- command records should include source timestamps for debugging, not as the
  sole source of truth
- use transactions or compare-and-set where concurrent backend writers can
  collide

### Observability and Replay
Backend scoring needs enough visibility to debug production mismatches.

Required audit fields:
- command id
- source event id
- source RTDB path
- worker version
- comp key
- round number
- affected game/tipper keys
- result status
- error class and message, if failed
- output branch version

Replay tooling should be able to re-run a command from audit data without
depending on the original client.

## Admin Authorization
Admin callables and HTTPS admin endpoints should verify admin status server-side.

Recommended first implementation:
- RTDB lookup by `auth.uid`
- resolve caller's tipper record
- require `tipperRole == admin`

For wrapper-to-worker calls:
- do not rely on end-user auth
- validate service identity or internal signature
- reject direct public calls that do not include the expected internal proof

Optional later improvement:
- sync role to Firebase Auth custom claims

## Risks
- the mixed TypeScript/Dart deployment surface is more complex than the deferred
  Dart-only design
- extra HTTP hop adds latency and another failure point
- retry behaviour can duplicate work unless idempotency is robust
- backend writes can accidentally trigger loops if paths are not isolated
- Firebase Dart Functions may change while experimental
- shadow output may expose hidden differences in current client-side behaviour

## Mitigations
- keep TypeScript wrappers small and heavily tested
- keep all scoring logic in shared Dart
- write backend output to shadow branches first
- use command ids and audit records from the start
- build replay tests from historical rounds
- keep current client v3 scoring stable until backend output is proven

## Recommendation
Approve this wrapper design only if earlier backend scoring is worth the added
operational complexity.

Recommended path:
- prepare shared Dart scoring logic now
- add Dart admin rescore/fixture worker first
- add TypeScript RTDB wrappers only after worker contracts and idempotency are
  tested
- shadow-write backend scoring beside the current v3 branch
- promote backend scoring only after mismatches are understood and resolved
