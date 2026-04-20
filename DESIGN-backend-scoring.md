# Design: Dart-Only Backend Migration for Fixture Download and Scoring

## Status
- Production migration is deferred until Firebase supports the required deployable Dart trigger types.
- No partial TypeScript implementation will be built.
- Near-term work is limited to preparation and, optionally, a narrowly scoped experimental admin callable in Dart.

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
- full backend migration is not ready yet
- optional experimental callables may be possible
- scheduled and event-triggered production migration should wait

## End-State Architecture
When Firebase supports the required Dart triggers, the end state is:

- backend-owned fixture download
- backend-owned official-score-triggered rescoring
- backend-owned tip-triggered rescoring
- backend-owned live-score-triggered rescoring
- backend-owned admin rescore
- client becomes a read-only consumer of scores and stats

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
- preserve `/Stats/.../live_scores_v1/` as the client-owned live-score input path unless redesigning that path explicitly

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
