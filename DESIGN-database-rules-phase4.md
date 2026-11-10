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
   `inflight` until it is empty. **An old marker is not proof that its request has ended.** Cloud Run
   returns 504 at the timeout, but its documentation says closing the connection does not terminate the
   container instance and that it may keep working on the request. So the tool never removes a marker on
   age alone and never reports quiet while one remains. A marker older than the hard timeout plus a margin is
   reported as `STALE, investigate` (callable, operation id, age) and the drain exits non-zero. A handler
   that does finish removes its own marker, and every mutating handler logs a start line and an end line
   carrying its operation id, so the owner can confirm from the logs that the operation ended (or that its
   instance is gone) and then clear it with an explicit `--ack-stale <opId>`. Nothing is declared quiet on a
   guess. (A fence that stops a late worker committing needs a conditional write tied to the marker across
   several locations, which the database does not offer; the per-step compare-and-set of section 6b's stale
   worker case is the mitigation inside one operation.)
3. **The stop-and-drain step precedes both reconcile and purge** (section 8). The audit job also
   reports any marker older than the timeout, as a violation.
4. `off` as the emergency stop therefore means: no new mutations at once, running ones finish within
   the timeout or are reported as stale and investigated, and the drain output says when it is quiet.

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
| M3b | **Done: built, proven and deployed 20 October 2026 (section 6d).** **Backend readers adapted** to read identity fields from `TipperPrivate` (`isAnonymous` for scoring) and tolerate absent public PII; prove `tipperWrittenAppBadge` is a no-op for unchanged `compsParticipatedIn`; prove reminders and scoring against records with the PII fields removed. | Tests plus a dry run against a copy of production data in the emulator. Deployed **before** any purge. | 2 d |
| M4a | **Done 22 October 2026 (section 6e): tool built and corrected after review, real dry run reviewed and approved by the owner, backfill applied and verified; cutover findings remain for M4c.** **Identity backfill** (pass 1) from the reviewed Auth mapping, written as a **Dart tool** (alias keys must come from the Dart function, section 6a); scheduled **drift report**. | Dry run reviewed by owner; audit clean; unlinked historical tippers listed separately (section 8). | 4 d |
| M4b | **Callables** `linkOrCreateTipper`, `updateTipperAlias`, `registerDeviceToken`, `unregisterDeviceToken`, all honouring section 5. | Protocol suite green on the REST handle; admission wrapper and drain tested (section 6b); deployed in mode `off`; deployed write-enabled integration check in `pilot` with a throwaway user and scratch data (separate owner go). | 9 d |
| M4c | **Admin callables** `adminCreateTipper`, merge, reassign, delete, `adminSetTipperRole`, `adminUpdateTipperContact`; leases and `IdentityOps` journal; scheduled audit and reaper. Existing admin endpoints move to `resolveCallerTipper` at cutover. | Crash injection after every step; one lease-takeover winner; **stale-holder scenario passes (section 6b)**; forged index or `authuid` rejected; last admin cannot be removed; audit reports every violation class. | 9 to 11 d |
| M5 | **Live-score aggregator**, shadow first. History ordering: numeric `t`, else parsed legacy `submittedTimeUTC`, else the push key's microseconds. The `current` write is a version-guarded transaction (`basedOnCount`) that is also skipped when the game already has an official score; the audit job sweeps any `current` left behind for a completed game (the import clears the game's whole live node, so an in-flight aggregation can recreate it). `gameComplete` never set. **Activation (`active`) only after R2 rules deploy**, when no client can write `current`. | **Synthetic game-day replay** on the emulator: mixed legacy and new entries, shuffled and duplicated deliveries, an official score arriving mid-stream, compared with golden vectors from the current client algorithm. **Mixed-writer replay** (a legacy client's `current` writes interleaved with the aggregator over the same history converge to one displayed score and do not flap). Shadow canary in the test comp. | 6 d |
| M6 | **Rulesets:** R1-compat, freeze, R2, all from templates; tests for each (R2 includes the bidirectional-check cases, multi-location updates, own-`AuthIndex` read, and **live-score `history` entries create-only for clients**, no overwrite and no delete, because the aggregator's version guard assumes the history only grows; see 6i); **rollback rehearsal** (section 9). | Every combination in section 10 passes; generated files match the build; rollback rehearsal green. | 8 d |
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
   data and the current client does not write them. The restore moves only the seven private fields; the
   purge also deletes these two legacy fields (decision 9, section 6d). The audit reports any other unknown
   field as information, not as a violation. The partition test covers what the model writes today.

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
- A marker older than the hard timeout is reported as stale and **blocks** the drain (non-zero exit, listed by
  operation id). It is cleared only by an explicit acknowledgement after the logs show the operation ended. A
  handler that finishes late removes its own marker, and the drain then completes.
- After purge-preparation drains, an old `coexist` request cannot restore public contact fields: proved
  by a test that holds a coexist request open across the mode change and the purge.
- The purge tool is idempotent and re-runnable; the audit gains a "public contact data present after
  purge" violation class.

**M4b, ambiguity is rejected by scanning, not by a missing claim.** The backfill leaves a login email shared
by two records unclaimed, and an unclaimed email looks like one never seen. `linkOrCreateTipper` must therefore
search every record's `logon` and `email` for the caller's verified address and reject an ambiguous result
before it creates or claims anything. Integration tests on the REST handle: (a) two records with the same login
email: the call is rejected as ambiguous, no claim is created and nothing is written; (b) one record's login
equal to another's contact email: rejected as ambiguous; (c) a login that matches exactly one record by `email`
only is linked, with the claim written; (d) the same address in different case or with surrounding spaces
matches the same records; (e) a login email no record holds creates a new tipper only when `createLinkedTipper`
allows it.

**M7, the cached tipper after `busy`.** (a) A linked user whose background refresh returns `busy` keeps using the
cached tipper, and only when the cache was written for the current uid. (b) A first-time link or create that returns
`busy` or any other error is a failed sign-in. (c) Signing in as a different account never shows or uses the previous
account's cached profile, and clears it. (d) Every refusal other than `busy` (and `unavailable`) is shown as a
refusal. Widget or view-model tests cover each.

**M4c, a stale worker resuming.**
- Lease owners are operation ids, never admin uids (two requests from one admin cannot both hold it).
- The lease TTL (5 minutes) exceeds the mutating callables' hard timeout (60 seconds), so a taken-over
  worker is expected to be dead already, except for a platform pause. That is a reduction of risk, not a
  guarantee: a worker can still have a write in the network or resume after a pause, which is why the write
  fence and the hold exist, and the remainder is an accepted limitation (scope reset in 6f).
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

**Client import removed (20 October 2026).** The client used to have a local fallback in
`getNetworkFixtureData` that downloaded fixtures itself and wrote games under the admin allowlist when the
Cloud Functions base URL was not configured. It is deleted, along with the services only it used. With no
URL configured the call now throws a `StateError` that the admin screen shows. The client has no import
path, so the only writer of `DateUtc` is the Dart functions, which write the epoch with it. The released
client on `main` still has the fallback until the next release, so the verifier is run again at the
pre-flight and the patch re-applied if needed. `GamesViewModel.updateGameAttribute` and
`saveBatchOfGameAttributes` now have no caller outside their tests; M7 can delete them with the other
client game-write code.

### 6d. Progress: M3b, the backend readers (20 October 2026; built, proven and deployed)

**Dart (scoring, app-badge count).** `functions_dart/lib/identity/backend_tippers.dart` replaces two
near-identical loaders and two helpers in `server.dart`. It joins each public tipper record with
`/TipperPrivate/{id}`: a private field is used only when the public record does not carry it, so a
1.4.x client's newer public write wins until the purge, and after the purge the private record answers.
A missing private record is fine (today), a private record with no public record is never read, and an
unknown role or odd type is an ordinary tipper rather than a crash. `isAnonymous` is what scoring and
the badge count need: an anonymous tipper counts as paid for every comp, so losing the flag at the
purge would drop them silently. A test shows exactly that failure without the private record.

**TypeScript.** `tipperWrittenAppBadge` compared `isAnonymous` and `compsParticipatedIn` before and
after each write. A flag that has simply left the record (the purge) is now not a change, so the purge
is a no-op for every tipper; creation, deletion, a changed `compsParticipatedIn` and a flag that is still
there and now differs still sync. After the purge an anonymous-to-real change is no longer visible to
that trigger, and the hourly reconcile sweep picks it up inside the badge window. The not-tipped
reminders greet a tipper by the public `name` only; that lookup is now a tested helper
(`reminder_recipients.ts`), which also stops an empty `/AllTippers` from crashing the run.

**Proof.** 16 unit tests of the Dart readers over the legacy, coexisting and purged shapes; TypeScript
tests for the trigger and the reminder name; the five mock-based scoring tests in `server_test.dart`
now stub the empty private node. **Dry run:** a copy of the 20 October production export went through
the real REST handle into the emulator in the three shapes (`backend_tippers_export_test.dart`, skipped
unless `test/data/production-export.json` exists). All 214 tippers read identically in all three
shapes, except one, below.

**Findings that change the purge tool (M4a, M8), and the owner's decisions (21 October 2026).**
1. **One production tipper has none of the public fields** (no name, photo or paid comps: only contact
   fields, and six tips in the closed 2025 comp). Removing the private fields would leave an empty node,
   and the database keeps no empty node, so that tipper would vanish from `/AllTippers` and from every
   reader. A bug in 2025 let new tippers sign up without entering an alias. **Decision: the purge gives
   such a tipper a placeholder name** (`placeholderTipperName` in `dau_shared`: "Unnamed tipper" and the
   last six characters of their id; never claimed as an alias, so the M4a alias index skips it). The purge
   must leave every tipper a public node, and the audit checks it. The dry run models exactly this and
   sees only that name differ.
2. **Two legacy fields, `active` (84 records) and `tipperID` (134), are in neither list.** Nothing reads
   them. **Decision: the purge deletes both** (`tipperLegacyFieldNames` in `dau_shared`), and the restore
   script does not bring them back, because they are not part of the snapshot's private list.
3. **No anonymous tippers exist in production today**, so the `isAnonymous` path is protected by tests,
   not exercised by real data.

**Deployed (20 October 2026, 19:05 to 19:06 UTC, run by the owner):** `scripts/deploy-functions.sh --project
dau-footy-tipping-f8a42 --only all --yes` from `development` at 49091c9. All ten TypeScript functions
reported success. The Dart CLI again printed "timed out after 30000ms" for four of six functions; Cloud Run
showed all six on new revisions, Ready and at 100% of traffic, and no error-level logs followed. Behaviour
is unchanged while every record is still in the legacy shape; the readers matter at the purge.

### 6e. Progress: M4a, the identity backfill tool (21 October 2026; built, tested and corrected after a review; nothing applied)

**What it is.** An offline Dart tool, `functions_dart/bin/identity_backfill.dart` (logic in
`lib/identity/backfill_plan.dart` and `backfill_cli.dart`). It reads a database export, a slim list of Firebase
Auth accounts (uid, email, verified flag), the admin allowlist and the owner's reviewed decisions, and writes a
multi-path patch and a findings file. It never contacts Firebase. A patch is applied with the Firebase CLI, as
M3's was, by `scripts/apply-identity-backfill.sh`.

**One function does three jobs.** It computes the full set of entries the current records call for
(`TipperPrivate/{id}` as a copy of the seven private fields exactly as stored; `AuthIndex/{uid}`;
`AliasIndex/{key}`; `LogonIndex/{hash}`; `Placeholders/{id}` for records whose `authuid` is not an Auth
account), then compares that with the database. An empty place becomes a write; a place holding something
else is a finding and is never overwritten. So the first run is the backfill, `--check` after it is the
verifier, and `--check` later is the **drift report**: a changed alias, contact or account shows as a new
write or a differing entry, a deleted tipper's entries as stale ones. Alias keys come from the Dart
normaliser, as section 6a requires.

**Two different checks, on purpose.** `--check` says the backfill is in place and nothing blocks it; it stays
green with duplicates and ambiguities still present, because nothing is lost by leaving them for now. It
**does not mean the identities are ready for R2.** Every finding is labelled `BLOCKS` (settle before
applying), `cutover` (does not stop the backfill, must be resolved before the cutover) or `info`; the output
ends by saying which of the two checks passed, and **`--strict` is the cutover check**: it fails while any
`cutover` finding remains. The `cutover` findings are: two records on one real account, a shared alias, a
shared login email, a shared contact email, and one record's login being another's contact email.

**Policies, each reported and none guessed.**
- *Real account or placeholder* is decided only by the Auth accounts. An approved link (owner-reviewed, from a
  git-ignored decisions file) is the one case that writes to a public record: it sets `authuid` there and in
  the private copy so they agree. A link is **rejected, and blocks**, if the account does not exist, if the
  record already holds a different real account, or **if another record, or another approved link, already
  holds that account** (an approved link may never create a duplicate).
- *Two records on one real account that already exist:* neither is indexed; both are listed as a `cutover`
  finding, not hidden in a green result.
- *A shared alias:* one record claims it, so a new sign-up cannot take it, and the rest are listed. The ranking
  (a real account first, then most tips in the current comp, then most paid comps, then lowest id) is only a
  **proposal**. The owner approves the four proposed owners in the decisions file (`aliasOwners`); an approval
  overrides the ranking. A claim already in the database is **kept**, so tip counts changing later cannot flip
  an owner the owner has seen. Each shared alias in the output says whether its owner came from `[ranking]`,
  `[existing claim]` or `[approved]`.
- *A shared login email:* nobody claims it. **A missing claim does not by itself make a link attempt
  ambiguous.** An unclaimed email looks the same as one never seen, so the link callable must find every
  candidate by scanning the records' `logon` **and** `email` fields and reject an ambiguous match before it
  creates or claims anything (acceptance requirement in section 6b, M4b). This tool only reports the
  collisions, including a login that equals another record's contact email.
- *Anonymous records* are copied but never indexed. *A record with no name* gets no alias claim (the
  placeholder name from decision 8 is never claimed).
- *Administrators must match the allowlist both ways.* An admin role on an account that is not allowlisted, a
  placeholder or a shared account blocks the patch, as does an allowlisted account with no admin record. This
  is the privilege-expansion check: under the AuthIndex rules a database admin record becomes an administrator.

**Auth data and password hashes.** `firebase auth:export` always includes password hashes. The planner
**refuses any file that still carries them**; `scripts/slim_auth_export.mjs` reduces an export to uid, email and
verified flag (and can delete the full export at once), so the hashes never reach the planner. The slimmer
itself reads the full export once, so the full file exists for seconds in a private folder.

**The apply script and what it can and cannot guarantee.** It re-reads the live database **and a fresh Auth
export** (slimmed at once), plans again, and writes only if the result is byte-identical to the reviewed
patch, so an account created or deleted since the review stops it. It reads the five identity nodes and the
tipper list before planning and again just before the write, and any difference stops it. The write itself is
the Firebase CLI's unconditional multi-path update: there is no conditional write, so the window between the
second read and the write cannot be zero. That is acceptable here because no client or function can write the
identity nodes (the rules name none of them, so they are denied), which leaves one place a concurrent writer
could be overwritten: the `authuid` of a link the owner approved. Draining running operations is the M4b
server-mode freeze and does not apply before those callables exist. It names the project, suppresses
triggers, then re-checks and prints the verifier output.

**Proof.** 43 planner tests (every policy, the duplicate-link guard, alias ownership kept and approved, email
ambiguity, re-runs, renames, deletions, byte-identical output whatever the data order, only identity roots
touched); 19 command-line tests (no names in output, raw Auth exports with hashes refused, patch not written
while anything blocks, personal-data files must be git-ignored, `--check` against `--strict`); 10 tests of the
apply script (including a change during planning stopping the write); 3 of the slimmer; and the plan applied
to the Database emulator through the production REST handle and re-checked clean. **That last test proves
storage compatibility and repeatability, not identity correctness:** on the 214 real records the accounts and
administrators were guessed from uid shape, so it shows the database accepts every key and the verifier is
repeatable. Only a run on real Auth data shows which accounts and administrators are right.

**Preview on the real data** (20 October export, account status guessed from uid shape): 214 tippers and the
findings the owner's worklist predicted: one shared real account (items 4 to 6), four shared aliases
(items 4, 5, 9), three shared login emails, and one blocker, the LivToz admin record. LivToz is `tipper` in
production now, so a fresh export clears it.

**Real dry run (21 and 22 October 2026).** On a fresh Auth export (227 accounts, slimmed and the full export
deleted at once) and a fresh database export: 214 tippers, 165 real accounts, 49 placeholders; 830 writes
(214 `TipperPrivate`, 163 `AuthIndex`, 208 `AliasIndex`, 195 `LogonIndex`, 49 `Placeholders`, and the one
approved link's public `authuid`); **no blocking finding**, and the four administrator records match the four
allowlisted accounts. The owner approved the link (item 1) and the four proposed shared-alias owners; the
patch is unchanged by the approvals. Findings that remain, all blocking the cutover and not the backfill: one
shared real account, four shared aliases, three shared login emails, two shared contact emails, and three
cases of a login equal to another record's contact email (the worklist's Tier 3). The apply script's
check-only run against production on 22 October confirmed that the live database and a fresh Auth export still
produce exactly the reviewed patch. One read of the whole database stalled for ten
minutes during the first check-only attempt (a one-off: a repeat took eight seconds); the script has no read
timeout, which is worth adding before the cutover scripts.

**Applied (22 October 2026, run by the owner).** `scripts/apply-identity-backfill.sh --apply` re-checked, wrote the
830 entries with triggers off, and its verifier then found 0 writes left and 829 entries in place. Spot checks
of production: the linked record agrees in its public `authuid`, its `AuthIndex` entry and its private record,
and no function logged an error afterwards. The planner's `--strict` still fails, correctly, on the cutover
findings above, which the admin callables of M4c resolve (merge, reassign, delete). **Rollback** of the
backfill is a patch that restores every written path to what it held before (null for the new nodes, the old
placeholder for the one public `authuid`); it was built from the pre-apply export, proved offline to restore
that export exactly, and is kept with the reviewed patch in the git-ignored `test/data/`. Nothing reads the new
nodes yet, so leaving them in place is harmless. The slim Auth file was deleted.

**Scheduled drift report: deferred, not done.** What exists is the on-demand `--check`. A deployed schedule
belongs with the scheduled audit and reaper in M4c.

**Next, each a separate go.** (1) A fresh `firebase auth:export` (a read of production Auth), slimmed and
deleted at once, and a fresh `database:get /`; the real dry run for the owner to review, with the item-1 link and
the four proposed alias owners in a decisions file. (2) Apply with the script. (3) `--check`, and later
`--strict` before the cutover.

### 6f. M4b plan: the identity callables (22 October 2026; amended after a second review; B1 built, rest not)

**Amended after review.** Four changes, each now a requirement below: an expired in-flight marker blocks the drain
instead of being deleted (a timed-out Cloud Run request can keep running); rename and login-address changes are
journalled and serialised per tipper so a retry never guesses the old claim; token ownership is coordinated by a
compare-and-set index, not just an atomic write, and the replay limitation is stated; candidate discovery covers
public records so a record a 1.4.x client creates after the backfill is found, not duplicated.

**B1 built (22 October 2026, local, not deployed).** `lib/identity/server_mode.dart` (the five modes; anything
unreadable is `off`; `checkAdmission` with `not_available` and `unavailable` refusals), `admission.dart`
(`runAdmitted`: marker first, then the mode, always remove the marker, fail closed when either cannot be done,
start and end log lines with the operation id), `mode_control.dart` (a store over the REST handle for tests and
one over the Firebase CLI for the owner, `setIdentityMode` that merges and logs, and `drainInflight`),
`mode_cli.dart` and `bin/identity_mode.dart` (`status`, `set <mode> [--yes]`, `drain [--ack-stale id]`; `set`
shows what it would do unless `--yes`). `errors.dart` gained `FailedPreconditionError` and a structured `reason`
on every error type, and `dau_shared` the reason constants. **The drain never deletes a marker on age and never
reports quiet while one remains.** Proof: 11 mode and admission unit tests, 16 drain, store and mode-change
tests, 13 command-line tests, 15 emulator tests (the marker is visible before the mode is read; a freeze written
between the two is honoured; a slow request admitted before a freeze finishes, a request after it is refused and
the drain waits for the slow one; a marker that cannot be removed is left and keeps the drain from reporting
quiet until acknowledged; a marker or mode failure refuses the request). **Mutation checks:** a drain that
deletes overdue markers fails six tests, and an admission that reads the mode before writing the marker fails two.

**B1 corrected after a third review (22 October 2026).** (1) **A timed-out write can outlive its handler.**
The REST handle's timeout stops waiting for a request without cancelling it, so a write could reach the database
after the handler had exited and its marker been cleared, and a drain could have called the system quiet. The
handle now records every write it sends (`WriteLedger`) until the request itself finishes, and the admission
wrapper clears its marker only when the handler has ended **and its writes have settled**; otherwise it keeps the
marker, logs `writesSettled=false`, and clears it in the background only when they do finish (if the process ends
first, the marker stays and the drain reports it stale). An end line with `writesSettled=false` never justifies
clearing a marker. A marker write that times out and lands late is removed the same way. (2) **Corrupt in-flight
data is an error, not "nothing running":** a missing node means no markers, but a string, number or list raises
`MalformedInflightError` and stops the command. (3) **The tool must be told the project for anything that
changes data** (`set --yes`, `drain --ack-stale`); only `status`, a dry-run `set` and a drain without
acknowledgements default to production. Tests: the reviewer's scenario (a write times out, the handler exits, the
request completes later while the drain watches: not quiet until it settles, and the write does land), the
ledger, malformed data in the parser, the store and the command, and the project rule. Mutation checks: an
admission that clears the marker without waiting fails the late-write test; a parser that treats corrupt data as
empty fails three.

**B2 and B3 built (22 October 2026, local, not deployed).** B2: the request and result types in
`dau_shared/lib/models/identity_callables.dart` (strict `fromJson`, 63 shared tests). B3: `link_or_create.dart`
with `tipper_records.dart` (public and private halves joined; candidates are the union of login and contact
email, normalised), `claim_moves.dart` (the journalled, resumable move of an alias or login claim), `tipper_lease.dart`
(per-tipper lease, left to expire after a simulated crash), `tipper_shapes.dart`, `caller_token.dart`, `push_id.dart`
and `faults.dart` (a crash-injection seam, null in production). Behaviour as planned: anonymous and unverified
refused; an account already linked is validated and refreshed (stamp, photo, a changed login address by a claim
move); a record is linked only if its private `authuid` is empty, already the caller, or exactly its audited
placeholder; ambiguity and any unaudited or half-present match are refused before the first write; a create
claims an intent, the alias, the login, writes the records and commits last. **Proof:** 45 handler tests and 14
claim-move tests on the emulator, including a crash after every step of a link, a create and a move followed by a
retry, ten accounts racing for one record, a double tap, two accounts choosing one alias, the legacy-created record
after the backfill, and many rounds of two concurrent renames. **Mutation checks, all caught:** login-only matching,
ignoring unaudited records, replacing any stored `authuid`, no lease, and the stale-old-claim bug below.
**What the tests found, now fixed:** (1) a rename retried after a crash computed its old claim *before* finishing the
pending move and leaked the first target; the move now derives the old claim itself after finishing any pending
move. (2) A link that crashed after its commit left the placeholder audit entry and a create's intent behind; both
are tidied by the next link or refresh. (3) A double tap whose twin committed first was told "alias taken"; it now
recognises its own account as linked. **Two changes to the plan to note:** `CreateIntents/{uid}` holds
`{tipperId, createdAtMs, aliasKey, logonKey}` rather than a string, so a retry with a different alias or address
releases the first claims instead of leaking them; and `/ClaimMoves` is a new server-only node that M6's rulesets
must keep closed, like the other identity nodes. Next: B4 `updateTipperAlias`, B5 tokens, B6 registration.

**B4 and B5 built (6 November 2026, local, not deployed).** B4 `update_alias.dart`: the signed-in tipper renames
themselves, found from the verified uid only, under their lease, as a journalled claim move; the alias already held
changes nothing, a spelling change that keeps the key only rewrites the name, a taken alias is `alias_taken`, a
claim that is not this tipper's is never released and a stale one it cannot know about is left for the audit.
B5 `device_tokens.dart`: `register` makes the caller the owner of `/TokenOwners/{token}` by compare-and-set, clears
the token from every other tipper (including holders that wrote directly, which the index has never seen), writes
the caller's entry, then reads the owner again and removes its own entry if a later registration took the token;
`unregister` gives up the ownership only if it still names the caller and only touches the caller's own entry, so a
delayed unregister from a former owner cannot disturb the later owner. **Proof:** 23 alias and 28 token tests on the
emulator, including a crash after every step followed by a retry, two renames of one tipper at once and two tippers
choosing one alias (12 rounds each), two callers and five callers registering one absent token at once (15 and 10
rounds, one holder and a matching owner every time), a register racing an unregister, and the accepted
replay limitation written down as a test. **Mutation checks, all caught:** skipping the finish-pending step in the
alias and in the link handlers, no lease, no final ownership re-check (caught three runs out of three), an
unregister that releases the owner whoever it is, and a register that does not clear other holders.
**The tests found one more bug, now fixed, and it is the review's scenario at handler level:** after a crash with
the new name already written, a retry that asked for the same alias saw "nothing to change" and took the
shortcut, so the old claim and the journal were never cleaned up. The same shortcut existed on the login-address
path of link and refresh. **Every operation that holds a tipper's lease now finishes any pending move first**
(`finishPendingClaimMove`), whatever it was asked to do; a pending move whose target was claimed meanwhile is
dropped and the request carries on. **Notes for later:** push tokens that the reminders function prunes leave a
stale `/TokenOwners` entry, harmless but for the M4c reaper to clear; the index needs no backfill because register
always scans for other holders; and `/TokenOwners` joins `/ClaimMoves` as a node M6's rulesets must keep closed.
Next: B6 registers the four callables in `server.dart` (App Check enforced, 60-second timeout, the admission
wrapper around each mutating one, the manifest test), then B7, deploy in `off`, which needs the owner's go.

**Corrections after a fourth review (6 November 2026).** The review found a real token race and kept three earlier
items open; all four are fixed, each with a deterministic or mutation-checked test, and the paragraph above on
B4 and B5 should be read with this one. (1) **A paused older registration could delete the winner's entry.** A takes
the token and pauses; B registers completely; A resumes, sees B among the "other holders", deletes B's entry, then
sees it is not the owner and deletes its own: the token ends up held by nobody. My loops of simultaneous callers
never forced that order. The ownership record is now `{owner, seq}` and a token entry's value *is* its registration's
sequence (a UTC time to the microsecond, still a valid ISO time, so the 30-day stale-token cleanup is unaffected). A
registration removes only entries that are not newer than itself, writes its own entry only if no newer one is there,
and stands down if the sequence has moved on; entries written directly by a 1.4.x client carry no order and are always
replaceable. Unregister keeps the sequence as a tombstone, so an older registration finishing after an unregister
does not bring the token back. Tests force the interleaving through the checkpoint (A paused after each step while B
completes, three registrations released in reverse order, unregister in between, the same tipper twice); the old
behaviour fails them. (2) **The per-tipper lease was released while a timed-out write was still on its way**, so a
successor could start alongside it. It now waits for the worker's writes to settle, as the admission marker does,
and otherwise stays until they finish or it expires. (3) **A create wrote its two halves as two writes**, and a retry
after only the private one was refused as needing audit. They are now one atomic update; a lone half is completed
rather than refused; and an interrupted create is resumed from its own intent instead of being counted as a stranger.
(4) **A changed create intent replaced its old alias and login keys before they were released**, so a second crash
leaked those claims. The intent now names every key that may have been claimed, as a set that only grows until the old
claims are released, and abandoning a create releases everything it names. **Correction to the documentation:**
registering another tipper's token does not deliver their notifications to the attacker's device (the token still
identifies the original device); it changes which account that device is sent notifications for. **Still open, stated
plainly:** B6 and the deployment readiness review; the handler deadline described below (a request Cloud Run has timed
out keeps running its Dart code, so each handler must stop itself at the next step boundary); and the points in
"Risks".

**B6, registration (6 November 2026).** `registerIdentityCallables` (`lib/identity/callables.dart`) registers the
four callables with `identityCallableOptions` (region `asia-southeast1`, 60-second timeout, App Check enforced) and
`server.dart` calls it. Every request goes through one path: no verified sign-in is refused as `UNAUTHENTICATED`; the
body is read strictly *before* the database is opened (a malformed one never touches it); each request gets a
database handle of its own, so the writes the admission wrapper waits for are that request's; the handler runs inside
`runAdmitted`; and a `HandlerDeadline` (50 seconds, ten before Cloud Run gives up) is the handler's checkpoint, so a
request stops at its next step instead of running on after the client has its 504. A stop at the deadline releases
the lease and the marker and leaves any journalled claim move for the next call to finish, as a crash does.
`functions.yaml` is regenerated and the manifest test names the four ids and the 60-second timeout.

*Tested through the real callable pipeline, not around it* (`test/identity/callables_test.dart`, 70 tests). The
registered callables are driven by firebase_functions' own test client with a real ID-token verifier (a test key
pair, adapted from the package's fixture, with its licence header) and the real App Check verifier (its key set
answered from the same test key by `http.runWithClient`, everything else passing through). Proved: without an App
Check token, with a garbage, wrongly signed or expired one, with a tampered, expired or wrong-project ID token, and
with no ID token, each of the four callables is refused with 401 and the database is never opened; a valid pair
reaches the handler; mode `off`, `pilot` for a caller outside the list, and `freeze` are refused with
`not_available`, `not_available` and `unavailable` and leave the database exactly as it was (the marker is cleared);
a pilot caller is let through; a malformed request is refused before the database is opened; the tipper acted on
is the caller's even when the request names another; a handler past its deadline stops, and the same request
succeeds afterwards. **Six mutants** (App Check enforcement removed, admission wrapper bypassed, deadline checkpoint
removed, one database handle shared across requests, unauthenticated caller not refused, provider claim not read)
each fail the suite: 16, 12, 1, 1, 4 and 1 tests.

