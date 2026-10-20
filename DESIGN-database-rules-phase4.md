# Database rules, phase 4: server pieces, coexistence and cutover to R2

Status: **revised plan, accepted by the owner on 2026-10-20 after an external review. M1 and M2 are
built and tested locally (section 6a); nothing is deployed and nothing else is implemented.** Written after R1 (rules 2026-10-06, Dart
functions and Firestore rules 2026-10-19) was verified in production. Basis:
[DESIGN-database-rules.md](DESIGN-database-rules.md) (D1 to D13),
[phase 1](DESIGN-database-rules-phase1.md) and [phase 3](DESIGN-database-rules-phase3.md).
A second review of the plan and the M1/M2 code (same day) raised three protocol points, now designed
(sections 3, 5 and 6b) and recorded as acceptance checks, plus one consistency fix (email
normalisation, done) and the owner's answers to section 12.

Revision 2 changes the first draft in response to six review findings: the new client could not run
under R1, the two-pass backfill did not stop drift, a rules-only rollback would not undo the data
migration, "dormant" callables were not access-controlled, role and login-identifier changes had no
endpoints, and the aggregator had no activation gate. The new material is sections 3 (coexistence),
5 (server mode), 8 (cutover) and 9 (rollback).

## 1. Goal and scope

Build, test and deploy everything R2 needs on the server, then the R2 rules, then the R2 client, so
that the final rules replace R1 in one controlled window before the 2027 season.

**Order matters.** Building and testing the R2 rules before the client exists is sensible. *Deploying*
them before the R2 floor is in force would break every released client. A new client cannot run under
R1 either (it needs reads R1 does not grant), so an intermediate ruleset ships first (section 3).

In scope: `DateUtcEpochMs`, `TipperPrivate`, the identity indexes and their callables, token
callables, admin identity callables (create, merge, reassign, delete, role, login identifiers), the
live-score aggregator, the intermediate and R2 rules, the R2 client, the floor and the cutover.
Out of scope: anything that changes scoring, fixtures or leaderboard behaviour.

**R1 is a safe place to rest.** If the schedule slips past the gate in section 7, we stay on R1 (with
R1-compat, section 3) until next off-season. The cost of staying: any signed-in user can edit another
tipper's `email` or `logon`, there is no kickoff lock, and signed-in users can read each other's tips
before kickoff.

## 2. What the research found