*Two things the pipeline tests found.* (1) The manifest does not record `enforceAppCheck`, so a manifest test cannot
show it is on; only a runtime test can, and now does. (2) The runtime copies only custom claims and a fixed set of
standard ones into `request.auth.token`; **the `firebase` claim, which says how the user signed in, is not among
them**, so `CallerToken.isAnonymous` could never have been true in production. Harmless so far (an anonymous account
has no verified email and was refused anyway, with `unverified_email` instead of `not_linked`), but the check was
dead. The provider is now read from the raw token's payload, which the runtime has already verified.

*Deployment readiness review.* The compiled `bin/server` was also run against the Database emulator (not just
`registerIdentityCallables` in-process) and called over HTTP with unsigned tokens: refused in `off`, 401 without
App Check or without an ID token, create, refresh, rename, register and unregister all correct, no marker or lease
left behind, and the existing admin callables still registered. What that does **not** cover is the production
branch of `_openIdentityDatabase` (`runtimeAdminApp.client` against the live database), which is the same client
the backend-scoring code already uses in production, and is what B7's first call exercises. Points to know before
the go: (a) the admission wrapper writes its marker *before* it reads the mode, so a deploy in `off` is not
write-free: each call from a signed-in, App Check-passing caller writes and then clears a marker under
`/ServerConfig/identity/inflight`; these endpoints are reachable by any such caller as soon as they are deployed, so
this is not "nothing calls them": the assurance is that `off` refuses every business mutation, while a temporary
admission marker remains possible; (b) the
runtime skips token verification whenever `FIREBASE_DEBUG_FEATURES` contains `skipTokenVerification`, with no
emulator check; nothing in the repository or its `.env` files sets it, and it is now an executable check
(see the fifth-review paragraph below), not just a warning; (c) `deploy-functions.sh --only dart` redeploys all six existing Dart functions with the new binary as well
as adding the four (their tests pass, and it is the off-season); (d) the new nodes (`/TokenOwners`, `/ClaimMoves`,
`/CreateIntents`, `/IdentityLocks`, `/ServerConfig`, `/Placeholders`) are named in no R1 rule, so clients cannot read
or write them, and M6's rulesets must keep it so.

**Corrections after a fifth review (6 November 2026).** The review accepted B6 for a controlled deploy in `off` and
kept the pilot a separate decision. Two limitations were left, both about writes whose outcome is not known, and
two statements needed correcting. All are addressed; what cannot be closed is stated as a limit.

*Finished is not known.* The write ledger counted a write as settled when its request finished, whatever way it
finished, so a lost connection (the write may have been applied; only the response was lost) or a 5xx cleared the
lease and the in-flight marker as if the outcome were known. The ledger now tells them apart: a response below 500
is a known outcome (2xx applied; 4xx, including the 412 of a lost compare-and-set, not applied), and a transport
error or a 5xx is counted in `uncertainCount`. `settled` still means "nothing in flight" and says nothing about
outcomes. **The marker** is cleared only when the writes have settled *and* every one has a known outcome; otherwise
it stays, the end line says `uncertainWrites=N`, and a "marker kept ... without a confirmed outcome" line follows.
It is resolved the way every stale marker is, with `identity_mode drain --ack-stale` after the owner has checked
the tipper (the tool's help says so now); the M4c reaper is to do that automatically. **The lease** is released only
in the same circumstances; a finished write with an unknown outcome leaves the lease to run out.

*The lease's promise was stated too strongly.* The comment said the lease outlasts any worker, and the 50-second
deadline is cooperative: it cannot stop a write already sent, or a process that is frozen and resumes later. What the
code does now, in three layers. (1) **A write fence**: while the body of a lease runs, every write is refused *before
it is sent* once the lease is within 30 seconds of expiring (the margin covers a last write timing out, the settle
wait and the hold being written), so a worker that was paused past its lease and resumes cannot carry on. The fence
sits in the write ledger of the request's database handle (one handle per request, so two operations never fence
each other); it is lifted for the release afterwards. (2) **A hold**: a worker that ends with writes still on their
way extends its lease to 15 minutes and releases it when the writes finish with known outcomes; until then a
successor is refused as busy even after the lease's own five minutes. The 15 minutes is an operational holding
period, chosen to be far longer than a healthy request takes and about as long as a stuck connection can linger; it
is not a guarantee that nothing arrives later. Only writes still *pending* get it: a write that has finished with an
unknown outcome leaves just the lease's own remaining time, and once either has run out another operation can
proceed despite unresolved state. The retained admission marker blocks a drain, not ordinary requests.
(3) The deadline, as before. The requested scenario is tested: a write is held in the network past the lease's own
expiry, a second operation tries to take the tipper over and is refused, the write lands, the lease is released, the
successor proceeds and is not overwritten. A paused worker is tested resuming after its successor has finished: its
write is refused and the successor's value stands. **Why not cancel a timed-out request instead?** The production
client (`googleapis_auth`) copies every request into a plain one before sending it, which drops any abort signal, so
cancellation is not available and the design does not depend on it. **What remains, stated plainly:** the Realtime
Database has no write that is conditional on another location, so there is no true fencing token. A write sent
*before* the lease expired and delivered long after is stopped only by the hold, which exists only if its worker
lived to extend it. The residual is a worker that dies or freezes between the fence check and the send, with the
request then held in the network for longer than the lease; the periodic audit (M4c) can detect what gets
through, but detection is not prevention or recovery, and this residual is an **accepted limitation** (see the scope reset below),
not a release requirement. A consequence for the client (M7): a tipper whose operation left writes unresolved is refused as `busy`
for up to 15 minutes, and sign-in's refresh takes the lease, so the client's handling of `busy` at sign-in is
specified narrowly in the M7 items below.