| Finding | Consequence |
|---|---|
| The production Dart database handle is a hand-written **REST client** (`_RestDatabaseReference`, `functions_dart/bin/server.dart` ~1266) whose compare-and-set uses `X-Firebase-ETag` and `if-match`. The phase 1 proofs ran on `firebase_dart`'s `StandaloneFirebaseDatabase`, which production does not use. | Re-run the identity proofs on the REST handle (design risk, section 8 of the main design). |
| **Probed 2026-10-20:** the emulator honours the same REST conditional writes (`null_etag` for an empty slot, **412** for a stale tag). | The REST handle is testable locally. |
| **Probed:** `if-match: *` overwrites an occupied slot, and the handle falls back to `'*'` when the ETag header is missing. | The handle must **fail closed** (throw) on a missing ETag. |
| Dart callables already work in production (App Check enforced); `request.auth.token` has the decoded claims (`email`, `email_verified`, `firebase.sign_in_provider`). | Same pattern for the new callables. |
| `firebase_functions` 0.8 has `firebase.database.onValueCreated`; nothing in the repo uses a Dart database trigger yet (today's are TypeScript). | First Dart trigger needs a canary; TypeScript is the fallback. |
| `firebase_admin` (Dart) has `Auth.getUser` and `getUserByEmail`; unproven with the Cloud Run service account. | M1 checks it. |
| Only two places write a game's `DateUtc`: `Game.toJson` and `FixtureImportApplier`. | One shared serializer; one backfill pass. |
| Backend readers of `/AllTippers` use the Admin SDK (bypass rules). TypeScript reminders read `name`; the app-badge function triggers on `/AllTippers/{id}` and reads `compsParticipatedIn`; Dart scoring reads `isAnonymous` (`server.dart` ~795) and builds a `Tipper` carrying `email`, `logon`, `authuid`, `tipperRole` it does not use. | Rules do not affect them; the **data shape** does. Readers must be adapted and deployed before any field is purged. A purge touches every record, so `tipperWrittenAppBadge` fires once per tipper and must be proven a no-op for unchanged `compsParticipatedIn`. |
| Client live-score writes today: `update` of `{game}/current` and `{game}/history/{micros}-{team}`; `history` entries are the client's `CrowdSourcedScore.toJson()` (ISO `submittedTimeUTC` from the **client clock**, no server time). The fixture import clears a game's whole `live_scores_backend_v1/{game}` node in the same update that writes the official score. | Aggregator ordering must handle legacy entries; official-score cleanup can race an in-flight aggregation (section 6, M5). |
| Alias normalisation is private to `tippers_viewmodel.dart:23`. The client finds its tipper by scanning the whole in-memory public list by uid, then `logon`, then `email`. | Move normalisation to `dau_shared`; the scan disappears in R2, which is what lets contact fields leave the public record. |
| Admin merge, delete and create are client multi-path writes today. | They must become callables, or the server-only indexes drift. |

## 3. Coexistence: what users actually run during the rollout

Each stage is a combination of rules, server mode (section 5), data shape and client version. Each
combination users meet is tested (section 10).

| Stage | Rules | Server mode | Data | Clients in the wild |
|---|---|---|---|---|
| S0 now | R1 | no callables | public records only | 1.4.0, 1.4.1 |
| S1 server pieces deployed | R1 | `off` | `TipperPrivate` and indexes backfilled, unused | 1.4.x |
| S2 compatibility rules | **R1-compat** | `pilot` | same | 1.4.x, owner's test builds |
| S3 store rollout | R1-compat | `coexist` | public (**legacy shape**) + private + indexes, kept consistent by callables | 1.4.x and R2 |
| S4 R2 floor raised | R1-compat | `coexist` | same | R2, plus running old sessions |
| S5 cutover step A | freeze, reconcile, then **R2** | `freeze` then `coexist` | same, public PII still present | R2 only |
| S6 verification window (about 7 days) | R2 | `coexist` | same | R2 |
| S7 cutover step B (purge) | R2 | `final` | public minimal, snapshot kept | R2 |

**R1-compat** is R1 plus exactly the reads the R2 client needs and nothing else: a signed-in tipper
may read `AuthIndex/{their own uid}` and `TipperPrivate/{id}` when `AuthIndex[auth.uid] == id` and the
record's `authuid == auth.uid` (the R2 owner rule), and allowlisted admins may read `TipperPrivate`.
No client write to either node, default deny elsewhere. It adds no write permission, so 1.4.x clients
behave exactly as under R1. It is deployed *before* the client release, which also exercises the
`root.child` lookups in production early.

**Callables dual-write while coexisting.** In `coexist`, `linkOrCreateTipper` and the other identity
callables write the **legacy public shape** (so a 1.4.x client scanning the public list still finds
and logs in the tipper) as well as `TipperPrivate` and the indexes. In `final` they write the minimal
public shape only. They are drift tolerant: a rename or contact change made directly by an old client
leaves an index entry the callable did not write, and a callable never releases a claim that does not
point at its own tipper.

**Live scores in the window, and the fallback.** R2 clients write `history` only, and until the R2
rules are live the aggregator runs in shadow, so nothing updates `current` for their submissions. That
is harmless while no game is on, and costly if the cutover then fails after users have installed the
client and we stay on R1-compat for the season. Decision (owner concurs with the review's framing):
1. **Make the failure case unlikely.** Two gates (section 7). **Gate A, before the R2 client is submitted
   to the stores:** every server-side prerequisite is done (R1-compat live, M3b deployed, rollback and
   freeze rehearsals green, aggregator replay green, audit clean). **Gate B, before the freeze:** stores
   available, no kickoff inside the window, audit re-run. The client is not released into a state where
   Gate B can fail for a reason we control.
2. **If Gate B fails anyway, the prepared fallback is aggregator mode `compat`:** it writes `current`
   while 1.4.x clients may still write it, using the version guard. Both derive the score from the same
   history, so they converge; legacy writes are overwritten at the next aggregation. It is enabled only
   by the owner, and only because the M5 mixed-writer replay shows no divergence (section 6b).
3. **If `compat` is not enabled, the accepted cost** is that crowd-sourced interim scores are missing
   for R2-client users. Official scoring, leaderboards and tips are unaffected, because they use the
   official fixture score.
"The cutover waits if a game starts" only protects the window, so it is not relied on as the fallback.

## 4. Proposals

**P1. Keep and extract the REST ETag handle** into `functions_dart/lib/`, fail closed on a missing
ETag, jittered retry on 412, atomic multi-path `PATCH` for the non-claim steps. Reviewer: yes.

**P2. Identity code outside `bin/server.dart`:** `lib/rtdb/`, `lib/identity/`, `lib/tokens/`,
`lib/live_scores/`; `server.dart` only registers functions. Reviewer: yes.

**P3. Read the caller's own `AuthIndex` entry first; call `linkOrCreateTipper` only to link or
repair.** With the reviewer's safeguards:
- a found entry is trusted only after reading `TipperPrivate/{id}` and confirming `authuid == uid`;
- "no entry" (a successful read returning null) is the only trigger for the callable;
- **permission-denied, network and timeout errors are not "missing"**: retry with backoff, then a
  retry screen; a locally cached tipper may keep the read-only UI usable but never triggers a link;
- anonymous browsing never attempts linking and has its own path.

**P4. Backfill, freeze and reconcile** (replaces the two-pass backfill). Pass 1 now (reviewed,
Auth-derived, dry run first, abort on any changed record). A **drift report** then runs on a schedule
from M4a so we see how much old clients change. At cutover a **short write-freeze** closes all identity
changes, a full **reconcile** covers every record (new, renamed, contact-changed, merged, deleted),
the audit must be clean, and only then do the R2 rules go live (section 8).

**P5. Dart aggregator with an activation gate** (section 6, M5).

**P6. Server-side mode flag on every mutating endpoint** (section 5). Deployment approval stays
manual, but "nothing calls it" is no longer relied on for safety.

**P7. R1-compat and freeze rulesets** generated from the same template, with the same allowlist
check, deploy script and tests as R1.

**P8. New admin callables:** `adminSetTipperRole` (promote or demote; refuses to remove the last
admin) and `adminUpdateTipperContact` (changes `logon` and `email`, keeps `LogonIndex` consistent,
rejects a login identifier already claimed by another record). Direct leaf writes by admins remain
only for fields that touch no index: `compsParticipatedIn` (paid toggle) and `photoURL`. This amends
D4's table: `tipperRole` and `logon` become server-only, not admin-writable leaves.

## 5. Server mode: access control for migration-era endpoints

Stored at `/ServerConfig/identity` = `{ mode, pilotUids }`. The node is not readable or writable by any
client under R1, R1-compat, freeze or R2 (closed by default); only the functions (Admin credentials)
read it. Every mutating callable reads it first.

| Mode | Mutating identity callables |
|---|---|
| `off` | refuse everyone (`failed-precondition`) |
| `pilot` | allow only uids in `pilotUids` (the owner's test accounts) |
| `coexist` | allow; write the legacy public shape and the private/index data |
| `freeze` | refuse with `unavailable` ("try again shortly"), reads still work |
| `final` | allow; write the minimal public shape |

Read-only callables are always allowed. Changing the mode is a deliberate, logged action (a database
write by the owner or the mode tool), never a deploy.

**What the flag guarantees, and what it does not.** Setting a mode stops *new* mutating requests from
being admitted at once. A request already admitted keeps running and can still write, bounded by the
callable's hard timeout (60 seconds for the mutating callables, set explicitly). So `off` and `freeze`
are not instant stops: a freeze that did not wait could let an old `coexist` request write after the
reconcile has read its data, or restore public contact fields after the purge. A **stop-and-drain**
protocol closes that:

1. **Admission wrapper** (every mutating callable). Create the operation id; write the in-flight
   marker `/ServerConfig/identity/inflight/{opId}` = `{callable, startedAtMs}`; only then read the
   mode; if the mode forbids the call, remove the marker and refuse; otherwise run, and remove the
   marker in `finally`. Because the marker is written *before* the mode is read, and a mode change is
   written *before* the markers are read, no admitted request can be missed (each side's second read
   sees the other's first write).
2. **Drain** (the mode tool, after writing a mode that forbids a shape or all mutation). Poll
   `inflight` until it is empty. A marker older than the hard timeout plus a margin belongs to a dead
   request (the platform has killed it); the tool reports it, removes it, and carries on. The tool
   exits only when drained, and prints the result.
3. **The stop-and-drain step precedes both reconcile and purge** (section 8). The audit job also
   reports any marker older than the timeout.
4. `off` as the emergency stop therefore means: no new mutations at once, running ones finish within
   the timeout, and the drain output says when it is quiet.

The aggregator has its own flag, `/ServerConfig/liveScores/mode` = `shadow` (compute and log) |
`active` (write `current`; for use when no client can) | `compat` (write `current` while legacy writers
exist; owner-enabled fallback, section 3).

## 6. Milestones

Estimates are working figures for focused effort, not commitments.

| # | Milestone | Exit criteria | Est. |
|---|---|---|---|
| M1 | **Foundation.** Extract the REST handle (fail-closed ETag). `claim`, `release`, `replaceIf`, lease primitives, `resolveCallerTipper` (bidirectional check). Port the 10-check CAS spike and the primitive parts of the 52-check identity spike to `dart test` on the REST handle against the emulator. Establish that the runtime service account can look up Firebase Auth users: first by reading its IAM roles (read-only metadata), and only if that is inconclusive a deployed probe that is **strictly read-only** (look up an existing account the owner names; no user is created), separately authorised. Establish whether the real callable code can run locally (Dart functions under the emulator suite, or `bin/server.dart` run directly against emulators). | Ported checks green on the REST handle; mutation check (loosened `replaceIf`) fails; Auth lookup result and local-callable answer recorded. | 3 to 4 d |
| M2 | **Shared code in `dau_shared`:** `normaliseAlias` (+ 64-char cap), `normaliseEmail`, `logonIndexKey` (base64url SHA-256), kickoff serializer, public/private `Tipper`, endpoint ids. | Unit tests; client and functions import it; no behaviour change shipped. | 2 d |
| M3 | **`DateUtcEpochMs`:** writers (`Game.toJson`, `FixtureImportApplier`), backfill, verifier. **Done (section 6c): functions deployed and patch applied and verified 20 October 2026.** | Verifier: 100% of games numeric and equal to `DateUtc`. | 3 d |
| M3b | **Backend readers adapted** to read identity fields from `TipperPrivate` (`isAnonymous` for scoring) and tolerate absent public PII; prove `tipperWrittenAppBadge` is a no-op for unchanged `compsParticipatedIn`; prove reminders and scoring against records with the PII fields removed. | Tests plus a dry run against a copy of production data in the emulator. Deployed **before** any purge. | 2 d |
| M4a | **Identity backfill** (pass 1) from the reviewed Auth mapping, written as a **Dart tool** (alias keys must come from the Dart function, section 6a); scheduled **drift report**. | Dry run reviewed by owner; audit clean; unlinked historical tippers listed separately (section 8). | 4 d |
| M4b | **Callables** `linkOrCreateTipper`, `updateTipperAlias`, `registerDeviceToken`, `unregisterDeviceToken`, all honouring section 5. | Protocol suite green on the REST handle; admission wrapper and drain tested (section 6b); deployed in mode `off`; deployed write-enabled integration check in `pilot` with a throwaway user and scratch data (separate owner go). | 9 d |
| M4c | **Admin callables** `adminCreateTipper`, merge, reassign, delete, `adminSetTipperRole`, `adminUpdateTipperContact`; leases and `IdentityOps` journal; scheduled audit and reaper. Existing admin endpoints move to `resolveCallerTipper` at cutover. | Crash injection after every step; one lease-takeover winner; **stale-holder scenario passes (section 6b)**; forged index or `authuid` rejected; last admin cannot be removed; audit reports every violation class. | 9 to 11 d |
| M5 | **Live-score aggregator**, shadow first. History ordering: numeric `t`, else parsed legacy `submittedTimeUTC`, else the push key's microseconds. The `current` write is a version-guarded transaction (`basedOnCount`) that is also skipped when the game already has an official score; the audit job sweeps any `current` left behind for a completed game (the import clears the game's whole live node, so an in-flight aggregation can recreate it). `gameComplete` never set. **Activation (`active`) only after R2 rules deploy**, when no client can write `current`. | **Synthetic game-day replay** on the emulator: mixed legacy and new entries, shuffled and duplicated deliveries, an official score arriving mid-stream, compared with golden vectors from the current client algorithm. **Mixed-writer replay** (a legacy client's `current` writes interleaved with the aggregator over the same history converge to one displayed score and do not flap). Shadow canary in the test comp. | 6 d |
| M6 | **Rulesets:** R1-compat, freeze, R2, all from templates; tests for each (R2 includes the bidirectional-check cases, multi-location updates, own-`AuthIndex` read); **rollback rehearsal** (section 9). | Every combination in section 10 passes; generated files match the build; rollback rehearsal green. | 8 d |
| M7 | **R2 client** (`1.4.n+1`), section 10 scope. | Tests; real-client smoke harness green against R1-compat and R2 using the real callable code; **reference-data checks (section 6b)**; soak on the owner's devices. | 12 to 15 d |
| M8 | **Cutover step A, verification window, step B, cleanup.** | Section 8 checklists green; allowlist and legacy paths removed; docs updated. | 4 d |

### 6a. Progress: M1 and M2 (2026-10-20, local only, not deployed)

**Built.** `functions_dart/lib/` now holds `errors.dart`, `rtdb/rest_database.dart` (the REST handle moved
out of `bin/server.dart`, which now imports it), `identity/claims.dart` (`claim`, `release`, `replaceIf`),
`identity/leases.dart` (`acquireLease`, `releaseLease`), `identity/caller.dart` (`resolveCallerTipper`, the
bidirectional check) and `identity/keys.dart` (`logonIndexKey`, `aliasIndexKey`). `packages/dau_shared`
gained identity path constants, `isValidRtdbKey`, `normaliseAlias` (moved from the client, behaviour
unchanged), `isValidAlias` (64 characters), `normaliseEmail`, `TipperPrivate` with the public/private
field partition, and the four callable endpoint ids. The client's private normaliser is gone.
`config/identity-vectors.json` holds cross-runtime test vectors.

**Verified.** 43 new tests for the primitives run on the production REST handle against the Database
emulator inside the isolation boundary (`npm run test:dart` in `rules_test` now runs them after the
spikes); the 91 existing function tests, 32 shared-package tests, 19 audit tests, the 149 unit checks in
`npm run test:unit` and the full Flutter suite (767 tests) pass; `flutter analyze` is clean. Mutation
checks prove the placeholder contract fails for a replacer that replaces anything, or anything that looks
like an email.

**Behaviour change to know about.** The REST handle used to write with `if-match: *` when the database
returned no ETag, which silently made the lock and idempotency transactions unconditional. It now throws.
The deployed scoring locks have worked through this path, so a missing ETag is not expected, but it is the
one change to existing production behaviour in M1 and is covered by a test.

**Findings that change the plan.**
1. **Dart is authoritative for alias keys.** Against Node, Dart's `toLowerCase` differs for U+0130 and for a
   capital sigma at the end of a word. The shared vectors recorded this; `scripts/audit_identity.mjs` was
   made to match Dart exactly and is tested against the vectors. Consequence: index keys are computed only
   in Dart, so the M4a backfill is a Dart tool, not a Node script. Node is still used for Auth export and
   review.
2. **Callables must use the REST handle in the emulator too.** `_openBackendScoringDatabase` switches to
   `firebase_dart`'s standalone client when `FIREBASE_DATABASE_EMULATOR_HOST` is set, so a locally run
   callable would not exercise production code. The new callables open `RestDatabase` in every
   environment (admin token against the emulator, service-account client in production).
3. **The real callable code can run locally.** `scripts/start_local_backend.sh` builds the native Dart
   executable and runs it under the Functions emulator, so the integration test required in section 10
   does not need a stub. Wiring it into the isolation runner is part of M4b.
4. **`LogonIndex` keys are unpadded base64url** (43 characters); D2 should read that way.
5. **Existing records store `acctCreatedUTC` and `acctLoggedOnUTC` with `DateTime.toString()`** (space
   separator), not ISO 8601. `DateTime.parse` reads both. The backfill copies the stored strings as they
   are, so the private copy equals the public one.
6. **Tipper records carry two legacy fields outside the public/private partition:** `tipperID` (134 of 214
   records, an opaque id or the literal `blah`) and `active` (84 records, a boolean). Neither is personal
   data and the current client does not write them. The purge and the restore move only the seven private
   fields and leave every other field alone, and the audit reports unknown fields as information, not as a
   violation. The partition test covers what the model writes today, not these legacy extras.

**Added after the second review.** `holdsLease` (a worker checks it before each step) and `newOperationId`
(unique lease owners and journal keys), both tested, including the taken-over worker at primitive level.
The Node audit now also lower-cases emails the way Dart does; email vectors for U+0130 and a final
capital sigma are in `config/identity-vectors.json` and asserted by Dart (shared package and
`functions_dart`) and Node.

**Still open in M1.** The service account's ability to look up Auth users is unconfirmed (see the M1
row); no production access has been used. Until it is confirmed the callable design assumes it works and
falls back to the Identity Toolkit REST lookup through the same authorised client.

### 6b. Acceptance checks that the second review added

These are requirements for the milestone named, to be met before cutover. They do not hold up M3 onwards.

**M4b, in-flight requests (stop and drain, section 5).**
- A slow mutating request admitted before a `freeze` completes; the drain waits for it; a request that
  starts after the mode change is refused; drain completes only after the slow one finishes.
- The marker-then-mode order is exercised with the mode changing between the two reads (no admitted
  request is invisible to the drain).
- A crashed request's marker is reported and removed after the timeout, and does not block the drain
  forever.
- After purge-preparation drains, an old `coexist` request cannot restore public contact fields: proved
  by a test that holds a coexist request open across the mode change and the purge.
- The purge tool is idempotent and re-runnable; the audit gains a "public contact data present after
  purge" violation class.

**M4c, a stale worker resuming.**
- Lease owners are operation ids, never admin uids (two requests from one admin cannot both hold it).
- The lease TTL (5 minutes) exceeds the mutating callables' hard timeout (60 seconds), so a taken-over
  worker is by construction already dead except for a platform pause.
- Before every step the worker checks `holdsLease`, and **every step's write is a compare-and-set on the
  exact value the step expects** (copy a tip only if the target is absent; delete the source only if it
  still equals what was copied; transfer an index entry with `replaceIf` or an owner-checked release). A
  stale worker waking between its check and its write therefore cannot overwrite its successor's work.
- Exact scenario test: worker A starts a merge and pauses past the TTL (a test hook between steps);
  worker B takes over from the journal and finishes; A resumes. Assert every remaining step of A is
  refused or a no-op, the final data equals B's outcome alone, and the audit is clean. Repeat for delete
  and reassign, and for A resuming after B has finished and released.

**M5, live scores.** The mixed-writer replay above, plus the official-score-mid-aggregation case under
both `active` and `compat`.

**M7, queued tips and the kickoff lock.** The client now stops waiting 15 seconds after a tip or admin edit is submitted and tells the user it is queued (build 713.2 onwards). Under R1 a queued tip sent after kickoff is still accepted. Under R2 the kickoff lock rejects it, and the user would hear nothing, because a rejection after the limit is only logged. Before R2: decide the wording of the queued-tip message so it does not promise delivery after kickoff, and surface a late rejection (for example, a notice on next launch). Add a test with a queued tip rejected by the rules.

**M7, reference data requires authentication.** `/Teams`, `/AllDAUComps` and `/DAUCompsGames` stay
auth-required, which holds only if anonymous browsing signs in anonymously before any of those listeners
attach (D10). Checks: cold start signed out; cold start signed in; sign-out then reconnect (listeners
torn down and re-attached, no permission-denied loop); anonymous browse then sign-in (listeners
re-subscribe); airplane-mode recovery.

### 6c. Progress: M3, the numeric kickoff (20 October 2026; built, deployed, backfilled and verified)

**Writers.** One shared parser and formatter (`packages/dau_shared/lib/services/kickoff_time.dart`) is
the only place a kickoff string becomes milliseconds. `FixtureImportApplier` adds `DateUtcEpochMs` to a
game's attributes whenever it has a `DateUtc`, so the Dart functions (scheduled and admin downloads)
write both in the same atomic multi-path update, and the client's own import path writes them in the same
batch. `Game.toJson` writes both, with the epoch derived from the same string, so the client's
change-detection stays quiet after the backfill. A `DateUtc` that cannot be read fails the import and
names the game; nothing is written without a usable kickoff. The parser reads the stored form
(`2026-03-01 02:15:00Z`), the `T` form and milliseconds, as `DateTime.parse` does, and refuses a time not
stated as UTC and dates that do not exist; `config/kickoff-vectors.json` pins Dart and Node to the same
answers.

**Backfill and verifier.** `scripts/backfill_kickoff_epoch.mjs` reads an export (or the live database)
and prints how many games are right, missing, wrong or unreadable, optionally writes a patch of
`DAUCompsGames/{comp}/{game}/DateUtcEpochMs` values, and with `--verify` exits 1 unless every game is
right. It has no way to write to the database (a test checks the code for that). It is the completeness
gate for the cutover pre-flight.

**State of the real data** (20 October export): 2,126 games in five comps, every `DateUtc` readable, none
with the epoch yet. The patch was `test/data/kickoff-epoch-patch.json` (git-ignored).

**Applied (20 October 2026, on the owner's go):**
1. The Dart functions were deployed from `development` at e478feb (`scripts/deploy-functions.sh --project
   dau-footy-tipping-f8a42 --only dart`). The CLI reported "timed out after 30000ms" for five of the six
   functions; Cloud Run showed all six on new revisions (created 18:21 to 18:22 UTC, Ready, 100% of
   traffic), so any fixture download from then on writes both fields.
2. The games were exported again and re-planned: 2,126 games, none correct, none wrong, none unreadable,
   and the patch paths identical to the reviewed patch. The patch was then applied with
   `firebase database:update / ... --disable-triggers --force`. No function ran afterwards.
3. A fresh export passes `--verify` (2,126 correct, none missing or wrong), and comparing it with the
   pre-patch export shows no game changed in any other field. The pre-patch export
   (`test/data/games-pre-patch-2026-10-20.json`, git-ignored) is the rollback point: undoing the backfill is
   removing the `DateUtcEpochMs` keys, which nothing reads yet.

**Still to do.** The client change rides the next client release. Until then an old client's admin
import (a fallback in `getNetworkFixtureData` that runs only when the Cloud Functions base URL is not
configured) would write `DateUtc` without the epoch, so the verifier is run again at the pre-flight and
the patch re-applied if needed. The R2 client should delete that fallback (M7), so the client has no
import path at all.

## 7. Timeline, back-planned from the season

**K, the earliest actual match, estimated from the extract (20 October 2026).** The season opens with the
NRL games in Las Vegas, which fall on a Sunday in Australia. The first kickoff in each comp was:

| Season | First kickoff (UTC) | Australian eastern | Where | First AFL game |
|---|---|---|---|---|
| 2024 | Sun 3 Mar 02:30 | Sun 3 Mar 13:30 | Allegiant Stadium | Thu 7 Mar |
| 2025 | Sun 2 Mar 00:00 | Sun 2 Mar 11:00 | Allegiant Stadium | Fri 7 Mar |
| 2026 | Sun 1 Mar 02:15 | Sun 1 Mar 13:15 | Allegiant Stadium | Thu 5 Mar |

Each year it is the first Sunday of March, which is also the Sunday of ISO week 9; both rules give
**Sunday 7 March 2027** for 2027. Treat that as the expected K, and **Sunday 28 February 2027** (the
Sunday before) as the cautious bound. The fixture feeds the app downloads are not published yet (the
2027 NRL and AFL feeds returned HTTP 404 on 20 October 2026), so this is an estimate to be replaced by the
published draw; re-check monthly and when the draw is announced. Under the expected K the purge keeps about
two weeks of margin; under the bound it keeps four to six days, which is still before the season but
leaves little slack, so the dates move earlier if the draw shows 28 February.

**When tipping opens.** The same extract shows tipping beginning later each year, and the bulk of tippers
starting only days before kickoff:

| Season | Comp record created | First tip | 10th tipper starts | 40th tipper starts |
|---|---|---|---|---|
| 2025 | 20 Jan | 20 Jan (40 days before K) | 31 Jan (29 days before) | 27 Feb (2 days before) |
| 2026 | 17 Feb | 17 Feb (11 days before K) | 24 Feb (4 days before) | 27 Feb (1 day before) |

The administrator decides when the comp is created, which is when tipping opens. Create the 2027 comp
**after** cutover step B if the schedule allows, so the freeze and the purge run with as little tipping and
registration going on as possible. The cutover is built to run with tipping open (tipping continues during
the freeze), so this is a preference, not a requirement. Every date below moves with K.

| When | What |
|---|---|
| 20 Oct to 14 Nov | M1, M2, M3. Owner works through the identity worklist (section 12). |
| 16 Nov to 12 Dec | M3b, M4a, M4b (deployed `off`, then `pilot`), M6 starts. |
| By mid-Dec | **R1-compat deployed** (S2). |
| 14 Dec to 9 Jan | M4c, M5 shadow, M6 finished. Holiday slack. |
| 4 to 22 Jan | M7 build, smoke tests, owner soak. |
| **About 22 Jan** | **Gate A** (release gate), then the R2 client is submitted. Mode `coexist` when it becomes available. |
| About 3 Feb | Available in both stores; floor announced out of band with web reload guidance. |
| **5 Feb** | **Gate B** (cutover gate). |
| About 10 Feb | Raise the floor. |
| 12 to 14 Feb | Cutover step A (freeze and drain, reconcile, R2 rules, aggregator `active`). |
| 14 to 21 Feb | Verification window (S6). |
| 22 to 24 Feb | Cutover step B (drain, purge). |
| Early March (K) | Round 1; about one week of margin after the purge. |

**Gate A, before the R2 client is submitted:** R1-compat live; M3b deployed and proven; rollback
rehearsal, freeze rehearsal and stop-and-drain tests green; aggregator replay (including mixed-writer)
green; identity audit clean; K confirmed. Not met: the client is not submitted.

**Gate B, 5 February:** R2 client available in both stores, Gate A items still true, no game kickoff
inside the window (section 3), audit re-run clean. Not met: no cutover before the season. Stay on
R1-compat; the owner decides whether to enable aggregator `compat`; use the next off-season. Server
pieces stay deployed.

## 8. Cutover

**Pre-flight (days before):** floor in force and adoption acceptable; drift report reviewed; audit run;
backup export of `/AllTippers`, `/TipperPrivate`, the indexes and `/AllTips`; Cloud Run revisions and
the git tag of the pre-cutover functions recorded; rollback scripts present and rehearsed.

**Step A: stop and drain, reconcile, R2 rules.** Target 30 minutes, **04:00 to 05:00 Australian Eastern
time (AEDT, UTC+11) on a weekday**, which is about 17:00 to 18:00 UTC the previous day and a quiet hour
for the tippers; the owner confirms they can attend. **Abort point:** 30 minutes after the start, or any
unexplained violation: redeploy R1-compat and set mode `coexist`. Reconcile only makes corrective,
idempotent writes to `TipperPrivate` and the indexes, so an abort leaves them in place.
1. Set mode `freeze` with the mode tool, then deploy the **freeze** ruleset (R1-compat with every
   identity-bearing write closed to all clients including admins: `name`, `email`, `logon`, `authuid`,
   `tipperRole`, `isAnonymous`, record creation and deletion, tip-node merges). Tipping, reading, paid
   toggles, photos, login timestamps and device tokens continue.
2. **Verify the stop.** A probe write of an identity field by the owner's test account is refused (the
   freeze rules are in force), and the mode tool **drains**: it waits until no mutating callable is in
   flight (section 5). Reconcile does not start before both are true.
3. **Reconcile every record** against Firebase Auth: public record versus `TipperPrivate`, `AuthIndex`,
   `AliasIndex`, `LogonIndex`; records created, renamed, contact-changed, merged or deleted since pass 1.
4. **Audit result, two classes.** *Violations* (must be zero): index entry without a matching record or
   with a mismatched `authuid`, record with a real uid and no entry, claim pointing at a missing record,
   stale intent, lease or in-flight marker. *Unlinked historical tippers* (expected, listed by opaque id,
   count recorded): records with a null, placeholder or no-longer-existing uid and no entry; they cannot
   sign in until `linkOrCreateTipper` claims them by verified login or email, as designed.
5. Deploy the **R2 rules** (deploy script, project explicit), set mode `coexist`, set the aggregator to
   `active`. The Dart functions without the allowlist go out in the same window.
6. Post-deploy verification: scoring event, fixture download, reminders dry run, tip write before and
   after kickoff, admin merge, role change, contact change, anonymous browse, token registration,
   sign-in on iOS, Android and web.

**Verification window (about 7 days).** Public PII is still present (as exposed as under R1 today; RTDB
cannot hide children of a readable parent, so this is no regression, only a delayed improvement). Watch
the audit job, function errors and support messages.

**Step B: drain, then purge.** Preconditions: M3b deployed and proven; window clean; fresh backup. Set
mode `freeze` and drain, so no request admitted under `coexist` is still running and none can restore a
public contact field afterwards. Take the snapshot, remove the public PII fields from every record,
set mode `final`, run the audit (which now fails on any public contact data) and the post-deploy
verification again. The purge is idempotent and is run once more after a short wait as a sweep. The
snapshot and the restore script stay for at least one season month.

## 9. Rollback

Rollback is coordinated across rules, data shape, backend version and client mode. **The target is
R1-compat, never plain R1**, while any R2 client exists, because the R2 client reads `AuthIndex` and
`TipperPrivate`.

| Failure | Action |
|---|---|
| R1-compat or earlier stage misbehaves | Redeploy R1 (S0/S1 only, before any R2 client exists), otherwise fix forward. Data untouched. |
| Step A (R2 rules) misbehaves, **before the purge** | Mode `freeze` and drain; deploy R1-compat; reconcile again (old-client direct writes may have returned); mode `coexist`; aggregator `shadow`. No data restore needed. |
| After the purge | Mode `freeze` and drain; **restore script** copies the purged fields back from `TipperPrivate` (R1's record validation requires `authuid` and `tipperRole`, so restore first); deploy R1-compat; redeploy the pre-cutover functions from the recorded git tag; mode `coexist`. |
| Callable defect | Mode `off` (no new mutations are admitted at once; running ones finish within 60 seconds and the drain says when quiet; no deploy), then fix forward. |
| Aggregator defect | `/ServerConfig/liveScores/mode` to `shadow`; under R2 clients cannot write `current`, so interim scores freeze until fixed (acceptable, scoring uses official results). Before the cutover, `compat` is the fallback (section 3). |
| Emergency | `BACKUP-database.rules.json` as in the main design, followed by the identity audit. |

The restore script is written and rehearsed in M6 against an emulator seeded in the post-purge shape,
then verified by running the R1-compat conformance suite and the real-client smoke harness.

## 10. R2 client scope and testing

**Client changes (M7):**
- Auth-aware startup (D10): protected view models start after sign-in and link; `onError` and
  re-subscribe on auth change; teardown on sign-out. Entry point: the post-frame warm-up in `main.dart`.
- Link flow per P3 replaces `_findExistingTipper`, `_createNewTipperIfNeeded`, `_updateExistingTipper`.
- Public/private `Tipper`; admin tipper screens read `TipperPrivate`; admin role and login-identifier
  edits call `adminSetTipperRole` and `adminUpdateTipperContact`; paid toggle stays a leaf write.
- Name changes through `updateTipperAlias`; per-game listeners for the drill-down; history-only live
  scores (remove the `current` writer and `gameComplete`); token callables replace
  `_removeTokenFromOtherTippers`; the Update App button works on web (D13).

**Test matrix (every combination users meet):** 1.4.x and R2 client against R1, R1-compat, freeze and
R2; mode transitions `off` → `pilot` → `coexist` → `freeze` → `coexist` → `final`; a 1.4.x client
against R2 must fail closed with the existing messages and no data change.

**Other tests:**
- **Identity protocol suite** (`functions_dart/test/identity/`, REST handle, emulator): exact-placeholder
  replacement, real uid never replaced, racing uids, crash injection after every step of link, create,
  rename and merge, partial states not takeable, abandoned-create reaping, lease takeover, same alias
  and email conflicts, merge into a target owned by another uid, last-admin protection, mode gating of
  every mutating callable, drift tolerance (index not matching a directly renamed record). Mutation
  checks included.
- **Callable handlers** as plain functions with mocktail doubles, as `server_test.dart` does.
- **Real-client smoke harness** (`rules_test/smoke/`) extended to the R2 client. **A contract-identical
  stub is acceptable for UI development but is never the final integration test:** the harness must
  call the real callable implementation, locally or in an isolated environment, before cutover (M1
  establishes how).
- **Synthetic game-day replay** (M5), **purge write-storm test** (badge function no-op), **rollback
  rehearsal** (M6), **write-freeze test** (identity writes denied, tipping allowed), and the acceptance
  checks in section 6b (drain, stale worker, mixed writers, reference data).
- **Deployed checks**, each separately authorised by the owner: the read-only Auth lookup (M1, existing
  account only, no writes), the write-enabled integration check with a throwaway user and scratch data in
  `pilot` (M4b), the aggregator canary (M5), then cutover verification.
- All suites run through the isolation runner; no new general isolation work is planned.

## 11. Risks

- **Login depends on a callable** only on first link or repair (P3). Mitigations: direct `AuthIndex`
  read, retry with backoff, `minInstances` for `linkOrCreateTipper` if cold starts show up.
- **Dart function deploys time out in the CLI while the revisions go live** (seen 2026-10-19): verify
  with Cloud Run revisions and probes after every deploy.
- **First Dart database trigger:** shadow canary, TypeScript fallback.
- **Mislinked backfill:** Auth-derived mapping, dry run, exact-placeholder rule, ambiguity rejected,
  audit job, freeze-and-reconcile at cutover.
- **Drift between pass 1 and cutover:** scheduled drift report; reconcile under freeze.
- **Store review delay:** 5 February gate; R1-compat is the resting state.
- **Mode flag misconfigured** (for example left on `off` after the client ships): the S3 entry check
  sets and verifies `coexist`; the post-deploy list includes a new-user link.
- **Requests already running when a mode changes:** admission wrapper and drain (section 5).
- **A worker resuming after a takeover:** operation-id leases, TTL above the request timeout, per-step
  lease check and compare-and-set writes (section 6b).
- **Client in the wild but cutover blocked:** Gates A and B, and the prepared `compat` fallback.
- **Holiday period** in the middle of the plan: heavy work lands before mid-December.

## 12. Decisions

The owner concurred on 2026-10-20 with the reviewer's recommendations on each point.

1. **Two-step cutover with about seven days of exposure before the purge: accepted.** The earlier
   suggestion to hide fields behind the R2 rules was withdrawn by its author: a readable parent cannot
   hide selected children. The exposure is bounded by a dated purge and a rehearsed restore.
2. **Season start date: estimated, and defined as K** (section 7): the earliest actual match in any
   competition the app supports, plus when registration and tipping open. From the last three seasons the
   opener is the Las Vegas NRL games on the first Sunday of March (Australian time), so **expected K is
   Sunday 7 March 2027, with Sunday 28 February as the cautious bound**; the 2027 feeds are not published
   yet. To be replaced by the published draw before Gate A.
3. **Freeze window: accepted as a 30-minute target with an abort point,** 04:00 to 05:00 AEDT on a
   weekday (section 8). Owner to confirm attendance once the date is set.
4. **Production probes: accepted in principle, each separately authorised when ready.** The M1 Auth
   lookup is strictly read-only against an existing account the owner names. A throwaway user and scratch
   data belong to the later write-enabled integration check (M4b). Nothing has been run in production for
   this phase.
5. **Manual identity fixes: prioritised, not exhaustive.** In order: administrators, the four active
   placeholder accounts, duplicates, ambiguous ownership. Historical placeholders may stay safely
   unlinked. A private worklist (opaque ids, outside the repository) shows exactly which decisions need
   the owner.
6. **Reference data stays auth-required: accepted,** provided anonymous browsing signs in anonymously
   before those listeners attach (D10); checked by the M7 acceptance items in section 6b.
7. **Live-score fallback: accepted as in section 3** (Gates A and B; prepared `compat` mode, owner-enabled;
   otherwise interim scores for R2-client users are the accepted cost).