*Statements corrected.* "Nothing calls these yet, so none will" was not a guarantee: the endpoints are public once
deployed. The assurance is that `off` refuses every business mutation, while a temporary admission marker remains
possible. And the `FIREBASE_DEBUG_FEATURES` warning is now executable: the server refuses to start if the variable
is set outside the Functions emulator (the emulator is `FUNCTIONS_EMULATOR=true` without Cloud Run's `K_CONFIGURATION`;
any value is refused, not just the one switch; **corrected 9 November 2026, caught by the M5 end-to-end run: the first
version keyed on `K_SERVICE` being absent, but the Firebase emulator sets `K_SERVICE` too (to the function's name), so
the worker would not have started in the local emulator. Deployed Cloud Run was unaffected. It now keys on
`K_CONFIGURATION`, which only Cloud Run sets, and a test pins the environment as the CLI really provides it**), `deploy-functions.sh` refuses to deploy while the shell or any
`functions*/.env*` file sets it (printing the file name, never its contents), and both are tested, the first also
in the compiled server.

*Tests and mutants.* Ledger classification and the fence (9 new), lease hold, keep, fence and timings (10 new), admission
(2 new), startup guard (6) and deploy script (7 new cases). Twelve mutants of these changes: eleven were caught at
once; one survived (the background release of a lease ignored unknown outcomes), a test for it was added, and it is
caught. All suites pass.

*B7, the sequence to follow* (each step needs its own go from the owner): (1) deploy in `off`, after `--dry-run`
passes (it now includes the bypass check), recording that the six existing Dart functions are redeployed with it;
(2) verify the deployed environment has no `FIREBASE_DEBUG_FEATURES` and the mode is `off`; (3) exercise the
deployed denial paths: no App Check and an invalid ID token fail before any database access, and a valid signed-in
request is refused by `off` with no marker left behind, which also exercises the production database opener; (4)
check the existing endpoints still work after their redeploy (the local registration test does not show it); (5)
only then agree the isolated pilot: the exact throwaway account, the exact scratch data, and the cleanup, written
down before it runs.

**Qualifications after a sixth review (6 November 2026).** The review judged the fifth round sufficient for B7's
deploy in `off` and the denial checks, with the throwaway pilot approved separately. It asked that three limits stay
explicit; no code changed, and the wording above was corrected where it overclaimed.

1. *The lease protection reduces risk; it does not remove it.* See the corrected wording above: the hold covers only
   still-pending writes, finished-but-unknown writes leave the lease's own remaining time, and once either runs out
   another operation can proceed over unresolved state. The 15 minutes is an operational holding period, and the
   retained marker blocks a drain, not ordinary requests. The throwaway pilot is validation of the wiring; it is not
   evidence that this concurrency risk has gone.
2. *The audit detects; it cannot guarantee prevention or recovery.* The review proposed a flag, a block and a
   scheduled reconcile as the gate before broader use, and then corrected its own proposal: a database that is
   consistent now does not prove a delayed write cannot arrive later, so nothing may be cleared automatically on
   that evidence. **This is superseded by the scope reset below, which does not build any of it.** What survives is
   the caution: a retained marker is cleared by a person who has looked at the tipper, never by a check that the data
   looks consistent, and a journal lets a pending move be resumed but does not make reversing it safe if another
   record has since acquired the old alias or login.
3. *"Use the cached tipper" has a narrow meaning.* Added to the M7 acceptance items (6b): it applies only to an
   already-linked user whose background refresh returned `busy`, which means the refresh is deferred, not that
   sign-in failed, and only if the cached tipper was written for the
   *currently signed-in uid*. A first-time link or create that fails for any reason is a failed sign-in, never a
   successful one; after an account switch the previous account's cached profile is neither used nor shown, and is
   cleared; and any other refusal (`needs_audit`, `ambiguous`, `claimed`, `unverified_email`, `not_linked`) is a real
   refusal, not something to paper over with a cache.

**Scope reset (6 November 2026).** The owner called a halt to hardening: this is not a mission-critical app, it
should be fast and stable, and rounds of review answering ever rarer timing failures were making the project
harder to reason about, which is itself a reliability cost. The reviewing agent agreed and said it had contributed.
**The hardening scope is frozen.** The fixes already made stay (the token ordering, atomic and recoverable create,
the authentication and App Check checks through the real pipeline, the production-deploy safeguards, and the
lease, marker and ledger changes of the fifth review); nothing is refactored out, and nothing new is added to this
layer.

*What blocks a release from here:* a credible account takeover, lost tips, a broken everyday flow, or an unsafe
deployment. Reviews should say which of those a finding is, and otherwise mark it an acceptable limitation.

*Accepted limitations (documented, not release requirements):*
- A write that is delayed in the network for longer than a lease (several minutes) can still disturb the operation
  that took the tipper over. The Realtime Database has no conditional multi-node write, so there is no fencing
  token. The fence, the hold and the deadline make it rare; they do not make it impossible.
- An operation whose write ended with an unknown outcome leaves its in-flight marker (and, for a write still
  pending, a longer lease). That blocks a drain; it does not block ordinary requests.
- There is no automatic reconciliation, no per-tipper flag or block, and no clearing tool. **Decision 10 is
  therefore decided the simple way, below.**

*How a rare unresolved operation is handled:* the log says so (`marker kept ... without a confirmed outcome`, `lease
held`), the drain tool lists the marker, and the owner looks at the tipper and repairs it by hand. A brief
disruption to that tipper's profile changes is acceptable. When repairing, look at who holds the tipper's old alias
or login now, and clear the marker only after looking at the tipper. If this ever happens in practice, revisit it
then. (An alert on those log lines, set up in Cloud Logging, is optional and is not code.)

*Where testing goes instead:* ordinary use. Sign-in and the first link of an account, switching accounts, tipping,
kickoff locks, admin changes to tippers, reminders, and the existing scoring and badge functions after the redeploy.
The M7 cached-tipper items in 6b stay because they are about sign-in and account switching, which are everyday flows.

**B7 step 1, deployed in `off` (6 November 2026).** `scripts/deploy-functions.sh --only dart` deployed `b34349a1` to
the production project (recorded in `config/deployments/allowlist-deployments.jsonl`), run by the owner. The mode was
`off` with nothing in flight before and after, and no business call has been made.

*What the deploy did.* The Firebase CLI reported errors on both runs (6 and then 7 of the 10 Dart functions "failed",
each `Task index 0 failed: timed out after 30000ms`). None of the Cloud Run operations returned an error: the CLI
stops waiting for a long-running operation after about 30 seconds, and several rollouts take longer. The second
run created another new revision of every service, so repeating the deploy does not help. Afterwards all 10 Dart
services (and the two TypeScript badge functions) had their newest revision ready.

*One manual step was needed.* `register-device-token` and `unregister-device-token` were created but never got the
public-invoker setting, because the CLI timed out before the step that adds it, so Cloud Run refused every call
(403) before our code ran. The owner added `allUsers` with `roles/run.invoker` to both with `gcloud run services
add-iam-policy-binding`, the setting the other callables already have; App Check and the ID token still do the
authenticating. The runbook (`docs/backend-scoring-deploy.md`) now says to check this after the first deploy of new
functions.

*Verified, with nothing but unauthenticated requests and read-only commands.* Mode `off`, nothing in flight. All four
new callables return our JSON 401 (`UNAUTHENTICATED`) with no credentials and with garbage tokens, so the real wrapper
refuses before the handler. The six existing endpoints answer with their own refusals (401 for the three admin
callables, 403 `PERMISSION_DENIED` for the secret-protected three), so the redeployed binary starts and does not
crash. Every service has the public invoker; the function addresses follow `https://<name>-rjp4ue2oxa-as.a.run.app`.
The server's startup refusal of `FIREBASE_DEBUG_FEATURES` means those responses also show it is not set.

*Verified with a real tip.* The owner changed one tip in the unpaid tippers competition (there is no separate test
competition) at 07:55 UTC. `tipWrittenBackendScoring` started, `backend-scoring-command` answered 200 in 0.54 s on
the new revision, and the wrapper finished `ok`; `tipWrittenAppBadge` also finished `ok`. No request reached the Dart
`app-badge-count` endpoint in that window (the badge path may be gated by its flag), so that endpoint is verified
only as answering strangers. The project logged no entries at ERROR or above in the 25 minutes after the deploy.

*Pilot replaced by a replay of the real data (9 November 2026).* The write-enabled pilot with a throwaway account
was meant to show the identity logic copes with real data. It would also have written to production. A replay shows
the same without that. `functions_dart/test/identity/replay_snapshot_test.dart` loads a copy of the identity data
into the emulator and, for every linked account, runs the sign-in (`link-or-create-tipper`), a rename to the name
already held, and a token register and unregister. The copy is the 21 October dry-run snapshot with the reviewed
backfill patch applied, which is what production held after 22 October, so no production access was needed. The test
is skipped unless `IDENTITY_SNAPSHOT` names a file under `test/data/` (git-ignored), and prints counts and opaque ids
only. **Result: all 163 linked accounts refresh as `existing`; 161 renames to the current name work (the other two
tippers have no public name); all 163 token round trips work; no link, alias claim or public name changed; the nine
accounts that had no stored login were given one (`LogonIndex` 195 to 204); no lease, move or intent was left
behind; a sign-in took a median 6 ms and at most 52 ms in the emulator** (each refresh reads every tipper record,
which is fine at this size). The test fails on a deliberately damaged copy. *What it does not cover:* creating a
new account, first-time linking, real tokens, and the production database client, which is the same client the
scoring worker used successfully on 6 November. The reconstruction can be replaced by a fresh export and re-run in
seconds. **Recommendation: skip the production pilot** unless a later change makes it worthwhile; it adds
production writes and no new information.

*Not yet verified.* A real signed-in request refused by `off`. It is the only check that needs real tokens, it is
optional, and nothing depends on it.

**Scope.** `linkOrCreateTipper`, `updateTipperAlias`, `registerDeviceToken` and `unregisterDeviceToken`
(endpoint ids already in `dau_shared`), the server mode and admission wrapper of section 5, and the owner's
mode tool. They are deployed in mode `off` (nothing calls them until the R2 client ships), then exercised in
`pilot` by a write-enabled check, each deploy and check on a separate owner go. All use `RestDatabase` in every
environment (6a, finding 2), App Check enforced, a 60-second hard timeout, and the existing error types
(`failed-precondition` and a structured `reason` detail are added so the client can tell *why*).

**What the existing client does, which the callables must reproduce** (read from `tippers_viewmodel.dart`
and `firebase_messaging_service.dart`): anonymous users stay local-only and are never persisted; a signed-in
user must have a verified email before linking (the sign-in screen already enforces it, so requiring
`email_verified` loses nobody, but the client must force-refresh its token after verifying); an existing record
gets `logon` set to the account email, `email` filled if missing or invalid, `isAnonymous` cleared, `photoURL`
and the two account timestamps refreshed; a new record needs an alias that passes the uniqueness check, role
`tipper`, and `AppConfig/createLinkedTipper` true; the current match is exact-string on `logon`, then `email`.

**Design decisions (proposed, for the owner to confirm or change).**
1. **No Auth lookup at run time.** D2 wanted "claimed" verified against Firebase Auth. The backfill already
   audited every placeholder (`/Placeholders/{id}`), so a candidate is linkable only if its private `authuid` is
   absent, already the caller, or exactly its audited placeholder; anything else, **including ownership the
   callable cannot establish, is treated as claimed** and refused. This removes the unconfirmed M1 item (the
   service account's Auth-lookup ability) from the callable's critical path; the audits still need Auth.
2. **Candidates are the union of `logon` and `email` matches on the normalised address, across public and private
   records.** During coexistence a 1.4.x client can create a public record after the backfill that has no
   `TipperPrivate` entry, so scanning private records alone would miss it and create a duplicate. Discovery
   therefore merges every public and private record (the M3b merge: a present public field wins, the private
   record fills the rest). A match with no private record is *unaudited*: it counts as a candidate, so no
   duplicate is ever created, and is refused for linking (`reason: needs_audit`, "contact support") until the
   next backfill pass audits it. Exactly one audited candidate: link. None: create, if allowed. More than one,
   or any unaudited match: reject before anything is written. The scan runs only on the first-link path.
3. **Operations are recoverable, and "safe" means no incorrect access.** For link and create no access exists
   until the commit (claiming `AuthIndex[uid]`), so every earlier state grants none. After the commit access
   exists, and later steps (profile refresh, rename, a login-address change) never remove it. Link: `replaceIf`
   the private `authuid`, then claim `AuthIndex[uid]` as the commit, compensating on a lost race. Create: a
   durable `CreateIntents/{uid}`, claim alias, claim login, write records, claim `AuthIndex` last, release the
   intent. **Operations on one tipper are serialised** by the `IdentityLocks/{tipperId}` lease (owner = the
   operation id; a live lease refuses a second request as `aborted`, "try again"; an expired lease is taken over
   by compare-and-set on the exact stale value). **Moving a claim** (an alias on rename, the login address when
   it changes) is journalled in a new server-only node `/ClaimMoves/{tipperId}` = `{kind, fromKey, toKey,
   toValue, startedAtMs}` so a retry never has to guess the old claim from a name that has already changed:
   under the lease, finish any move already journalled; write the journal with `fromKey` taken from the tipper's
   *current* claim; claim `toKey` (held by another tipper: delete the journal and refuse `alias_taken` or
   `claimed`); write the new value (public and private as the mode requires); release `fromKey` only if this
   tipper owns it; delete the journal. A crash after any step is completed by the retry. A **login-address
   change** is a contact change, not an incidental profile overwrite: the verified address comes only from the
   authenticated token, it moves the `LogonIndex` claim as above and is refused if another tipper holds it, and
   the contact `email` is filled only when missing or invalid and never overwritten.
4. **Shape by mode.** `pilot` and `coexist` write the legacy public shape as well as the private record and
   indexes, so 1.4.x clients keep finding the tipper; `final` writes the minimal public shape (decisions 8, 9).
   One module builds both shapes. A callable never releases a claim that does not point at its own tipper and
   tolerates drift from a direct 1.4.x edit.
5. **`linkOrCreateTipper` is also the sign-in refresh.** R2 clients cannot write the private timestamps, so for an
   already-linked caller it validates the link and refreshes `acctLoggedOnUTC` and `photoURL` (a changed login
   address goes through the claim move of decision 3), returning `existing`. The client reads its own `AuthIndex` entry first and calls this in the background, so a
   function outage never stops a linked user starting. **Timestamps are server time** (`acctLoggedOnUTC` always,
   `acctCreatedUTC` only on create), not Firebase metadata: nothing depends on the difference.
6. **Token callables are mutating, so the mode gates them too, and ownership is coordinated, not merely written
   atomically.** An atomic update does not stop two callers that both scanned before either wrote from both
   adding the token. A new server-only index `/TokenOwners/{token}` = tipper id, changed only by compare-and-set,
   linearises ownership. Register: set the owner to the caller; scan `/AllTippersTokens` and remove the token
   from every other tipper (this also covers legacy holders, since 1.4.x clients write directly and do not know
   the index); write the caller's entry; read the owner again and, if it is no longer the caller, remove the
   caller's own entry. Two callers registering the same absent token at once therefore converge on the last
   compare-and-set winner. Unregister releases the owner **only if it is still the caller**, then removes the
   caller's entry, so a delayed unregister from a former owner leaves a later owner's registration intact. The
   token is validated as a database key. **Accepted limitation:** knowing a push token does not prove the caller
   controls that device. The token still identifies the original device, so a signed-in tipper who learned
   another's token cannot make notifications arrive anywhere new. What they can do is change which account that
   device is sent notifications for: the device's owner could stop receiving their reminders, and the device
   could be sent the other account's. That is no weaker than today (a 1.4.x client can write the token
   directly), the effect is limited to notifications, and it is recorded as an accepted tradeoff, not a
   security property.
7. **Mode tool: `functions_dart/bin/identity_mode.dart`, through the Firebase CLI** (so no extra credentials; built in
   Dart rather than Node so the drain is proven against the real admission code), with
   `set <mode>`, `status` and the drain of section 5. The drain **blocks on any stale marker** (listed by operation
   id, non-zero exit) and clears one only with `--ack-stale <opId>`; every mutating handler logs a start and an
   end line with its operation id so the owner can check. Its store takes an injected process runner so it is
   unit-tested; it writes the mode and a log entry, never the whole node (it would erase `inflight`). A missing
   or unreadable mode is `off`.
8. **Structured errors.** `reason` is one of `not_available`, `unavailable`, `unverified_email`,
   `ambiguous`, `claimed`, `alias_taken`, `invalid_alias`, `creation_disabled`, `not_linked`, `invalid_token`.

**Build order, each step committed and tested before the next.** B1 mode, admission wrapper, drain, mode tool.
B2 shared request and response types in `dau_shared` (used by the M7 client). B3 `linkOrCreateTipper`.
B4 `updateTipperAlias`. B5 token callables. B6 registration in `server.dart`, options, manifest test.
B7 deploy in `off` (owner go), then the `pilot` check with a throwaway user and scratch data (separate go).

**Proof required** (on the REST handle against the emulator, mutation checks included): every case in 6b for
M4b (including the scan-based ambiguity tests (a) to (e)); exact-placeholder replacement and refusal of any
other value; a real uid never replaced; racing uids, one winner; crash injection after every step of link,
create, rename and login-address change followed by a retry; double-tap create makes one record; alias and login
conflicts roll back cleanly; drift tolerance; mode gating of every mutating callable in every mode (`off` and a
non-pilot uid refused, `freeze` unavailable, `final` minimal shape); the admission and drain cases of 6b.
Added after the second review: **two concurrent renames of one tipper** leave exactly one alias claim for it and
no leak; **a crash after the name changed, then a retry** releases the right old claim; **a record created by a
1.4.x client after the backfill** (public, no `TipperPrivate`) is found and refused as unaudited, and no duplicate
is created; **two callers registering the same absent token at once** end with exactly one owner and one entry;
**a delayed unregister** from a former owner leaves the later owner's registration intact; a stale marker blocks
the drain until acknowledged.

**Risks.** An unaudited placeholder or record (decisions 1 and 2) leaves a person unable to link until the next
audit; an expired marker needs a human (decision 7); anonymous callers and unverified emails are refused
outright; the client must refresh its token after verification (M7); callable latency adds to first link only.
Estimate: 9 days as in the table, plus about a day for the claim-move journal and the token index.

### 6g. Progress: M6 started with R1-compat (9 November 2026; built, tested and deployed to production)

**Built.** `r1-compat` is a third variant of the rules generator (`scripts/build_admin_allowlist.mjs`), made from the
same template and the same admin allowlist as R1 and R1-recovery, and written to
`config/generated/database.rules.r1-compat.json`. It is R1 plus exactly two things, and no write permission:
- `AuthIndex/{uid}`: a signed-in, non-anonymous user may read **their own entry only**. A user with no link reads
  their own entry and gets `null`, which is a successful "no entry" and not a denial (the R2 client relies on that
  to know it must link).
- `TipperPrivate/{id}`: a signed-in user may read the record only when the link agrees in **both directions**
  (`AuthIndex[auth.uid] == id` and the record's `authuid == auth.uid`, the R2 owner rule). Allowlisted admins may
  read the whole node. A user whose database record merely says `admin` gets nothing extra.

Every R1 node is byte-for-byte as in R1, and `AliasIndex`, `LogonIndex`, `Placeholders`, `ServerConfig`,
`ClaimMoves`, `TokenOwners`, `CreateIntents` and `IdentityLocks` stay closed to every client. `database.rules.json`
(the file Firebase ships) is **still R1**; nothing has been installed or deployed.

**Tested.** `rules_test/r1_compat.rules.test.mjs` (23 tests): structurally the ruleset is R1 plus the two nodes with
no `.write` in them; against the rules engine the owner rule is refused when either side of the link is missing or
disagrees, to anonymous sessions, and to everyone else; no client, admin included, can write either node; the other
identity nodes stay closed; a few R1 behaviours are unchanged. `allowlist.test.mjs` and `deploy_scripts.test.mjs`
now cover the variant (fresh output, empty allowlist leaves the admin read `false`, the variants are not
interchangeable, a deploy is refused unless the compat rules are installed). Six deliberate breakages of the rules
(drop either half of the two-way check, let any user read any `AuthIndex` entry, let anonymous sessions in, add a
write, drop the admin read) are each caught. All 127 database rules tests and the 191 rules_test unit tests pass.

**Deployed on 9 November 2026** from `70eb9ba0` with `scripts/deploy-database-rules.sh --variant r1-compat`, at the
owner's request (recorded in `config/deployments/allowlist-deployments.jsonl`). Before the deploy the live rules equalled
the generated R1 exactly; after it they equal the generated R1-compat exactly. That comparison (the live document read
with the owner's `gcloud` login, compared as parsed JSON, printing only match or no match) is the check that the right
ruleset is live. **A bare unauthenticated REST read proves nothing about the rules:** the database enforces App Check in
front of them, so every path, public ones included, answers `401 Missing appcheck token` to a request without a token.
What is still to do is an ordinary-use smoke from the app (below), and the optional real-token read of a linked
non-admin's own `TipperPrivate/{id}`.

**How it was to be deployed** (kept for the rollback and for the next ruleset; nothing calls `AuthIndex` or
`TipperPrivate` from the app yet, so it should change nothing anyone sees):
1. `node scripts/build_admin_allowlist.mjs --install-rules --variant r1-compat`, then commit.
2. `scripts/deploy-database-rules.sh --project dau-footy-tipping-f8a42 --variant r1-compat --dry-run`, then without
   `--dry-run`.
3. Check: the live rules equal the generated R1-compat (see above); the app signs in and a tip saves as before; the
   tipper list still loads. (Optionally, with a real ID token for a **linked
   non-admin**, read your own `TipperPrivate/{id}`. That is the only read that runs the `root.child` lookup for the
   first time in production. Reading your own `AuthIndex` entry does not, and an allowlisted admin would pass
   through the admin permission and could miss a broken owner rule.)

**Rollback:** `--install-rules --variant r1`, commit, deploy. That is safe while no R2 client exists; once one does,
fix forward on `r1-compat` instead, because that client reads both nodes (section 9).

### 6h. Progress: M4c, scoped to what the app does (9 November 2026; all three callables built, tested and deployed in mode `off`)

**Scope, after the scope reset.** The plan listed six admin callables with leases, an operations journal and a
reaper. Reading the admin screens (`admin_tippers_edit_add.dart`, `admin_tipper_merge.dart`) shows the app does less:
an admin **edits** an existing tipper (name, contact email, role, paid comps) and **merges** two tippers (moves the
tips in every comp, optionally moves the login, deletes the original, copies its account link to the target). There
is **no admin "create tipper"**, no admin delete outside merge, and no separate reassign, so those callables are not
built. M4c is therefore: `unlink-my-account` (done), `adminUpdateTipper` (name through the existing claim move,
contact email, role with a last-admin check; the paid toggle stays a direct leaf write), and `adminMergeTippers`
(each step checks the current state, so running the same merge again finishes an interrupted one; no journal, no
reaper). The existing admin endpoints keep the compile-time allowlist until cutover.

**The gap found, and `unlink-my-account`.** The app's "delete account" removes only the sign-in account. The tipper
record keeps naming it, and linking never checks whether an old account still exists (design decision 1 in 6f: any
other owner is treated as a claim to respect), so signing up again with the same email would be refused as
`claimed`. `unlink-my-account` detaches the record, keeping its name, claims, tips and tokens, so a later sign-up
links back to it. **The client's delete flow (M7) must be: unregister the push token, then `unlink-my-account`,
then delete the sign-in account.** Unlinking needs a linked account, so the token goes first.

How it works, and the points that are easy to get wrong:
- It finds the records from the verified uid alone, and from **both sides**: the account's `AuthIndex` entry and every
  record whose private or public `authuid` names it. Once the index entry has gone the account no longer resolves
  through the index, so a retry of a call cut short at any step finishes the job from the record itself.
- Per record, under its tipper lease: release the `AuthIndex` entry (access ends first); **remove** the private
  `authuid`; **blank** the public `authuid` to an empty string. Each is a compare-and-set on "this account", so a
  record meanwhile linked to someone else is never touched.
- **Removed, not blanked, in the private record:** linking treats only a *missing* `authuid` as free (`replaceIf`
  tests for null), so an empty string would still be refused as claimed.
- **Blanked, not removed, in the public record:** the 1.4.x client parses it as a non-null string (`data['authuid']
  as String`) and would fail to read the tipper list without it. After the purge the public record has no such
  field and this step does nothing.
- An account with nothing attached is not an error (`unlinked: false`), and a second call changes nothing.

**Tested.** Twelve handler tests, including: the person signs up again with a new account and is linked back to the
same record, and the same sign-up without unlinking is refused as `claimed`; a record meanwhile linked elsewhere is
untouched; the post-purge shape; a retry finishing a call cut short (index already gone, only the public copy left,
crashes after each step); a stale duplicate naming the same account. Through the real callable pipeline it joins the
authentication, App Check, mode and malformed-request tests of the other callables, and a signed-in call detaches the
caller only, whatever the request names. Five deliberate breakages (index entry not released, private blanked not
removed, public removed not blanked, private cleared without checking the account, records found from the index only)
are each caught.

**Not covered.** A 1.4.x client that deletes its account still leaves the dead link, as it always did; re-registering
from an R2 client after that is refused as claimed until an administrator fixes it. This is rare and accepted.
Deploying the function is a separate go, and as with the last four it may need its public-invoker setting added by hand
(section 6f, B7 and `docs/backend-scoring-deploy.md`).

**`admin-update-tipper` (built, tested, not deployed).** An administrator changes another tipper's `name`, contact
`email` or `role` (at least one; the paid-competition list stays a direct write). What to know:
- **Who:** `requireAdmin` (`lib/identity/admin_gate.dart`), the one place that decides. Until the cutover it is the
  compile-time allowlist, the same list the rules and the other admin endpoints use, passed in by `server.dart`;
  at the cutover it becomes the linked tipper's role, a one-place change. Anyone else is refused (`not_admin`) before
  anything is read or written.
- **A refusal changes nothing.** Everything that can refuse is checked before the first write (a missing tipper, a
  record missing a half, a blank or over-long name, an address that is not an address, a demotion that would leave no
  administrator). The name goes first because it is the one step another tipper's claim can refuse (`alias_taken`),
  as the same journalled claim move a tipper's own rename uses, so a lost name leaves the email and role untouched.
  The email and role then go in **one atomic update**, to the private record and, in the legacy modes, the public
  copy a 1.4.x client still reads (after the purge only the private record). A field already holding the requested
  value is left alone and not listed in the result, so asking twice, or retrying after a crash, finishes only what was
  not done.
- **No journal.** Running the same request again completes an interrupted one.
- **Accepted limitation:** the last-administrator check and the write are not one atomic step, so two administrators
  demoting each other in the same instant could both pass it. With four administrators that is repaired by hand.
- **Tested.** Twenty handler tests plus wrapper-level tests through the real callable pipeline (a tipper who is not an
  administrator is refused with 403, an administrator renames another tipper, nothing-to-change and unknown-role
  requests are refused before the database is opened). Six deliberate breakages (admin check skipped, last-admin check
  skipped, email not mirrored, a name conflict swallowed, the tipper counted as another administrator, role not
  mirrored) are each caught.

**`admin-merge-tippers` (built, tested, not deployed).** Merges the `original` tipper record into the `target` and
removes the original, as the admin screen's merge has always done. Options: `mergeTips` (the original's tips in every
competition move to the target; where both tipped a game **the original's tip replaces the target's, as before**, and
the result says how many were replaced), `mergeLogon` (the original's login address becomes the target's), and
`dryRun` (report and change nothing, replacing the screen's trial mode). The original's sign-in account, if it has one,
always moves to the target, and the target's own account stops working for it. The paid-competition list is not merged
(the target keeps its own), as before.

The order is what makes it safe to run again: **everything the later steps need is read from records that still exist
until the very last step, and every step checks what is already done**, so running the same request again finishes a
merge that was cut short. There is no journal. Under the leases of **both** tippers, taken in id order so two merges
cannot deadlock: (1) tips, one atomic update per competition; (2) push tokens and their ownership in `/TokenOwners`;
(3) the login address (release the original's claim, then the usual claim move); (4) the account: the target's old
account loses its index entry first, then the target's `authuid` takes the original's, then `/AuthIndex` is pointed at
the target; (5) claims tidied, with the target made sure of its own alias and login claim (a duplicate pair can share
a key); (6) the original's two records removed together, the commit.

How it was tested. Sixteen handler tests, including the usual case (a new sign-in's record merged into the old one with
history, a game both tipped, tokens, claims, account), a dry run that changes nothing, an original with only a
placeholder and a target with no account, duplicates sharing a login or an alias, every refusal leaving the database
exactly as it was, both leases, and the strongest property: **a merge cut short at each of the seven steps and then run
again ends in exactly the same database as one that was not.** Two wrapper-level tests through the real callable
pipeline. Nine deliberate breakages are each caught (admin check skipped; original's tip node not removed; shared game
keeping the target's tip; token ownership not handed over; the target's old account keeping its index entry; target's
alias claim not made sure of; the original removed too early; only one tipper leased; a placeholder treated as an
account).

Two things the breakages taught me. One survived because the code was **redundant**: step 3 also claimed the login for
the target, and step 5 already does, so the extra claim was deleted, not tested. One survived because the test used a
placeholder that is an email address, which an invalid database key already rejects, so the placeholder check never
ran; the test now uses a placeholder that would pass for a key.

**Accepted limitations.** A person signing in as the original during a merge is told `busy` and carries on with the
cached tipper (the M7 rule). A merge touches several competitions in separate updates, so a failure partway leaves the
original in place for a re-run to finish. If someone else claims the original's login address in the instant between
its release and the target's claim, the merge stops with `claimed` and can be run again.

**M4c: the three callables are built and tested; none is deployed.** Remaining on the server: deploy them in mode
`off` (a separate go; each new function may need `allUsers` `roles/run.invoker` added by hand after the CLI's timeout,
section 6f B7), then M5 (live score aggregator, shadow first) and M6's freeze and R2 rulesets, then the client (M7) and
the cutover (M8). **The server identity work is not "finished" until the cutover items below are done.**

**Deployed in mode `off` (9 November 2026)** from `144c1e89` with `scripts/deploy-functions.sh --only dart`, run by the
owner, as a focused batch: `unlink-my-account`, `admin-update-tipper` and `admin-merge-tippers` created, and the other
ten Dart functions updated. The CLI again printed `timed out after 30000ms` and listed six functions as failed
(`admin-merge-tippers`, `admin-update-tipper`, `admin-scoring-rescore`, `app-badge-count`, `unregister-device-token`,
`update-tipper-alias`); `gcloud` showed none had errored and every one of the 13 services had its newest revision ready.
As before, the two functions whose create timed out (`admin-update-tipper`, `admin-merge-tippers`) did not get their
public-invoker setting, so Cloud Run answered 403 before our code; the owner added `allUsers` with `roles/run.invoker`
to both. Verified afterwards with nothing but unauthenticated requests and read-only commands: all ten callables
answer our JSON 401 for no credentials and for garbage tokens, the three secret-protected endpoints answer their own
403 `PERMISSION_DENIED`, every service is ready, and the identity mode is `off` with nothing in flight. Recorded in
`config/deployments/allowlist-deployments.jsonl`. **The pattern has repeated across three deploys, so plan for it. Each
timeout is inconclusive until the intended revision, the endpoint's response and its permissions have been checked: here
the revisions were all fine, but the two services whose create timed out had to have their invoker permission repaired,
so the timeout was not entirely harmless.** What the 401 and 403 checks show is that the endpoints are reachable and
refuse those unauthenticated requests. They do not show a successful business operation, an acceptable limit for a
deploy in `off`. And `off` blocks business mutations through the *new identity callables* only: it does not disable the
existing admin endpoints, or the legacy client writes that R1 and R1-compat still permit.

**Corrections after a seventh review (9 November 2026).**
1. *The merge refuses a known clash before it moves anything.* The preview used to check only that both records
   exist, so a successful preview could be followed by a refusal after the tips had already moved. One check is now
   shared by the preview and the merge, and runs before the first write: the original's login address (when it is being
   moved) or its sign-in account already held by a third record is refused as `claimed`, with nothing changed. A clash
   that appears in the instant between the check and the step is still caught by the step. A login held by a third
   record is no clash when the login is not being moved.
2. *"Another administrator" means one who can sign in.* The last-administrator check counted any record marked
   `admin`, including a historical one nobody can sign in to. It now counts only an administrator whose private
   `authuid` is a real account that `/AuthIndex` points back at.
3. *The client's delete flow is still to be written (M7), and I overstated it.* The app today deletes the sign-in
   account first and does not call `unlink-my-account`. When it does, the order is: reauthenticate if the account
   needs it, unregister the push token, `unlink-my-account`, then delete the sign-in account. Reauthentication comes
   **before** unlinking, so a user who cancels it is not left half-unlinked. The tests must cover a deletion that fails
   after the unlink and is then retried: the person is signed in but unlinked, the next `link-or-create-tipper`
   links them back (`linked`), and unlinking twice is harmless (`unlinked: false`).
4. *Administrator access is still the compile-time allowlist.* `requireAdmin` is the one place that decides, and it
   uses the list the rules and the other admin endpoints use. **Until it is switched to the validated private role at
   the cutover (part of the M8 exit "allowlist removed"), a role change made by `admin-update-tipper` changes what the
   admin screens show and who counts as an administrator in the data, but not who may call the admin endpoints.**
   Promoting or demoting someone does not yet grant or remove their access.


**A mistake of mine, found and fixed on the way.** The earlier replay test skipped its test but not its `setUpAll`,
which read the snapshot, so the whole suite failed whenever the snapshot variable was unset, which includes the deploy
script's test gate. It is now skipped as a group, and the suite passes with and without the variable.

### 6i. Progress: M5, the live-score aggregator (9 November 2026; built, wired, exercised end to end on the emulators, and DEPLOYED IN SHADOW)

**What it is.** The 1.4.x client builds the `current` live-score snapshot from its own local list and writes it beside
`history`. The R2 client will write `history` only, so the server derives `current` from it. The rule is the one the
client has always applied: each team keeps its **three most recent** submissions; a team's displayed score is its
**latest**; the snapshot's time and tipper are those of the latest submission of either team; an **official score
overrides all of it**. **`gameComplete` is never true in anything the aggregator writes**: only an official score
completes a game, so the snapshot's flag and each entry's flag are written `false` whatever a legacy client left in
`history` (reviewer finding on `a425f10f`; a snapshot that says `true` is also a difference the aggregator corrects).
The scoring worker already reads `current` and a write to it already triggers a rescore, so nothing downstream
changes.

**Built** (`functions_dart/lib/live_scores/`): `live_score_aggregate.dart` is the pure calculation, from a game's
`history` to the snapshot, plus a comparison that names how two snapshots differ (the list's order, the count and the
spelling of a time are not differences); `live_score_aggregation.dart` is the handler and the mode flag.

**The history contract for the R2 client (M7).** An entry is the client's `CrowdSourcedScore.toJson()` shape:
`submittedTimeUTC`, `tipperID`, `scoreTeam` (`home`/`away`), `interimScore`, `gameComplete` (false). The time used
for ordering is, in this order: a numeric **`t`**: the database's server timestamp in **milliseconds** (what the R2 rules force,
`t === now`, so the one time a client cannot choose) or microseconds since the epoch (plausible only from 2001 on, so a
value in seconds is ignored); else the parsed `submittedTimeUTC`; else the push key's leading microseconds. Equal
times are broken by key, so the result never depends on delivery order. An entry that cannot be read (no tipper, a
team that is not home or away, a score that is not a number, no time) is counted and ignored, never guessed at.

**The handler.** Mode lives at `/ServerConfig/liveScores/mode`: `shadow` (the default, and what anything missing,
unreadable or unrecognised means), `active`, `compat`. **In `shadow` nothing is written**: it compares with the
`current` already there and logs `match=true/false` and how it differs. In `active` and `compat` (the same write; the
difference is the owner's decision to enable `compat` while legacy writers exist) the write is a compare-and-set that
is skipped when `current` already shows this game (a rewrite would only trigger a pointless rescore) or records that
it was computed from at least as much history (`basedOnCount`), so a slow, older computation cannot undo a newer one.
A snapshot a legacy client wrote has no count and is replaced if it differs. A game with an official score is left
alone; if one arrives *while* the write is in flight, the snapshot is removed again. Every run recomputes from the
whole of `history`, so duplicated, shuffled or simultaneous runs agree.

**Tested.** The calculation is held to a faithful port of the client's own submit-and-trim logic
(`test/support/client_live_score_oracle.dart`, using the shared `Scoring.currentScore`): **three hundred random game
days** with several tippers whose clocks disagree, so some arrive out of order, with the history shuffled before it is
handed over, must show the same game as the client's own `current`. Also: each ordering rule; keys that sort against
time; entries that cannot be read; equal times. Against the emulator: shadow never writes; the version guard; an
unchanged snapshot, from the aggregator or from a legacy client, is not rewritten; an official score up front, and
arriving mid-write; simultaneous runs; and **twenty random games with two legacy clients overwriting `current` from
their own stale lists, the aggregator running after every submission**: it put `current` right every time and then
changed nothing (it does not flap), and the test insists the clients really did disagree so it cannot pass vacuously.
Eleven breakages of the calculation and handler were each caught; two survived at first, and each taught something (a
test where push keys sort against time, which the oracle's own keys never do; and one for a legacy snapshot that
already shows the game).

**One consequence worth knowing.** A 1.4.x client writes `current` from its *local* list, so two tippers submitting at
nearly the same moment can overwrite each other's scores in `current` while `history` has both. The aggregator
corrects that **when it next runs**, which is on the next `history` event. In `compat` a later legacy write can
therefore replace the corrected result, and it stays replaced until another submission triggers the aggregator. That
is an accepted limit of `compat`, not a guarantee that the display never changes back; the mixed-writer tests show
convergence after the aggregator runs, nothing more.

**The version guard assumes `history` only grows.** `basedOnCount` says which of two computations saw more entries.
Editing or deleting an existing entry can change the right answer without raising the count, and the guard would
then leave an older snapshot in place. No versioning scheme is added for that. Instead:

- **R2 makes ordinary client `history` entries immutable** (create-only: no overwrite, no delete; M6). A client
  cannot correct or remove its own submission, which also means a tipper cannot rewrite what the scoring saw.
- **An administrator corrects a game by hand**, with Admin SDK or console access: remove `current` first, then fix or
  delete the bad `history` entry. Removing the entry is an event the trigger delivers, and with no `current` left the
  aggregator writes a fresh one from what remains (in `shadow` it only reports, so an administrator running a
  correction in `shadow` writes `current` themselves or sets the mode to `active` for the moment). Rare and
  manual, which is the right size for it.

**Wired** (this commit):

- `functions/src/backend_scoring.ts`: a new trigger, `liveScoreHistoryWrittenBackendScoring`, on
  `Stats/{comp}/live_scores_backend_v1/{game}/history/{entry}`. A create, a change and a removal each post one
  `liveScoreHistoryWritten` command to the existing worker endpoint with the existing shared secret; an unchanged
  write posts nothing. It lives beside `liveScoreWrittenBackendScoring` (on `.../current`) and the two paths are
  disjoint, so the aggregator's write to `current` can start a rescore but never another aggregation.
- `functions_dart/bin/server.dart`: `executeBackendScoringCommand` dispatches the new type to
  `runLiveScoreAggregation` on a `RestDatabase` (the compare-and-set needs one). It is not given an idempotency
  record: every run recomputes from the whole history, so a duplicate is harmless and a record per submission would
  only be more writes. The shared enum `BackendScoringCommandType` gains `liveScoreHistoryWritten`.
- Nothing changes in what ships to users: the new function only reads `history`, `current` and the game, and writes
  `current` only in `active` or `compat`, which stay off until the owner decides.

**Run end to end on the emulators.** `scripts/test-live-score-wiring.sh` starts the Database and Functions emulators
inside the operating-system boundary (no network but loopback, no credentials, its own project, ports and throwaway
secret) and runs `functions_dart/test/e2e/live_score_wiring_e2e_test.dart` against the real TypeScript trigger and
the real Dart worker, with a small synthetic competition. It checks the three things the calculation tests cannot:
(1) a history submission reaches the real worker command and handler, and the worker refuses a request without the
secret, with the wrong one, or by `GET`, and rejects a command with no game; (2) in `shadow`, the default, the
database is left exactly as the submission left it, with no `current`, no scoring record and no statistics;
(3) in `active`, writing `current` triggers the existing rescore once per change and the aggregator runs once per
submission, never again because of its own write, and a stale legacy write of `current` is put right by the next
submission; and the fixture import's clearing of a finished game's live node is not undone (every aggregator run it
causes stands aside for the official score).

Six end-to-end tests, all passing, run twice in a row on the final code. Five breakages of the wiring were each caught: the
wrapper posting a scoring command instead of the history one, a trigger on the wrong child, the worker sending the
command to scoring, the worker ignoring the mode, and a trigger that also fires on `current` (aggregation triggering
itself). The run also found two defects outside M5: the M4c debug-features guard refused to start the worker in the
local emulator (corrected, section 6f note above), and a malformed command to the worker answered `500` instead of
`400` (now `400`). Elsewhere: 58 TypeScript tests (7 new), 698 Dart tests on the emulator, `flutter analyze` clean.

**Deploying it.** Two codebases, in this order: the Dart worker first (so it understands the new command), then the
TypeScript functions (which start sending it). The other order is harmless but noisy: the worker answers `400` to a
command type it does not know and the wrapper logs a warning. The aggregator starts in `shadow` because
`/ServerConfig/liveScores/mode` does not exist; in `shadow` the only effect is a log line per submission.
Production `shadow` establishes that the services deploy and stay healthy; there is no need to manufacture
production activity, and the synthetic end-to-end run is the functional evidence until real submissions exist in
March. **Neither `active` nor `compat` is enabled by this deployment; each is a separate decision of the owner's.**
`compat` is the prepared fallback for while 1.4.x clients can still write `current`, which can be before the R2 rules
(section 3, Gate B). `active` belongs after the R2 rules have closed those writes.

**Deployed in shadow (9 November 2026, from `a1351b8d`, which has the code of `3e7f3849`; the owner ran both deploys).**
Order: the Dart codebase, then the TypeScript one.

- *Mode first:* `/ServerConfig/liveScores/mode` read `null` (missing), and again `null` after both deploys, so the
  aggregator runs in `shadow`. Neither `active` nor `compat` was enabled.
- *Dart:* the CLI ended with "Failed to update" for four services (`admin-check-fixture-url`,
  `scheduled-fixture-download`, `link-or-create-tipper`, `admin-merge-tippers`), all 30-second timeouts. Checked
  directly instead: all 13 services on a revision created 11:16 to 11:19 UTC, ready; `allUsers` invoker intact on all
  13; unauthenticated `GET` 405 everywhere, `POST` 401 (callables) or 403 (secret-guarded); the new command type with
  a wrong secret 403; no error-level log entries.
- *TypeScript:* the first two attempts failed before touching any function (a storage upload error, then "An unexpected
  error has occurred" at the same early stage); production was checked unchanged between attempts, and the third
  attempt completed. `liveScoreHistoryWrittenBackendScoring` exists in `asia-southeast1` (1st Gen, `ref.write`) on
  `Stats/{compKey}/live_scores_backend_v1/{gameKey}/history/{entryKey}`; `liveScoreWrittenBackendScoring` is still on
  `.../current`; the other triggers are unchanged; all 11 TypeScript functions are `ACTIVE`; the new function has the
  same environment variable names as its siblings; no error-level log entries since.
- *Not exercised in production:* there are no live games until March, so the first real submission will be the first
  `[liveScores] shadow ...` line. The emulator end-to-end run is the functional evidence until then.
- *To check before March:* the Firebase CLI warns that the `functions.config()` API and Runtime Config shut down in
  March 2027. Nothing in this repository calls it, but whether the project still holds Runtime Config values has not
  been checked.

### 6j. Progress: M6, the freeze and R2 rulesets and the rollback rehearsal (9 November 2026; built and tested, not installed, not deployed)

**Built** (nothing is installed in `database.rules.json`, which is still R1-compat; nothing is deployed):
- Two more variants of the rules generator (`scripts/build_admin_allowlist.mjs`), written to
  `config/generated/database.rules.freeze.json` and `database.rules.r2.json`. `freeze` is derived from R1-compat.
  `r2` has its own template, `config/database.rules.r2.template.json`, and takes **no allowlist**: an administrator
  is the validated private role (`TipperPrivate[AuthIndex[uid]].tipperRole === 'admin'` where that record's `authuid`
  is the uid), every lookup guarded with `exists()` so no outcome rests on a rule error. The output is identical
  whatever the allowlist holds, and a test asserts no uid literal appears in it.
- `scripts/deploy-database-rules.sh` accepts both and **enforces the cutover order from the deployment log**:
  `freeze` only straight after `r1-compat`, `r2` only straight after `freeze` (redeploying the same one, and rolling
  back to `r1-compat` or `r1`, are never refused). `--out-of-order` overrides it with a warning; a dry run reports
  the refusal too. Each prints what it is.

**Freeze (cutover step A1).** R1-compat with every identity-bearing write closed to all clients, administrators
included: no record created, deleted or replaced, no whole-node `AllTippers` write, `name`, `email`, `logon` and
`isAnonymous` closed, and the tipper-level `AllTips` write (a tip-node merge or delete) closed. Kept: reads, tipping at
the game level, photos, login timestamps, device tokens, live-score entries, the admin-only reference data, and the
paid toggle, now a narrow leaf write for allowlisted administrators on `compsParticipatedIn`. **Known cost, accepted:**
a 1.4.x client writes `logon`/`isAnonymous` at sign-in only when they differ from the stored record, so a settled
account signs in normally, but an account whose stored `logon` differs from its email has its whole sign-in batch
refused for the length of the window (tested; the window is about 30 minutes at 04:00 and by February few 1.4.x
clients remain).

**R2, rule by rule** (original design D1 to D9, as built):
- *Administrator and owner:* the validated private role and the two-way link, as above. A retired allowlist uid, a
  user whose PUBLIC record says admin, a tampered index, an anonymous session with a perfect link and an unlinked user
  are none of them administrators or owners.
- *`AllTippers`:* readable by any session (an anonymous one included), not before sign-in. **No client creates,
  deletes, replaces or renames a record, administrators included.** The only direct writes are the owner's `photoURL`
  (a string of at most 2048 characters) and an administrator's `compsParticipatedIn` (the paid toggle). The login
  timestamps are not client writes: the callables stamp them. The record must keep its `name`.
- *`AuthIndex` and `TipperPrivate`:* as in R1-compat, but the administrator read is the validated role. No client
  writes either.
- *`AllTips`:* the competition level is administrators only; a tipper's own node is readable by the owner and
  administrators; a single game's tip is readable by anyone **with a session** once the game has started, and by its
  owner and administrators before. The owner writes only before kickoff (the numeric `DateUtcEpochMs`, to the
  millisecond); administrators write at any time and may merge or delete a whole node. A missing or non-numeric
  kickoff fails closed for both. The shape is the R1 shape (compact or legacy) with `t` no more than a day ahead of
  server time.
- *`Stats`:* readable by any session. The **only** client write is a live-score `history` entry: create-only (no
  overwrite, no delete by a tipper), by a validated linked tipper for themselves (`tipperID` is their own), only once
  the game has started and before it has an official score, with `t` equal to the database's own `now`, a whole-number
  score from 0 to 300, `scoreTeam` home or away, and nothing else in the entry. `current` and every scoring branch
  are server-only. An administrator may delete an entry (a correction).
- *Closed to every client by absence from the rules:* `AliasIndex`, `LogonIndex`, `Placeholders`, `ServerConfig`,
  `ClaimMoves`, `TokenOwners`, `CreateIntents`, `IdentityLocks`, `IdentityOps` and `AllTippersTokens`, and anything
  not named (default deny).
- *Deliberate differences from the original text:* a started tip is readable only **with a session** (the design's
  `now >= kickoff` alone would have let an unauthenticated request read it); `Diagnostics` is readable by any session
  rather than administrators only, because the Android resume diagnostic reads it; the history entry takes the
  server's `t` in **milliseconds**, and the aggregator now reads that (a follow-up to M5: it had treated only
  microseconds as plausible and would have ignored the one time a client cannot choose).

**Tested.** Against the rules engine: `r2.rules.test.mjs` (67), `freeze.rules.test.mjs` (36), and
`client_matrix.rules.test.mjs`, **156 cells: 38 operations a 1.4.x client or an R2 client performs against each of R1,
R1-compat, freeze and R2, every cell stated before it was run**, with each refusal also checked to leave the data
exactly as it was. All 156 matched. Tooling: the generator, drift detection, the five variants told apart, and the
deploy order guard (`allowlist.test.mjs`, `deploy_scripts.test.mjs`). **Twenty deliberate breakages of the rules were
each caught** (administrator read from the public record, the uid comparison dropped, the ownership check dropped,
anonymous sessions let in, started tips readable without a session, the kickoff lock dropped, history made
overwritable or naming another tipper or accepting a client time or accepted after an official score, a client write
on `current`, a rename and a photo for anyone, the allowlist back in; and in freeze: the whole-node write, record
creation, rename, tip-node merges left open, and the paid toggle open to anyone or lost). One real finding came from
the first run: the unauthenticated read of a started tip.

**The rollback rehearsal and restore tool (design section 9).** `functions_dart/bin/identity_restore.dart` plans, and
with `--apply --project <id>` writes, the copy of each purged field from `/TipperPrivate` back to the public record. It
never overwrites a field the public record has, writes `authuid: ''` for an unlinked tipper (the legacy way of saying
"no account"; 1.4.x reads the field as text), does not bring back the deleted legacy `active` and `tipperID`, and
**blocks without writing** for a tipper with no public record or no role. `--apply` also refuses unless the identity
mode is `freeze` or `off` and nothing is in flight, re-reads and requires the identical plan, writes one update with
triggers suppressed, then re-reads and requires an empty plan. It prints counts and opaque ids only; its `--out` patch
holds email addresses and belongs under `test/data/`. Tested as a planner (12), as a CLI against in-memory stores (17,
including the Firebase CLI store through a fake runner), and as a **rehearsal on the emulator** (9): a realistic
pre-cutover database (linked, administrator, unlinked, no-alias, anonymous, legacy-field tippers), a model of cutover
step B (the plan's own definition), the restore through the same code the owner runs, and a comparison with what was
there before: identical bar the two deleted legacy fields and the placeholder name. Eleven breakages of the restore
were each caught. **The real purge tool is M8's**; its tests should run this same round trip with it in place of the
model in the rehearsal.

**For M7 and M8, from the rules.** The R2 client must: write a history entry as `{tipperID, scoreTeam, interimScore,
t: ServerValue.timestamp}` and nothing else; read other tippers' tips game by game after kickoff, never at the tipper
or competition level; never write `name`, `email`, `logon`, the timestamps or tokens; and sign in (anonymously, for
browsing) before attaching any listener other than `AppConfig`. The admin screens that edit a tipper must call the
M4c callables, not write the record.

**Review fix: the restore also checks the records that have no private copy.** The planner first looked only at
`TipperPrivate`, so a purged public record whose private copy was missing would have been skipped and the run reported
as verified. It now checks both sets of ids and **blocks** a public record that has no private copy to restore from
and lacks `authuid` or `tipperRole` (what the legacy shape requires); one that already has both is left alone. Tested
as a planner, in the CLI and in the emulator rehearsal; removing the check fails four tests.

**Validating the rules against production, without deploying.** `scripts/validate-database-rules.sh --project <id>`
(default: `freeze` and `r2`; `--variant all` for the five) runs `firebase deploy --only database --dry-run` for each,
from a throwaway `firebase.json` that points straight at the generated file. The Firebase CLI submits the rules to the
service for validation (`dryRun: true`) and skips the release. `--dry-run` is hard-coded, `database.rules.json` is
never touched (nothing to install or put back), the project must be named, and it refuses stale generated rules.
Tested against the stub firebase (7 tests). **It contacts the project, so it runs only on the owner's explicit go.**
Production's rules compiler has limits (expression length, depth) the emulator may not enforce, and R2's longest
expressions are about a thousand characters, so it is worth doing months before the window rather than in it.

**Dependencies to keep before the cutover** (from the review of `91543eff`):
1. **Deploy the aggregator's millisecond-`t` support before any R2 client sends that format.** It is committed
   (`a20fa8f4`) but not deployed; the next Dart release carries it. Until then the deployed aggregator would ignore
   the server time and fall back to the client's clock.
2. **M7 must send exactly the allowed history fields** with a server timestamp: `{tipperID, scoreTeam, interimScore,
   t}`. The client's existing serialized score object (`CrowdSourcedScore.toJson()`) carries `submittedTimeUTC` and
   `gameComplete`, which the R2 rules reject, so the new client builds the entry itself and does not reuse it.
3. **Rehearse the rollback again with the real purge tool** once M8 builds it, in place of the model.
4. **Switch the server's administrator check in the same window as the R2 rules.** The rules no longer use the
   allowlist, but the Dart admin endpoints and the new callables still do (`requireAdmin`, the compile-time list);
   changing the rules alone does not retire it. M8 moves them to the validated private role and removes the list.

**Validated against production (9 November 2026, on the owner's go).** `scripts/validate-database-rules.sh --project
dau-footy-tipping-f8a42` ran for `freeze` and `r2`: the service reported "rules syntax ... is valid" for both and
released nothing. Afterwards the live rules were read back and still equal the generated R1-compat exactly, and no
deployment was recorded. So neither ruleset trips a production limit on length or depth.

**Still to do.** The real purge and cutover scripts (M8); M7's client against these rules.

### 6k. M7 scoping: the R2 client (9 November 2026; a PROPOSAL, awaiting the owner's go; no client code changed)

**What the survey of the client found.**
- *Startup:* the post-frame warm-up in `main.dart` (about line 550) creates `TeamsViewModel`, `TippersViewModel` and
  `DAUCompsViewModel` together, which attach their listeners at once. Under R2 `Teams`, `AllDAUComps` and
  `DAUCompsGames` need a session, so those listeners must wait for a Firebase user (anonymous will do for browsing),
  and every listener needs an `onError` that re-subscribes when the auth state changes.
- *Linking:* `TippersViewModel` (1043 lines) scans the public tipper list by uid, email and login
  (`_findExistingTipper`, `_createNewTipperIfNeeded`, `_updateExistingTipper`) and writes the record itself. All of that
  becomes: read my own `AuthIndex` entry, validate it against my own `TipperPrivate`, call `link-or-create-tipper` only
  when there is no entry, with the cached-tipper rules already decided.
- *Tips:* the competition-wide tips listener (`TipsViewModel` with no tipper) is used **only by the admin merge**
  (`mergeTipsForComp`), which becomes the `admin-merge-tippers` callable. Everything else uses the per-tipper listener.
  Under R2 that works for my own tips; for another tipper's tips (the drill-down) it must become per-game listeners for
  the tipper being viewed, which is a handful, not a fan-out of every tipper.
- *Live scores:* `StatsViewModel._writeLiveScoreToDb` writes `current` and history together, with the whole serialized
  score (`submittedTimeUTC`, `gameComplete`). Under R2 it writes history entries only, built field by field.
- *Tokens, account deletion, admin:* `firebase_messaging_service` reads every tipper's tokens and writes the token node
  directly (`_removeTokenFromOtherTippers`), `deleteAccount` deletes only the Firebase user, and the admin screens
  write tipper records directly. These become the token callables, the unlink-then-delete flow, and the admin callables.

**Proposed slices, each testable on its own** (the estimate is the plan's 12 to 15 days):
1. *Identity service:* one thin wrapper over the callables using the shared request/result types, typed errors, a fake
   for tests. (2 d)
2. *Link flow, public/private tipper, auth-aware startup, cached tipper:* the core and the riskiest slice. (5 to 6 d)
3. *Tips:* per-game listeners for other tippers, and the queued-tip message that does not promise delivery after
   kickoff, with a late rejection surfaced. (3 d)
4. *Live scores:* history-only writes with the server timestamp; remove the `current` writer and `gameComplete`. (1.5 d)
5. *Tokens and account deletion:* token callables; reauthenticate, unregister the token, `unlink-my-account`, delete the
   Firebase user, with a failure after the unlink being retried. (2 d)
6. *Admin:* screens read `TipperPrivate`; edits, roles and merges through the callables; delete
   `GamesViewModel.updateGameAttribute` and `saveBatchOfGameAttributes`. (3 d)
7. *Small items:* name changes through `update-tipper-alias`; the Update App button on web (D13). (1 d)
8. *Integration:* the real-client smoke harness against R1-compat and R2 with the real callable code, and the
   reference-data checks of 6b. (3 d)

**Two things the owner should know before starting.**
- **A linked user needs no callable to sign in under the R2 client** (read my `AuthIndex` entry and my `TipperPrivate`
  record, both allowed by R1-compat, which is live), so the R2 client can be tried on production for the read paths
  already. But a new sign-up, a name change, a push-token registration and the delete flow all call callables, which
  refuse everyone while the mode is `off`. To soak the build on the owner's devices the mode must move to `pilot` with
  the owner's uids, and to `coexist` before any R2 client reaches other users. Each is a separate owner decision and
  a deployed check.
- **Slice 2 changes how every user signs in.** It is the one to review most carefully, to soak longest, and not to
  squash with the others; the other slices only change what happens after sign-in.

**Slice 1 built (9 November 2026).** `lib/services/identity_service.dart` is the typed wrapper over the seven
callables, `lib/services/functions_identity_invoker.dart` the `cloud_functions` adapter. Every call returns the
shared typed result or throws an `IdentityFailure` with a kind (`refused`, `transient`, `unauthenticated`,
`unexpected`) and the server's machine-readable reason; an answer of the wrong shape is an `unexpected` failure, never
a crash; a timeout or lost connection is a `transient` one. **Decision taken: how the client finds the callables.**
They are Cloud Run services, so the `cloudfunctions.net` form does not exist for them; the address is
`https://{name}-rjp4ue2oxa-as.a.run.app` (the same shape as the admin URLs already in `AppConfig`). The pattern is a
built-in default with an optional `AppConfig/identityFunctionsURLPattern` override, so the app works with no new
configuration and an address can still be redirected without a release. Tested with 25 tests; seven deliberate
breakages caught.

**Slice 2 built (9 November 2026), in four commits.**
- *2a, the model.* `Tipper.fromJson` read `authuid` as a non-nullable string, so one purged public record would have
  crashed the whole tipper list for an R2 client. A missing `authuid` now reads as `''`. Equality compares the record
  key when both tippers have one (only the signed-in tipper's own object knows its account id). `Tipper.fromRecords`
  builds the signed-in user's own tipper from the public record with the private one over it; `withIdentityOf`
  carries those identity fields across every refresh from the public list (found in review of my own change: without
  it an administrator would have lost the admin menu at the first refresh after the purge).
- *2b, listeners.* `authAwareStream` opens a listener only while a user is signed in, closes it on sign-out, and
  reopens it on the next token event after a failure (never on a timer). The tipper list, teams and competitions use
  it; nothing awaits their first load before sign-in.
- *2c, linking.* `LinkedTipperResolver` reads the caller's own `AuthIndex` entry and the private record it names and
  calls `link-or-create-tipper` only when there is no valid link; a failed read is retried and is **never "missing"**
  (the server is asked to link only after a read that worked and found nothing). `CachedTipperStore` and
  `TipperLinkService` hold the kept-tipper rules already decided: open from it, confirm in the background, a delay
  keeps it, a refusal or an unlinked account throws it away, a first link that fails is never answered from a cache.
- *2d, wiring.* `SignInLinkController` holds the sign-in page's linking state (the page only draws it); the old
  scan-and-write code in `TippersViewModel` (`findExistingTipper`, `updateOrCreateTipper`, the finders by email and
  login, `checkEmail`, the creation) is deleted; the services are registered in `main.dart`, built lazily so the
  optional `AppConfig` address override and the competitions lookup are read when needed. A competitions load that
  stalls no longer holds up sign-in: the tipper arrives without the paid comps and the public list supplies them.

**What changes for people, and what to confirm.**
1. *The R2 client no longer writes `logon`, `email` or `isAnonymous` at sign-in* (they are server-owned), and it
   **does not refresh `acctLoggedOnUTC`**: the server stamps it only when `link-or-create-tipper` runs, and a linked user
   never calls it. The admin tipper list's "last login" column will stop moving for R2 users. **Decision for the owner:**
   accept that, or have the client call the callable once per session (which would make every sign-in depend on it).
2. *A linked account signs in on production already, with the mode `off`:* it needs only the two reads R1-compat
   allows. A new account, or one with no `AuthIndex` entry, needs the callable and is told "Signing in is not available
   right now" until the mode leaves `off`.
3. *A kept tipper whose link is refused or has gone* now closes the app on a message ("sign out and sign in again")
   instead of carrying on silently.
4. A guest is unchanged.

**Tested.** 25 + 11 + 11 + 3 + 18 + 17 + 23 + 5 new tests in the app and shared package, and 36 breakages caught across
them; the whole app suite passes (1006) apart from the two live support-site network tests, which fail the same way
without these changes. **Not tested by anything automatic:** the sign-in page's drawing and the registration in
`main.dart`, because they need Firebase Auth. The decisions are in the controller (tested); the page maps its phase to a
screen. They need a run on a device or the emulators; a checklist is in the slice 2 hand-over to the owner.

**Running the new client against the local emulators (found on the owner's first run, 9 November 2026).** A fresh local
emulator greets the first sign-in with "Signing in is not available right now": the seeded production snapshot has no
`AuthIndex` or `TipperPrivate` for the emulator's own accounts and the identity mode is unset (`off`), so the client
finds no link, asks the server, and the server correctly refuses. `scripts/seed_rtdb_emulator.sh` now sets the mode to
`coexist` after seeding (`SEED_IDENTITY_MODE=off` keeps the refusal for testing it); for an emulator already running,
`PUT /ServerConfig/identity/mode` to `"coexist"`. In `coexist` an emulator account whose verified email matches a seeded
legacy record is refused as `claimed` (that record's account id is a production one), and an account with no matching
record is asked for an alias and given a new tipper; signing out and in again then takes the read-only path.

**Decisions wanted.** (1) Go to start with slices 1 and 2. (2) Whether to take the mode to `pilot` for the owner's
devices once slice 2 is in a TestFlight build.

**Slice 3 built (9 November 2026): tips.**
- *Another tipper's tips, one game at a time.* The only screen that read a tipper's tips other than the signed-in
  user's is the round game scores drill-down. It now builds `TipsViewModel.forTipperGames` and calls `watchGames` with
  the started games it shows: one listener per game (`AllTips/{comp}/{tipper}/{game}`), none at the tipper or
  competition node, listeners opened and closed as the set changes, a game the server refuses to show counted as
  answered with no tip, asking again for the same games a no-op that notifies nobody. 10 tests, six deliberate
  breakages caught. `findTipAcrossCompetitions` was already a per-game read. The competition-wide listener
  (`TipsViewModel` with no tipper) now has one user left, the admin merge (slice 6).
- *The queued-tip message and a late rejection.* The message no longer promises delivery: "it only counts if it
  arrives before kickoff. We will tell you if it does not count." A tip the database has not confirmed within the
  limit is recorded on the device (`UnconfirmedTipsService`, SharedPreferences, forgotten after 14 days). If the
  server later rejects it, the home page shows a "Tip not counted" dialog; if the server confirms it, the record is
  dropped. (That first version settled a tip queued by an app that was then closed from the first tips snapshot of the next
  launch; the real SDK showed that to be wrong, see "Review fixes" below.) A tip replaced by a newer one for the same
  game reports nothing for the older one. Tested at the service (14), the view model (4: remembered, rejected after the limit, confirmed late,
  rejected before the limit) and the home page (3); nine deliberate breakages caught in the service and view model,
  three in the home page. A rejection that arrives in the instant between the limit and the record being written
  would be missed (accepted: the next launch's settle still reports it).

**Review fixes to slice 3 (10 November 2026), and what the real SDK does with a queued tip.** A reviewer found two
queued-tip problems and one in the drill-down. For the first the fake tests could not settle the question, so it was
run against the real iOS Realtime Database SDK (12.19.3, persistence on, a throwaway emulator with a rule that refuses
writes once a flag is set; a scratch app in the session scratchpad, not in the repository): write offline, kill the
process, restart offline, restart online.
- *Offline restart.* Both the listener and `get()` report the queued tip as present, although the server has never seen
  it. A local snapshot is not proof of server acceptance; the first version forgot the tip on exactly that evidence, so
  a later refusal would have gone unreported.
- *Online restart, write refused.* The listener first emits the tip (the replayed write, applied locally), then emits
  "absent" a few milliseconds after the connection comes up, when the refusal reverts it. `get()` behaves the same
  (local view while a listener is active, so it is no server read either).
- *Online restart, write accepted.* Nothing changes. A queued tip and an accepted tip look identical in the data.
- *So:* the data can prove a tip did **not** count, never that it did. `UnconfirmedTipsService.observe` now follows the
  tips listener for the signed-in tipper: a tip shown stays queued (no verdict); a tip replaced by a newer one (later
  submitted time) is forgotten silently; a tip missing is reported only if it stays missing for 3 s **and** the
  connection is up (`.info/connected`), because an accepted tip can vanish for an instant if the database replays and
  refuses a write it had already sent. Offline, nothing is decided. The 3 s is a heuristic, not proof that the
  listener has caught up, so an inferred failure says "We could not confirm your tip for ... please check it on the
  Tips page" under the title "Please check your tips"; "Tip not counted" and "not counted" wording are reserved for an
  actual write rejection (`rejected()`). A drop of the connection, however brief, cancels the wait; it starts again
  after the reconnection (an earlier version let the timer survive a brief drop and fire straight after it). A tip
  missing before its game starts is told to tip again if it is missing (a tip lost with the process on web, which has
  no persistence, is the usual way to get there). Accepted entries are not tidied from the data; they go in 14 days, or when the write itself answers.
- *Overlapping operations.* The service's operations ran load, change, save independently, so two at once could lose
  one another's change. All operations now go through one queue. Tested with a deliberately slow store; removing the
  queue fails three tests.
- *Failed per-game listeners.* A game the server refused stayed in the watched set, so later `watchGames` calls skipped
  it and, if the device's clock was ahead of the server's at kickoff, the game stayed blank until the screen was
  reopened. A failed listener is now cancelled and dropped, the next `watchGames` opens a fresh one, and it is also
  tried again on its own, up to 3 times 5 s apart.
- *Still to do before release (the reviewer asked for it):* run the queued-tip scenario (offline tip, kill, restart,
  game started, refused) in the real app against R2 rules, signed in by hand; the probe above establishes the SDK's
  behaviour, not the app's wiring.

**Slice 6 built (9 November 2026): the admin tipper screens.**
- *Reading.* While the signed-in tipper is an administrator, `TippersViewModel` also listens to `/TipperPrivate` (which
  only administrators may read) and lays each record over the public list (`Tipper.withPrivateRecord`), so the admin
  list, edit and merge screens and the duplicate-email check see each tipper's login, email, role and last login
  exactly as before. Anyone else, and a guest whatever role it carries, never listens; what an administrator read is
  dropped the moment the signed-in tipper is not one. An unreadable private record is skipped, not fatal. 8 tests,
  six deliberate breakages caught (one weak test found and strengthened).
- *Editing.* Name, email and role go through `admin-update-tipper` (one call, only what was edited); the server checks
  a name another tipper has, an invalid email and the last administrator, and the page says so in words from the
  reason (`admin_failure_message.dart`). Paid competitions stay a direct leaf write (R2 allows an administrator that
  one). The identity change is made first and the paid write only if it succeeded; a retry resends the same values,
  which the server treats as no change. A paid change alone makes no call to the server. 20 page tests.
- *Merging.* The merge page asks the server for a dry run when a target is chosen and shows what would happen (tips
  moved, tips that replace the target's for the same game, login and account moving, the source deleted); Merge stays
  off until the preview has arrived, asks to confirm, waits for the answer, and goes back to the list. A merge the
  server could not finish is explained, with "running it again finishes it". The per-competition tip counts of the old
  page are gone (the server reports totals). 6 page tests, seven breakages caught.
- *Deleted.* `TippersViewModel.mergeTippers`, `mergeTipsForComp`, `setTipperEmail`; the competition-wide
  `TipsViewModel` (so a tips view model now always has a tipper), `deleteTip`, `updateTip`, `deleteAllTipsForTipper`;
  `GamesViewModel.updateGameAttribute`, `saveBatchOfGameAttributes` and the batch-write refresh machinery, with the
  four tests that exercised only them. `IdentityService` is now registered once in `main.dart` and shared by the link
  service and the admin pages.
- *Needs mode `coexist`.* Admin edits and merges are identity callables, so under mode `off` they say "Changing
  tippers is switched off at the moment." Until the mode moves, the R2 client cannot edit a tipper's name, email or
  role from the admin screens; paid ticks work.
- *Migrated, and what stays direct.* The identity operations the survey listed (linking, own alias, push tokens,
  account deletion, admin edits and merges) now go through callables; slices 5 and 7 below finished them. Tips, paid
  status, photos and live-score history remain direct client writes, by design: the R2 rules allow exactly those
  (a tip before kickoff, the owner's photo, an administrator's paid ticks, a create-only history entry).

**Slice 8 built (10 November 2026): the client integration harness.**
- *What it is.* `scripts/test-client-integration.sh` compiles `functions_dart/bin/server.dart`, starts a Database
  emulator under the repository's OS boundary (`rules_test/support/isolated.sh`: loopback only, no credentials) with the
  R1-compat rules, starts the compiled server beside it in emulator mode, and runs `flutter test test/integration`.
  The tests use the app's own `IdentityService`, `LinkedTipperResolver`, `DeviceTokenRegistrar`, `AccountDeletion`,
  `aliasFailureMessage`, `adminFailureMessage` and `liveScoreHistoryEntry`. Only what cannot run outside a device is
  stood in for: accounts are unsigned tokens (accepted only because the server is in emulator mode), and database
  reads and writes are the same paths and payloads over the emulator's REST interface, with the user's token in the
  `auth` parameter so the rules apply. Outside the script the tests skip, so `flutter test` is unaffected.
- *What it proves.* 52 tests: sign-in and alias (9), tokens and account deletion (10), admin edit and merge (11), and 22
  on the R2 rules using data the real callables wrote under R1-compat, the state the cutover will find. Eight
  deliberate breakages, five in the real server (unlink leaves the index entry; unlink keeps the private link; a token
  is not taken from its old holder; anyone is an administrator; a role change is not written to the private record),
  one in the rules in force (R2 tests run on R1-compat) and two in the client's live-score entry, were each caught.
- *What it found.* Nothing wrong in the client or the server: every real failure along the way was the harness's own.
  Three of them are worth keeping: the emulator treats an `Authorization: Bearer` header as the administrator's and
  evaluates the rules only for a token in the `auth` parameter (my first version passed every refusal check
  vacuously); the emulator wants the standard claims (`iss`, `aud`, `iat`, `exp`, `auth_time`) in a test token; and a
  new sign-up needs `AppConfig/createLinkedTipper` to be `true`. One server behaviour was confirmed rather than
  assumed: the merge moves tips only in competitions listed under `AllDAUComps`.
- *What it cannot do.* The Firebase Auth, Messaging and Database plugins, Apple and Google sign-in, and the pages.
  Those remain the device checks in section 8.

**Slice 4 built (10 November 2026): live scores.**
- *History only.* `StatsViewModel._writeLiveScoreToDb` writes one create-only entry per submitted score under
  `{game}/history/{micros}-{team}` and nothing else. The `current` snapshot writer (`_liveScoreCurrentPayload`) is
  deleted: under R2 only the server builds `current`, from the history, and it reaches the client through the existing
  live scores listener. Each entry has exactly the four fields the R2 rules allow (`tipperID`, `scoreTeam`,
  `interimScore`, `t`), `t` being `ServerValue.timestamp`, never the device's clock; the client's `submittedTimeUTC`
  and `gameComplete` are no longer written (a contract test reads `config/generated/database.rules.r2.json` and
  compares its allowed fields with the entry's, so the two cannot drift apart). The server's `LiveScoreEntry` already
  reads a numeric `t` in milliseconds. The shared `CrowdSourcedScore.gameComplete` stays, because the server's
  `current` snapshot still carries it (always false) and the client parses that.
- *What the user sees.* The local score still updates at once, as before; other tippers see it when the server's
  aggregator writes `current` (a trigger away, instead of the client's own write). While the aggregator is in `shadow`
  nothing updates `current` for these submissions: the accepted window risk of section 6, which Gates A and B are
  there to keep from mattering. The rules refuse a score for a game that has not started by the server's clock or that
  already has its official score, which a device with its clock ahead will meet at kickoff; the live score dialog now
  says so in words instead of showing the raw error.
- 17 tests (write shape 3, entry and rules contract 4, message 2, and the changed write tests), seven deliberate
  breakages caught.

**Slice 5 built (10 November 2026): push tokens and account deletion.**
- *Tokens.* `FirebaseMessagingService` no longer touches `/AllTippersTokens`: it registers through
  `register-device-token` (the server moves the token from whoever held it, so the client's read of every tipper's
  tokens and `_removeTokenFromOtherTippers` are gone) and removes through `unregister-device-token`. The logic is in
  `DeviceTokenRegistrar`: every call goes through one queue (the server expects a client's register and unregister
  for a token in order), a server that cannot be reached is tried again after 5 s and 30 s (the waits are outside the
  queue, so a removal is not held up behind them), a refusal is final for now, and a registration failure is logged,
  never thrown. A removal of a token voids any registration of that token still waiting to be retried or queued, and a change of the
  signed-in account voids registrations and removals asked for by the earlier account (a per-token counter and an
  account check, so a retry cannot undo a removal and one account's work is not done under another's). A token refresh
  removes the old token only if it had been registered. Signing out removes the token
  best-effort for 10 s and then signs out regardless (`unregisterCurrentTokenIfPossible`): an offline sign-out must not
  hang; the server moves the token to the next tipper who registers on the device, or drops it as stale.
- *Account deletion* is `AccountDeletion` (`lib/services/account_deletion.dart`), no longer in `TippersViewModel`:
  sign in again if the last sign-in is more than 4 minutes old (or unknown), **before** anything is changed, so backing
  out loses nothing; then remove the push token, `unlink-my-account`, and delete the sign-in account last. A failure at
  the token or the unlink stops the deletion with nothing deleted and says why (switched off, busy, unreachable). If the
  provider still wants a fresher sign-in at the last step, the person signs in again and the delete is retried. A
  deletion that fails after the unlink is simply run again: the token step finds `not_linked` and carries on, the
  unlink says `unlinked: false`, the account is deleted (tested as the design asked). `FirebaseDeletableAccount` is the
  thin Firebase Auth adapter. Every failure of signing in again is passed on, Apple's included: the old delete flow
  let five Apple error codes (`user-mismatch`, `invalid-credential` and others) through as success, which would have
  let this flow remove the token and unlink before finding out the sign-in had failed. Only a call that returns
  without an error counts as signing in again.
- *Shared queue.* `SerialQueue` (`lib/services/serial_queue.dart`) is the one-at-a-time runner both this and
  `UnconfirmedTipsService` use.
- *Needs mode `coexist`.* Under mode `off` the callables refuse, so no push token is registered and **deleting an
  account is refused** ("Deleting accounts is switched off at the moment"). That is the design's order (unlinking is
  what lets the person sign up again later), but it means the R2 client cannot ship to users while the mode is `off`.
- *What is not covered by tests.* The Firebase Auth and Messaging adapters (the real reauthentication with Apple and
  Google, the real token) cannot run in the VM. 63 tests cover the logic; 16 deliberate breakages caught. The real
  flow needs a signed-in session: see the pre-release checks in section 8.

**Slice 7 built (10 November 2026): small items.**
- *Own alias.* The Profile alias dialog now calls `update-tipper-alias` (`IdentityService.updateTipperAlias`) instead of
  writing `name` and checking the tipper list itself; the server's alias claim is the only uniqueness check, so the
  client-side duplicate scan and `TippersViewModel.setTipperName` are gone. Failures are explained from the machine
  reason (`alias_failure_message.dart`: taken, not allowed, busy, switched off, not linked, unreachable, signed out).
  Save and Cancel are off while the server is answering, so a second tap cannot send a second call; a refusal leaves
  the dialog open to try again. On success `TippersViewModel.applyOwnAlias` shows the new name at once on the public
  record and on the signed-in copy (which keeps its private fields), as the old direct write did through its local
  echo; the tippers stream confirms it. A first alias for a new tipper is already given at sign-in
  (`createWithAlias`), so the dialog's "create" case is only the legacy empty-name record. 25 tests (dialog 11, message
  8, view model 2, plus the rest of the Profile page's), ten deliberate breakages caught.
- *Update App on web (D13).* The button threw on web (`dart:io` `Platform`). It now reloads the page on web, after
  unregistering any service worker so the reload cannot be answered from an old cached copy, and the notice and
  button say "Reload" with "close the tab and reopen the site" as the fallback; on iOS and Android it opens the
  store, and says so in words if the store cannot be opened (it used to throw). The web code
  (`lib/platform/reload_page_web.dart`) cannot run in the VM tests: it was compiled to JavaScript and run in a browser.
  The page reloaded, and with two stand-in service-worker registrations both were unregistered first. The built-in
  browser pane would not register a real service worker, so that part is shown with stand-ins, not a real worker.
  9 widget tests, six breakages caught.

### 6l. M8 built locally (10 November 2026): admin authorization, the purge, the cutover rehearsal

Local only. Nothing is deployed, and the production cutover is a separate decision.

**Server admin authorization is the validated private role.** An administrator, for the identity callables
(`admin-update-tipper`, `admin-merge-tippers`) and for the older admin endpoints (`admin-fixture-download`,
`admin-scoring-rescore`, `admin-check-fixture-url`), is the tipper whose `/AuthIndex` entry names them and whose
private record names them back and says `admin`: the same test the R2 rules apply, so what the rules let an
administrator do and what the functions let them do cannot come apart. A role changed by `admin-update-tipper`
takes effect at once in both. One implementation (`resolveCallerTipperFrom` in `caller.dart`, used through
`admin_gate.dart`) serves the REST handle of the callables and the other handles of the older endpoints. A failed
read refuses the call; an anonymous caller is refused without a read. The compile-time list is gone from the
functions: `functions_dart/bin/admin_allowlist.g.dart` is deleted, the generator no longer emits it, and
`deploy-functions.sh` no longer checks or records an allowlist (`--record` now takes only `rules`). The list in
`config/admin-auth-uids.json` stays for the R1 family of rulesets (the rollback target) and the offline backfill.
- *Ordering matters at deploy time.* The R1-compat rules still use the list, the functions no longer do, so before
  the functions carrying this change are deployed every allowlisted administrator must already be a validated
  administrator in the data (indexed, record naming them back, role `admin`), or they lose the admin endpoints. That
  is a pre-flight read-only check for the owner's go (cutover pre-flight, section 8).
- Tested: 14 gate unit tests (six deliberate breakages caught), the rewritten server tests (a forged public record
  grants nothing; an ordinary tipper, a record naming someone else, an index entry without a record are refused;
  authorization reads exactly the two identity records; a failed read refuses), a promoted tipper using the admin
  callables at once and losing them when demoted, an administrator whose account is no longer linked refused, and the
  52 integration tests with the administrator now a seeded role.

**The purge (cutover step B) is a previewable tool.** `functions_dart/bin/identity_purge.dart` mirrors the restore tool
(planner in `purge_public.dart`, command line in `purge_cli.dart`, both over the shared `IdentityRecordsStore`, which
the restore tool now uses too).
- *Plan by default.* With no options it reads the two nodes and says what it would do, writing nothing: how many fields
  from how many records, how many later login times it will keep, how many tippers get a placeholder name. Output is
  counts and opaque ids only; the optional `--out` patch holds removals, login times and names, no address.
- *What it removes.* The seven private fields and the two legacy fields from every public record, in one multi-path
  update, once the private record holds them. The private value must equal the public one (an empty public `authuid`
  equals a private record with none; two times are equal if they are the same instant, whatever their text).
- *Newer login times are kept.* A public `acctLoggedOnUTC` later than the private one (a 1.4.x sign-in since the
  backfill) is written into the private record in the same update that removes the public one.
- *Unresolved records block everything.* A public record with identity fields and no private record (a tipper created
  by a 1.4.x client after the backfill: "run the final backfill pass first"), a field that differs between the copies
  (including a creation time or a role), a field only the public record has, or a login time that cannot be read:
  exit 1 naming the opaque id and field, never a value; nothing is written for any tipper.
- *Apply* needs `--project` and `--snapshot <file>`; refuses unless the identity mode is `freeze` or `off`, no request
  is in flight, a second read plans exactly the same patch and the snapshot file does not already exist; saves
  `/AllTippers` as it was to the snapshot (it holds addresses: keep it under `test/data/`) **before** writing; and
  afterwards reads again, which must plan nothing. Run again as the sweep it finds nothing and needs no snapshot.
- Tested: 22 planner tests and 20 tool tests (sixteen deliberate breakages caught, one weak test strengthened), the
  existing rollback rehearsal now using the real purge instead of its hand-written model, and the cutover rehearsal.

**The three identity tools run against a local emulator.** `identity_mode`, `identity_purge` and `identity_restore`
use the emulator named by `FIREBASE_DATABASE_EMULATOR_HOST` when it is set, and otherwise the Firebase CLI to a named
project as before. The variable names a host and port, never a project, so it cannot point a tool at production.

**The cutover rehearsal** (`test/integration/cutover_rehearsal_test.dart`, run by `scripts/test-client-integration.sh`
with the real compiled server and the three compiled tools) tells one story on the emulator: tippers made by the
real callables, plus what 1.4.x clients leave behind (a later public login time, a tipper with no private record, the
two legacy fields, a tipper with no alias). **Step A:** mode `freeze` and drain; the freeze rules refuse an identity
write and a contact change and a refused callable shows the stop is real, while photos continue; the purge refuses
while the unresolved tipper exists and writes nothing; the final-backfill output is stood in for by a direct write;
then R2 rules, mode `coexist`, aggregator `active`. **Verification window:** a linked tipper signs in under R2 with no
server call; **a newly promoted administrator gains** the admin callables, the private records, every tip and the paid
ticks at once, and **the demoted one loses all four**, in the functions and in the rules; tipping before kickoff
works and after it is refused. **Step B:** the purge plans, applies with its snapshot, mode `final`; no address or
identity field is left in the public list, the placeholder name appears, Ann's later login time is in her private
record, the app still signs everyone in (role and identity from the private record), the administrator still
administers, a sign-up in mode `final` leaves only a name in the public record, and the sweep finds nothing and needs
no snapshot. **Rollback:** `freeze`, the restore tool, R1-compat, `coexist`, aggregator `shadow`; every tipper has
the legacy fields back for 1.4.x clients (including the login time carried across the purge), Bob's demotion
survives, the R2 client still signs in and a 1.4.x-style own-record write is allowed again. It takes about three
minutes, mostly the mode tool draining. Deliberate breakages in the purge, the admin gate, the restore and the
rulesets each fail it (see the commit).
- *What it does not do:* the final backfill from a real Auth export, the real functions deployment, the owner's
  attendance and timing, or anything on a device. The production cutover remains a separate decision.

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
the git tag of the pre-cutover functions recorded; rollback scripts present and rehearsed (the rehearsal is
`test/integration/cutover_rehearsal_test.dart`, section 6l). **Administrators, read-only:** every uid in
`config/admin-auth-uids.json` must already be a validated administrator in the data (indexed, record naming them
back, role `admin`) before the functions carrying the role-based gate are deployed, because those functions no longer
consult the list; compare the two by hand or with a one-off read, naming counts and opaque ids only.

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
public contact field afterwards. Take the snapshot (the purge tool's `--snapshot`, required with `--apply`), remove the public PII fields from every record
(give a tipper who has no public field a placeholder name, and delete the legacy `active` and `tipperID`
fields: decisions 8 and 9, section 6d), set mode `final`, run the audit (which now fails on any public contact data) and the post-deploy
verification again. The purge is idempotent and is run once more after a short wait as a sweep. The
snapshot and the restore script stay for at least one season month.

**Cutover checklist: two findings from the R2 client's emulator rounds (9 November 2026).** Both were found on a
copy of production reshaped to the post-purge shape; neither blocks client development, both must be reconciled
before the real purge (Step B). **The purge tool now enforces both** (`bin/identity_purge.dart`, section 6l): finding 1
is handled by the tool itself, finding 2 makes it refuse.
1. **A newer public `acctLoggedOnUTC`.** A 1.4.x client's sign-in refreshes the public login time, so the public copy
   can be ahead of the private one (two tippers on the copy). The purge must first copy the newer value into
   `TipperPrivate`, never drop it ("a present public field wins", as the merge already rules).
2. **A public record with no private record** (the "unaudited" case of section 6f decision 2): a 1.4.x client created
   a tipper after the identity backfill (one on the copy, holding every private field in its public record). A final
   backfill pass (which needs a fresh Auth export) must audit it and build its private record and index entries before
   the purge; until then the purge must leave it alone, as the emulator script did.

**Pre-release checks (10 November 2026; asked for by the reviewer).** The wiring is now checked by
`scripts/test-client-integration.sh` (section 6k, "Slice 8 built"), which runs the app's own client classes against
the real Dart callable server and the real rulesets, before and after the cutover to R2. That leaves only what needs
a device or a signed-in session, and these are the owner's manual checks. None needs production; none should enable
`coexist` in production just to test the screens.
- *Covered by the harness (do not repeat by hand):* sign-up and sign-in, alias changes and refusals, push-token
  registration and moving, the full deletion order (token, unlink, then the account) including a deletion that fails
  after the unlink and is run again, and signing up again linking back to the same record; admin edit, the refusals
  (taken alias, invalid email, last administrator, not an administrator) and merge with its dry run; and under the R2
  rules a tip before and after kickoff (the rejection a queued tip meets), another tipper's tips game by game and never
  at the tipper or competition node, the live-score entry and what it may not contain, photo and paid ticks, and that
  unlinking ends access.
- *One short app-level smoke test against the emulators (the harness substitutes REST adapters for the Firebase
  plugins and does not drive the pages):* sign in, edit your alias, edit a tipper as an administrator, merge two
  tippers. There is no need to repeat the 52 cases by hand.
- *Queued tip, on a device or simulator against the emulators with the R2 rules loaded, signed in by hand:* tip with
  the connection down, kill the app, let the game start, restart (offline first, then online). The tip must stay
  unreported while offline and be reported once online. The SDK's behaviour is established (section 6k, "Review fixes
  to slice 3") and the rules' refusal is covered above; this checks the app's wiring of them.
- *Apple and Google sign-in again, and a real push token, on a device:* delete an account with a fresh sign-in, with an
  old one (the sign-in-again prompt, and cancelling it, which must leave the tipper linked), and with the connection
  cut after the unlink and then retried; confirm the real token is removed and a second tipper signing in on the same
  device takes it.
- *Account deletion refused under mode `off`:* the message appears and nothing is deleted (covered by the harness; worth
  one look on a device for the wording).
- *Production settings to confirm before an R2 client ships:* `AppConfig/createLinkedTipper` is `true` (without it a
  new sign-up is answered `creation_disabled`) and the identity mode is `coexist`. The live-score aggregator is **not**
  a prerequisite: it stays in `shadow` until cutover step A sets `active` (section 8), as the schedule has it. While
  mixed clients are in the field that leaves interim scores from R2-client users unpublished, which is harmless
  while no game is on (the client ships in late January and K is early March, section 7). If a game could be on
  before the cutover, or Gate B fails, the owner enables `compat` instead (section 3). That is an explicit owner
  decision, taken then; it is not something to switch on in advance.

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
8. **A tipper with no public field gets a placeholder name at the purge** (21 October 2026). One tipper
   signed up in 2025 without an alias, because of a bug that year. Without a name the purge would leave
   an empty node and the tipper would vanish. Section 6d.
9. **The legacy `active` and `tipperID` fields are deleted in the purge** (21 October 2026). Nothing
   reads them. Section 6d.
10. **Unresolved operations are handled by hand, and the hardening scope is frozen** (6 November 2026). The proposed
    flag, block and scheduled reconcile are not built. A rare operation with an unknown outcome is found in the log
    and the drain tool's list, and the owner repairs the tipper manually, accepting a brief disruption to that
    tipper's profile changes. Accepted limitations and what blocks a release are in the scope reset in section 6f.
