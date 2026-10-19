# DESIGN: Realtime Database Security Rules

Status: **DRAFT v6. Phase 1 (inventory and spike) is complete, re-checked against the end-of-2026
export, and reviewed a third time. Findings are in
[DESIGN-database-rules-phase1.md](DESIGN-database-rules-phase1.md) and are folded in below. No app,
backend or rules behaviour has changed. Production web was updated to 1.4.0+712 on 2026-10-05
(the only production change).**

## 1. Problem

[database.rules.json](database.rules.json) is `.read: true` / `.write: true` at the root.
Anyone who knows the database URL can read or overwrite everything, including other tippers'
picks before kickoff. App Check is currently the only barrier. Goal: default-deny rules that
enforce who can read and write what, validated by automated tests, rolled out without
locking out live users.

**An exposure exists today, independent of this work:** the Dart admin endpoints decide who
is an admin by scanning `/AllTippers` for a matching `authuid`
(`resolveTipperRoleForAuthUid`, `functions_dart/bin/server.dart:1838`). Because the database
is publicly writable, anyone can write their uid onto an admin record and call those
endpoints. Closing this is the first rollout step (section 5).

## 2. Facts established from the code

- Cloud Functions use the **Admin SDK (service account) and bypass rules**. The Dart
  functions use the Admin SDK or an authenticated REST client with the runtime service
  account (`_openBackendScoringDatabase`); only the emulator path uses
  `authenticate('owner')`. The Dart REST handle already implements ETag/`if-match`
  `runTransaction` (`server.dart:1326`; **inspected, not run**: the spikes exercise
  `firebase_dart`'s `runTransaction`, not this REST code, and which handle the deployed callables
  would use is a phase 2 decision to prove). Scoring, badges and reminders are unaffected by
  rules. This must be verified end-to-end after deploy because the emulator cannot prove
  production bypass.
- Tippers are keyed by **push ID** at `/AllTippers/{tipperId}`. Rules cannot query.
- **Identity linking today is by email string match, not by uid.** `_findExistingTipper`
  tries `authuid`, then `logon`, then `email` (exact, case-sensitive).
  `_updateExistingTipper` writes `logon`, `email` (if invalid), `isAnonymous`, `photoURL`
  and timestamps but **not `authuid`**. `authuid` is written only on record creation
  (`tippers_viewmodel.dart:658`) and by `mergeTippers` (`:763`). **Measured on the end-of-2026
  export (211 tippers, 80 of them active in 2026): every record has an `authuid`, but 40 (19%)
  hold a sheet-era placeholder that is an email address, not a Firebase UID.** Only 2 of those
  40 are active in 2026 (776 tips). All 34 records created in 2026 have real UIDs. **4 values are
  shared by two records** (3 placeholders; 1 real UID where one record has 12 tips and a login
  and the other has neither). "Empty `authuid`" therefore does **not** mean unclaimed.
- New users **create their own record** (including `authuid` and `tipperRole`), gated by the
  client-read `AppConfig/createLinkedTipper` flag. Alias uniqueness is checked client-side
  only, and again on name edit (`updateTipperName`), both bypassable.
- **Anonymous users are local-only**: no tipper record is persisted, so no `tipperId`.
- **Listeners start before sign-in.** Once config loads, a post-frame warm-up
  (`main.dart:476-492`) constructs `TeamsViewModel`, `TippersViewModel` and `DAUCompsViewModel`,
  whose constructors attach listeners on `/Teams`, `/AllTippers` and `/AllDAUComps` (and the
  Teams/Tippers listeners have no `onError`). RTDB cancels a listener denied by rules and does
  **not** re-attach it after a later sign-in.
- **Device tokens use cross-tipper access.** `FirebaseMessagingService` reads the whole
  `/AllTippersTokens` (`_removeTokenFromOtherTippers`) and deletes other tippers' tokens. (A client
  `deleteStaleTokens` also did, but it had no callers and has been removed; stale tokens are cleaned
  up by the backend, see D9.)
- **Firestore is a second surface.** The client writes `tipLogs2` (an audit log of every tip,
  `gametip_viewmodel.dart:431`). The repo has no `firestore.rules` and `firebase.json` has no
  Firestore rules entry, so its rules live only in the console and are unverified.
- `mergeTippers` moves tips, copies `logon` and `authuid` onto the target, deletes the
  original. It runs as an admin from the client.
- Admin = `tipperRole == 'admin'` on the tipper record. Admin "god mode" writes tips as
  another tipper.
- **`ConfigViewModel` listens to the whole `/AppConfig` node** (`config_viewmodel.dart:84`,
  `:136`), is created at app start (`main.dart:284`), and startup waits for it before
  showing sign-in (`main.dart:557`). `AppConfig` is read **before authentication**.
- **The in-app update button does not work on web**: `UpdateAppLink` uses `dart:io`'s
  `Platform.isIOS`, which throws on web, and returns no URL for non-mobile platforms. A blocked
  web user has no working in-app recovery.
- The version gate compares **`packageInfo.version` dotted parts** against
  `AppConfig/minAppVersion` (`user_auth.dart:76`), not the build number. Current version is
  `1.4.1+713`.
- Tips: new writes are `AllTips/{comp}/{tipperId}/{gameKey}` = `{r, t}` (`t` epoch seconds,
  client-supplied). **Live data is a mix**: the 2026 comp has 22,982 compact tips and 43 legacy-
  shaped ones; the 2023 to 2025 comps (86,000+ tips) are all legacy
  `{gameResult, submittedTimeUTC (ISO string)[, legacyTip]}`. `Tip.fromJson` accepts both and
  `updateTip` merges compact fields into legacy nodes.
- **Tip readers today:** main UI (`TipsViewModel.forTipper`, listener at tipper node),
  `findTipAcrossCompetitions` (per-game get), leaderboard drill-down
  (`user_home_stats_roundgamescoresfortipper.dart`: another tipper's tips, started games only,
  tipper-level listener), admin merge (`mergeTipsForComp`: unscoped listener at
  `AllTips/{comp}`, the only comp-wide listener). `StatsViewModel` does not read tips.
- `Game.DateUtc` is a **string** (`yyyy-MM-dd HH:mm:ssZ`). Rules cannot parse dates. All 2,121
  games in the 2026 export match that format, so the numeric backfill is deterministic.
- Live scores: the client writes `Stats/{comp}/live_scores_backend_v1/{game}/current` (a
  **client-computed aggregate** that triggers `liveScoreWrittenBackendScoring`) and
  `.../history/{ts}-{team}` entries. `tipperID` and `submittedTimeUTC` are client-supplied. The
  Dart backend parses the `current` snapshot (`homeInterimScore`, `awayInterimScore`,
  `submittedTimeUTC` ISO string, `tipperID`, `crowdSourcedScores`), so the aggregator must keep
  that shape. `gameComplete` is parsed into `CrowdSourcedScore` but **not used in any scoring
  decision**; only the TypeScript trigger gate compares it.
- **Released clients still write legacy Stats branches.** HEAD (1.4.x) does not (the writers
  were retired on 2026-07-29, commit `0970b86`), but 1.3.10 to 1.3.11 (the current
  `minAppVersion` is `1.3.11`) write `game_stats_v3`, `live_scores_v3` (set and delete),
  `scoring_audit_v3` and an `admin_scoring_freshness_probe`, **as ordinary tippers**: 58 distinct
  tippers (53 non-admins; iOS, Android and web) wrote 7,612 audit entries between 2026-05-28 and
  2026-08-14. A rule set validated only against HEAD would have broken them. The **1.4.0 floor (section 5 step A)
  excludes all of them**, and R1 still rejects their writes in case a session or modified client
  persists.
- Alias normalisation (`_normaliseAlias`): strip non-letter/non-digit/non-space, remove
  whitespace, lower-case (Unicode aware).
- Client write inventory (re-verify in phase 1):

| Path | Writer today |
|---|---|
| `AppConfig/*` | admin (and **public read before sign-in**) |
| `AllDAUComps/*` (incl. `downloadLock`), `Teams`, `DAUCompsGames` | admin |
| `AllTippers/*` | admin; users create/update own record |
| `AllTippersTokens/{tipperId}/*` | owner |
| `AllTips/{comp}/{tipperId}/{game}` | owner; admin (god mode, merge) |
| `Stats/{comp}/live_scores_backend_v1` (HEAD) | any tipper |
| `Stats/{comp}/{game_stats_v3,live_scores_v3,round_stats_v3,scoring_audit_v3,admin_scoring_freshness_probe}` (1.3.x) | any tipper |
| `Diagnostics/*`, `AppConfig/resumeProbe` | diagnostic probe |

## 3. Decisions (resolved)

| # | Decision |
|---|---|
| 1 | Server-owned UID mapping with rule-side lookup (no custom claims), with a **bidirectional** UID check. |
| 2 | **Split public and private tipper data in this release** (D6). |
| 3 | `/AppConfig` stays public-read. The live node was inspected (end-of-2026 export): 10 keys, no secrets, so nothing needs to move. |
| 4 | **Two version floors.** **R1 floor `1.4.0`** (public in both stores and, since 2026-10-05, on web): a *compatibility* floor, raised now while no comp is running. It removes the 1.3.x clients (legacy Stats writers) but is **not** the security release; 1.4.0 lacks callable linking, private profiles, authentication-aware startup, history-only live scores and token callables. **R2 floor: the later release (`1.4.n+1`, a patch bump suffices because the gate compares dotted parts positionally) containing all security-related client changes.** About one week after availability in both production stores for R2, with an announcement that includes web reload guidance. TestFlight alone is insufficient. **Raising `minAppVersion` neither disconnects running sessions nor stops modified clients, so the rules must reject obsolete writes regardless of the gate.** |
| 5 | Live-score aggregation moves to the backend now (D7). |
| 6 | Numeric kickoff `DateUtcEpochMs` (UTC epoch ms), written atomically with `DateUtc`, mandatory, fail closed. No scheduled "started" flag. |
| 7 | **Callables live in `functions_dart/` (Dart).** One shared authorization policy: the existing Dart admin endpoints migrate to it. |
| 8 | **R1 admin allowlist (D12)**: a temporary, independently verified list of admin Firebase Auth UIDs, applied to **both** the R1 rules and the existing Dart admin endpoints, retired when the bidirectional `AuthIndex` check is authoritative. |

## 4. Design

### D1. Authoritative identity
Identity data is written **only by server code**. Server-owned structures (no client write
access in the final rules):

- `authuid` and `tipperRole` on the tipper record (private part, see D6).
- `/AuthIndex/{uid} -> tipperId`
- `/AliasIndex/{normalisedAlias} -> tipperId`
- `/LogonIndex/{normalisedEmail} -> tipperId`
- `/IdentityLocks/{tipperId}` and `/IdentityOps/{opId}` (merge leases and journal)

**Bidirectional check, in rules and in every callable:** the caller's tipper is
`tipperId = AuthIndex[auth.uid]`, valid only if the record exists **and its `authuid`
equals `auth.uid`**. A missing record, mismatching `authuid` or missing index entry grants
nothing. Partial or tampered state therefore fails closed. Admin = the validated tipper's
`tipperRole === 'admin'`. Rules use `root.child(...)` lookups (a rule error evaluates to
deny; test it explicitly).

One shared Dart implementation (`resolveCallerTipper(uid)`) is used by `linkOrCreateTipper`,
all admin callables and the existing admin endpoints. **The `authuid` role scan is deleted**
(replaced first by the R1 allowlist, D12, then by this check in R2).
`docs/admin_authorization.md` (which describes a stale `/AllTippers/{uid}` lookup) is
updated.

### D2. Server-owned create / link / rename callables (Dart)
App Check-enforced callables, awaited by the client before it starts protected listeners:

- `linkOrCreateTipper`
  1. Reject anonymous. Require the token's `email_verified === true`. Normalise the email.
  2. If `AuthIndex[uid]` exists: **validate** it (record exists, `authuid == uid`). If valid,
     return it. If invalid, fail and flag for repair; never return a stale mapping.
  3. Find candidate records by `LogonIndex`/`logon`, then `email`. **"Claimed" means the record's
     `authuid` is a real Firebase uid that exists in Firebase Auth** (verified with Auth, not by
     string shape). A record is replaceable only if its `authuid` is null, already this uid, or
     **exactly equals the placeholder recorded for that record in the rollout audit
     (`/Placeholders/{tipperId}`, step 0)**; the replacement is a conditional compare-and-set on
     that exact string (D3), never a blind overwrite. A candidate claimed by another uid is
     **rejected (no takeover)**. Several candidates are **rejected as ambiguous**. None: create if
     `AppConfig/createLinkedTipper` is true (read server-side); role is always `tipper`.
  4. Writes follow the claim protocol in D3.
- `updateTipperAlias`: owner-only, server-side alias uniqueness via `AliasIndex`. The
  client can no longer write `name` directly, which closes the alias-uniqueness bypass.
- Move `normaliseAlias` into `dau_shared` so both runtimes use one implementation. Cap alias
  length at 64 characters.
- **Index keys must be valid RTDB keys** (no `.`, `$`, `#`, `[`, `]`, `/`). `AliasIndex` keys are
  the normalised alias (Unicode letters and digits only, so already valid). **`LogonIndex` keys
  are `base64url(SHA-256(normalisedEmail))`**, where `normalisedEmail` is trim plus lower-case;
  raw emails cannot be keys because they contain `.`, and hashing also keeps addresses out of
  keys and logs.

### D3. Concurrency design (no root transactions)
`/AllTippers`, `/AuthIndex` and `/AllTips` share only the database root, so a transaction
spanning them would lock the whole tree. Instead:

- **Primitives:** single-location compare-and-set (transaction at one path):
  `claim(path, value)` (null to value, idempotent for the same value), `release(path, value)`
  (owner-only), and **`replaceIf(path, exactExpected, value)`** for the audited-placeholder case,
  which succeeds only if the current value is null, already `value`, or exactly the audited
  placeholder. **Proven in phase 1** with `firebase_dart`'s `runTransaction` against the emulator
  (`rules_test/dart_spike`). The project's separate REST ETag implementation is inspected, not
  run; phase 2 picks the production handle for the deployed callables and re-runs these tests
  against it (a deployed check, since the emulator uses a different path).
- **Ordered, idempotent steps with fail-closed partial states** (the bidirectional check in D1
  means a half-finished operation grants no access):
  - *Link:* `replaceIf` the record's `authuid` (null, same uid, or the exact audited
    placeholder) then claim `AuthIndex[uid]`; if the uid is already mapped elsewhere, restore
    the previous `authuid` (compensation). A different uid cannot take over a half-linked record
    (its `authuid` is no longer null or the placeholder), and the same uid's retry completes it.
  - *Create:* a durable **intent** `CreateIntents/{uid} = "{tipperId}|{createdAtMs}"` is claimed
    first so a retry reuses the same `tipperId`; then claim `AliasIndex`, claim `LogonIndex`,
    write the record (only if absent or already this uid's), and finally claim `AuthIndex[uid]`
    as the commit; then release the intent. A conflict rolls back everything claimed so far.
    A concurrent double-tap by one uid creates exactly one record.
  - *Rename:* claim the new alias, write `name`, release the old alias.
  - **Abandoned creates:** an intent older than its TTL whose record never reached the index is
    reaped (claims released, orphan record removed, intent deleted), freeing the alias.
- **Leases** (merge/reassign/delete): `IdentityLocks/{tipperId} = "{owner}|{expiresAtMs}"`. A
  live lease is refused to other owners; the same owner may renew; an **expired lease is taken
  over by compare-and-set on the exact stale value**, so only one of several contenders wins.
- **Merge / reassign / delete** (admin callables) take leases on every involved record, record
  steps in `IdentityOps/{opId}`, and run **idempotent, resumable** steps (move tips, transfer
  `AuthIndex`, update `authuid`, delete source, release claims). **Target already owned by a
  different uid:** reject by default. An explicit `replaceUid` option removes the previous
  `AuthIndex` mapping for that uid (they lose access) and is audit-logged. During a merge, tip
  writes to the source are not blocked; this is an accepted risk (rare, admin-driven, verified
  after).
- **Audit job (scheduled):** every `AuthIndex` entry points at a record whose `authuid` equals
  the uid; every record with a real-uid `authuid` has the matching entry; every alias/logon
  claim points at an existing record; no stale intents or leases remain. It reports violations
  and runs the reaper.
- **Proven in phase 1** (52 checks, plus a mutation check that a loosened placeholder rule is
  caught): exact-placeholder replacement and refusal of any other value; a real uid is never
  replaced; one winner among racing uids; compensation restores the placeholder; crash injection
  after **every** step of link and create followed by a retry restores a clean audit; partial
  states are flagged and cannot be taken over; abandoned creates are detected and reaped; lease
  takeover has one winner; same-alias and same-email conflicts roll back cleanly.

### D4. Tipper record protection (fine-grained writes, no blanket grant)
No client `.write` is granted at `AllTippers`, `AllTippers/$tipperId`, `TipperPrivate` or the
identity indexes. Grants are on **leaf fields only**, so a parent replacement or delete
(including of `authuid`) is denied by default.

| Field | Client write |
|---|---|
| `authuid`, `tipperRole`, indexes, `name` | none (server/callable only) |
| `photoURL`, `acctLoggedOnUTC`, `acctCreatedUTC` | owner (validated) |
| `logon`, `email`, `compsParticipatedIn`, `isAnonymous` | admin only |

Creating and deleting tipper records is callable-only (`adminCreateTipper`, merge/delete).
The admin client edit flow must write field paths, not whole records (phase 1 inventory
confirms how `toJson()` is used). Reminder: `.validate` is not evaluated on deletes, so
protection against deletion comes from the absence of `.write` grants, not `.validate`.
Phase 1 confirmed (a) a parent `.write` grant cascades and a child `.write: false` cannot
revoke it, (b) a child `.validate` blocks changes but not deletes, and (c) a parent
`.validate(hasChildren([...]))` **does** block direct deletion of a required child and
replacement of the record without it. As defence in depth, the tipper records also carry
required-children validation, in addition to the leaf-only write grants.

### D5. Pre-kickoff tip secrecy and kickoff lock
`DateUtcEpochMs` (UTC epoch ms) is mandatory on every game and written **in the same
multi-path update** as `DateUtc` by every writer (client admin fixture flow, shared
`fixture_import_applier`, functions) via one shared serializer. Existing data is backfilled
and verified complete before rules deploy. Rules **fail closed**: a missing or non-numeric
kickoff denies owner writes and non-owner reads.

```
AllTips/$comp
  .read:  admin
  $tipperId
    .read:  owner || admin                    // own listener at this level
    .write: admin                             // parent delete, merge, god mode
    $game
      .read:  owner || admin || now >= kickoff
      .write: (owner && now < kickoff) || admin
      .validate: (compact: r in GameResult names and t a number <= now/1000 + skew)
                 || (legacy: gameResult and submittedTimeUTC present); unknown legacy
                 keys (legacyTip) tolerated, since existing nodes can be mixed
```
`.validate` does not cover deletes, so the owner delete lock is in `.write`. Non-owners
cannot listen at the tipper node. The drill-down screen changes to **per-game `onValue`
listeners** (a handful of started games), which preserves reactive updates (god mode and
merges can still change started tips). Admin merge keeps working through the admin read at
`AllTips/{comp}`. Default tips are written by the backend and are unaffected.

### D6. Public / private tipper data (this release)
- Public `/AllTippers/{tipperId}`: `name`, `photoURL`, `compsParticipatedIn` (needed for
  leaderboards). Readable by any signed-in user (anonymous read is still permitted for
  browsing).
- Private `/TipperPrivate/{tipperId}`: `email`, `logon`, `authuid`, `tipperRole`,
  `isAnonymous`, `acctCreatedUTC`, `acctLoggedOnUTC`. Readable by the owner and admins only.
- The `Tipper` model in `dau_shared` is built from public data plus optional private data.
  Other tippers' private fields are null on the client. Admin tipper screens read the private
  collection. The reminders function and Dart helpers are updated for the new shape.
- Migration is additive first (copy to `TipperPrivate`), then **public PII fields are purged
  after the R2 floor is enforced and before the final rules deploy** (RTDB cannot hide
  children of a readable parent).

### D7. Live scores (backend aggregation)
- Clients write **only** `history` entries. `current` becomes server-write-only.
- Entry shape: `{tipperID, scoreTeam, interimScore}` plus `t`. Clients no longer submit a
  `gameComplete` flag. Rules:
  write allowed for a non-anonymous tipper (via D1) while the game has started and is not
  complete; `tipperID` must equal the caller's `tipperId`; `t === now` (**trusted server
  submission time**, resolved by RTDB server timestamp); scores are integers within bounds;
  entries are **append-only** (`!data.exists()`); deletes are admin-only.
- A backend trigger (`onCreate` of a history entry) recomputes `current` as a **pure
  function of the full history**, with idempotency via the existing
  `scoring_idempotency_backend_v1` mechanism. Ordering by `t`, then key. Current client
  behaviour (latest valid submission per team wins) is preserved for scores.
- **Concurrency: version-guarded writes.** Two invocations can read different snapshots and
  finish in reverse order, so a deterministic function alone can leave `current` stale. Each
  computation records `basedOnCount` (the number of history entries it included; monotonic
  because history is append-only) and is written with a **transaction at `current` that applies
  only if `basedOnCount` exceeds the stored value**. The invocation triggered by the last entry
  reads a snapshot containing all earlier entries, so the highest version wins whatever the
  completion order. **Proven in phase 1:** an older computation finishing last is refused, and 30
  computations completing in random order leave the latest. The extra `basedOnCount` field is
  ignored by the Dart and TypeScript consumers of `current`, which read only the fields listed
  in section 2.
- **Only an official fixture score completes a game** (owner decision). The aggregator never
  sets `current.gameComplete` to true; it stays false for crowd-derived data, and completion
  flows through the existing official-score path (`handleOfficialScoreWrittenBackendScoringWrite`).
  `CrowdSourcedScore.gameComplete` and the `gameComplete` field in the `current` payload
  (`stats_viewmodel.dart:1200`) are removed. Phase 1 checks how
  `backend_scoring.ts` treats `gameComplete` in live-score material so that removing it
  changes no scoring behaviour.
- Per-tipper limit: the aggregator counts only each tipper's latest entry per team and
  ignores bursts beyond a rate cap.
- Review what `handleLiveScoreWrittenBackendScoringWrite` already validates in phase 1.

### D8. Other areas
- Default deny at the root. Keep `.indexOn` (`AllTippers`: `authuid`, `email`, `logon`,
  moved to `TipperPrivate` if still queried; `DAUCompsGames/$comp`: `DateUtc`). Re-check
  which indexes are still used.
- `AppConfig`: public read, admin write. The end-of-2026 export holds 10 keys:
  `createLinkedTipper`, `currentDAUComp`, `googleClientId` (a public OAuth client id),
  `minAppVersion` (`1.3.11`), three Cloud Run function URLs (public hostnames, already shipped
  to every client, and App Check protected), `outstandingTipsPushEnabled` (read by the app-badge
  function), `resumeProbe` (a short diagnostic nonce) and `useBackendScoringBranches`
  (referenced nowhere in the current code; candidate for removal). **No secrets.** (Public read
  of the whole node is required because the client listens at the parent before sign-in.)
- `AllDAUComps`, `Teams`, `DAUCompsGames`: read `auth != null`, write admin.
- `AllTippersTokens`: **no client access** (D9).
- Remaining `Stats`: read `auth != null`, write server only. `Diagnostics`: admin only or removed.
- Anonymous users: read-only parity with today; no record, no tip writes.

### D9. Device tokens move server-side
The client currently reads all tippers' tokens and removes a token from other tippers
(`_removeTokenFromOtherTippers`; the client's `deleteStaleTokens` was dead code and is removed).
Under owner-only rules that would fail,
and they are cross-user operations the client should not perform. New callables
`registerDeviceToken` and `unregisterDeviceToken` (Dart) move a token to the caller's tipper
and remove it from any other tipper in one server step. Stale-token cleanup becomes a scheduled
server job (the reminders function already prunes invalid tokens). Rules grant clients **no**
access to `/AllTippersTokens`.

### D10. Client startup must be authentication-aware
Listeners attached before sign-in are cancelled by an auth-required rule and are not
re-attached (section 2). The new client therefore:
- starts the Teams, Tippers and DAUComps view models (and every protected listener) **only
  after** a Firebase user exists and `linkOrCreateTipper` has returned;
- gives every listener an `onError` that records the failure and re-subscribes when the auth
  state changes;
- tears listeners down on sign-out.
Only `AppConfig` (and `.info/connected`) may be read before sign-in.

### D11. Firestore `tipLogs2` (adjacent surface; blocks the secrecy claim)
`tipLogs2` holds **actual picks and tipper identities** (`tipResult`, `tipperId`, `tipperName`,
`submittedBy`). If clients can read it, securing `/AllTips` does not deliver pre-kickoff
secrecy, so **the owner inspects the production Firestore rules now** (Firebase console, Firestore
Database, Rules; the repo has no `firestore.rules`, the CLI cannot print deployed rules, and it
was not probed from here). Until that is closed, pre-kickoff secrecy is **not** claimed.
Target state: a version-controlled `firestore.rules` (with the `firestore` entry in
`firebase.json`) allowing authenticated **create-only** with field validation and **no client
read, update or delete**, or move the write to a callable. Included in this release.

### D12. R1 admin allowlist (temporary)
Until `AuthIndex` is authoritative, an admin cannot be derived safely from the database, and the
current Dart admin endpoints trust `authuid` plus `tipperRole` in publicly writable data. R1
therefore uses an explicit allowlist of **independently verified Firebase Auth UIDs**:
- **Source of truth:** `config/admin-auth-uids.json`, changed only through the repo and deployed
  server-side; clients cannot modify it. The database `authuid` is never the source. Each UID
  is verified with `scripts/verify_admin_auth_uids.mjs` (read-only: exists in Auth, email
  matches and is verified, not shared) and signed off by the owner before it is added.
- **Consumed in both places, kept in sync by a build step and a test:** (a) `database.rules.json`
  generated from a template (`auth.uid === '...' || ...`), and (b) the existing Dart admin
  endpoints (`adminFixtureDownload`, `adminScoringRescore`, `adminCheckFixtureUrl`), where the
  `resolveTipperRoleForAuthUid` scan is replaced by the allowlist check. An allowlist used only
  in rules would leave the backend's old authorization in place.
- **Grants in R1:** admin-only areas (`AppConfig`, `AllDAUComps`, `Teams`, `DAUCompsGames`),
  all `AllTippers` writes by admins (role, paid, merge, delete: so the earlier "admin edits
  unavailable in R1" limitation disappears), and god-mode tip writes.
- **Retired in R2:** both consumers move to the bidirectional `AuthIndex` check (D1) and the
  list is deleted. A test asserts the allowlist path is gone.
- Changing an admin account before R2 means editing the JSON and redeploying rules and
  functions (rare).
- **The verification proves consistency, not entitlement:** a matching verified email shows the
  Auth account and the record agree, not that the person should be an administrator. The
  owner's confirmation of each UID is essential.
- **Contact fields are untrusted until R2.** R1 lets any non-anonymous user write `email` and
  `logon` (a compatibility concession), so an audit can go stale immediately. The identity
  migration therefore applies only a **reviewed mapping** derived from Firebase Auth, re-runs
  the audit immediately before applying, and aborts for any record whose contact fields or
  `authuid` no longer match the audited snapshot (phase 3 report, section 7).

### D13. Update recovery, especially on web
A blocked user needs a working recovery path. Installed clients show a fixed message and, on
iOS and Android, an Update App button; on web the button throws. Therefore:
- the next client fixes `UpdateAppLink`: no `dart:io` `Platform` on web, and on web it reloads
  the page (and clears a stale service worker if present) instead of opening a store;
- every cutoff announcement **includes reload guidance for web users** ("refresh the page; if you
  still see the notice, close the tab and reopen the site") and store-update guidance for mobile;
- this is an operational requirement for each floor (R1 now, R2 later), not an off-season nicety.

## 5. Rollout and compatibility

There are **two version floors** and two rule sets. Identity protection comes first, before any
callable trusts data. The version gate is UX guidance; **the rules must reject obsolete and
modified-client writes whatever the gate says**, because raising `minAppVersion` does not
disconnect running sessions.

**A. Raise `minAppVersion` to `1.4.0` now (the R1 floor).** 1.4.0 is public in both stores and,
since 2026-10-05, on web, and no comp is running. 1.4.0 and 1.4.1 write exactly the same RTDB
paths. This excludes every 1.3.x client (the legacy Stats writers). It is a compatibility
floor only. Announce it lightly, with web reload guidance (D13).

0. **Read-only identity audit** against Firebase Auth (not the DB `authuid`): placeholder
   `authuid` values (record each exact string in `/Placeholders/{tipperId}`), duplicates, an
   `authuid` that does not match the Auth user for the record's email, multiple records per
   email, alias collisions, and the admin list (run `scripts/verify_admin_auth_uids.mjs`). Fix
   by hand. The 2026 export suggests this is small: 2 active placeholder users, 1 real-UID
   duplicate pair, 3 `logon` and 4 alias collision groups.
1. **R1: interim rules (deploy first; closes today's exposure).** Deployed together with the
   Dart admin endpoint change (D12), because rules alone leave the backend's role scan in place.
   Baseline: clients 1.4.0 and 1.4.1 only.
   - Remove root `.write: true`; default deny. **All client writes require a non-anonymous
     sign-in.**
   - **Admin-only** (allowlisted UIDs, D12): `AppConfig`, `AllDAUComps`, `Teams`,
     `DAUCompsGames`, and every `AllTippers` write that touches `authuid`, `tipperRole`,
     `compsParticipatedIn`, or creates/deletes a record other than a user's own new record.
   - **Unchanged from today (any non-anonymous signed-in user)**: creating one's own record
     (`tipperRole == 'tipper'`, `authuid == auth.uid`, no paid comps, no unknown keys), own-profile
     leaf fields (`name`, `logon`, `email`, `isAnonymous`, `photoURL`, `acctCreatedUTC`,
     `acctLoggedOnUTC`), single tips under `AllTips/{comp}/{tipper}/{game}` (shape validated:
     compact `{r,t}` with `r` in `a` to `e` or `z`, or the legacy shape), tokens at **leaf**
     level only (no parent wipe), and `Stats/{comp}/live_scores_backend_v1` at the
     `{game}/current` and `{game}/history/{key}` leaves.
     The owner check cannot be applied yet without breaking login for the 40 placeholder
     records, and the kickoff lock needs the numeric kickoff; both arrive in R2.
   - **Legacy writes are rejected.** `game_stats_v3`, `live_scores_v3`, `round_stats_v3`,
     `scoring_audit_v3`, `admin_scoring_freshness_probe` and every other `Stats` path are not
     client-writable. A running or modified 1.3.x client's writes fail (tested).
   - **Reads stay open, as today, except `AllTippersTokens` (any signed-in user; the client only
     reads it after sign-in; the dead client `deleteStaleTokens` has been removed) and unknown paths (closed).**
     1.4.x attaches `/Teams`, `/AllTippers`, `/AllDAUComps` (and the games listener) before
     sign-in, so an auth-required read there would cancel them. Per-path `.read` grants replace
     the old root `.read: true`, so a new top-level node is closed by default.
   - Validate with the conformance replay against 1.4.0 and 1.4.1, plus a suite that proves
     the rejected writes above fail.
2. **Additive server pieces** (Dart functions, deployed deliberately with
   `scripts/deploy-functions.sh --only dart`): `DateUtcEpochMs` writers and backfill,
   `TipperPrivate` copy, `AuthIndex`/`AliasIndex`/`LogonIndex` backfill (resolve each record to a
   uid via the Firebase Auth user for its verified email, using a one-off Node Admin script;
   replace only audited placeholders; flag every disagreement), the callables, token callables,
   and the live-score aggregator running **alongside** the client-written `current`.
3. **Release the R2 client (`1.4.n+1`)** on App Store, Play and web: callable linking,
   authentication-aware startup (D10), public/private tipper model, per-game drill-down
   listeners, history-only live scores, token callables, the web-capable update button (D13).
4. **R2 floor: raise `minAppVersion` to the R2 client** about one week after availability in
   both production stores. Announce beforehand out of band (installed versions only have the
   fixed block screen; section 9 item 1), including web reload guidance.
5. **Purge public PII fields, then deploy R2 (final rules)** in one window. The allowlist (D12)
   is retired in the same release as the `AuthIndex` check goes live. Immediately run the
   post-deploy verification: a scoring event, a fixture download, reminders dry run, tip
   write/read before and after kickoff, admin merge, anonymous browse, push token registration.
6. **Rollback (smallest step first).** (1) A compatibility problem with R1: deploy the tested
   **recovery ruleset** (`config/generated/database.rules.r1-recovery.json`), which keeps
   allowlisted admins, identity protection and default deny and relaxes only validation strictness
   and the legacy 1.3.x Stats writers. (2) Anything else: fix forward. (3) **Emergency only:**
   `BACKUP-database.rules.json` is fully open and has outdated indexes; it restores unrestricted
   writes, so it is a last resort, and any rollback that reopens writes must be followed by
   re-running the identity audit. R2 rollback goes to R1, never to open rules. Deployments use
   `scripts/deploy-database-rules.sh --project <id>`, which checks the file Firebase ships and
   records the allowlist revision (phase 3 report, sections 6 and 8).

## 6. Implementation phases

1. **Inventory and spike: DONE.** See [DESIGN-database-rules-phase1.md](DESIGN-database-rules-phase1.md).
   Spike tests live in `rules_test/` (47 rules tests, a 10-check claim spike and a 52-check
   identity protocol spike).
2. **Phase 3 status: built, tested, and R1 deployed to production on 2026-10-06** (see
   [DESIGN-database-rules-phase3.md](DESIGN-database-rules-phase3.md)): R1 rules template and
   generator, the recovery ruleset, the allowlist consumers, the Dart endpoint change, the guarded
   deployment script, the identity audit script, hardened test isolation and 253 + 91 + 62
   automated checks (149 of the Node checks need no emulator: `npm run test:unit`). The deploy script
   refuses an empty or stale allowlist. The Dart functions change (the admin endpoints check the
   allowlist) was deployed on 2026-10-19 (`f0820ef`).
3. **Immediate owner actions** (no code): raise `minAppVersion` to `1.4.0` (step A); inspect the
   production Firestore rules (D11); run `scripts/verify_admin_auth_uids.mjs` and confirm the admin
   UIDs; check store version adoption. **Status:** done, except the Firestore inspection.
4. **Deploy R1** (owner decision, after the actions above): audit fixes, then the Dart functions,
   then the rules, then the post-deploy verification (phase 3 doc, section 6). **Status:** the rules were
   deployed first (2026-10-06) because R1 does not depend on the functions; the Dart functions followed
   on 2026-10-19, and the admin endpoints were verified from a real device (an allowlisted admin
   accepted, a database-role admin who is not on the list refused), as was an allowlisted admin's
   database edit. Sign-in, registration, push delivery and the scheduled functions are still to
   verify.
5. **Server pieces** (step 2) with tests, including the proofs re-run against the production
   database handle.
6. **R2 client release** (step 3), including the update-button fix.
7. **R2 rules, floor and cutover** (steps 4 and 5).
8. **Cleanup:** remove old code paths and the allowlist, update `docs/admin_authorization.md`,
   remove the dead `useBackendScoringBranches` flag.
9. **Firestore `tipLogs2` rules** (D11) are part of this release, not a follow-up.

## 7. Testing

- **Rules unit tests:** `@firebase/rules-unit-testing` with `node:test` against the RTDB
  emulator (`firebase.json`, port 8000). Actors: unauthenticated, anonymous, tipper A, tipper B,
  allowlisted admin, non-allowlisted record marked admin, user with no record, user with an
  inconsistent mapping. Read/write/delete for every path in both R1 and R2. Specific cases:
  - **R1:** legacy `Stats` writes rejected (a 1.3.x client's operations fail); admin-only areas
    refuse a non-allowlisted user, including one whose record says `tipperRole: admin`;
    anonymous users cannot write; own-record create with another role or uid denied; identity
    fields not writable by non-admins; allowlisted admin merge, role and paid edits work
  - tip write before, exactly at, and after kickoff; missing or malformed kickoff fails closed
  - non-owner tip read before/after kickoff; per-game listener allowed after kickoff; tipper-
    and comp-level listeners denied
  - owner single-tip delete before/after kickoff; **parent deletes** at
    `AllTips/{comp}/{tipperId}` (owner denied, admin allowed)
  - **multi-location `update()`** from the root mixing allowed and denied paths (all or none)
  - **`authuid`/`tipperRole` immutability: delete `/authuid` directly, delete it through a
    parent replacement, replace the whole record, and overwrite it with a changed value**
  - cannot write `AuthIndex`/`AliasIndex`/`LogonIndex`/locks/ops; cannot write `name`
  - **bidirectional check:** index entry pointing at an admin record whose `authuid` differs
    (denied); missing record; mismatched `authuid`; tampered index
  - private data readable by owner/admin only; public data readable by signed-in/anonymous
  - live scores: append-only, `tipperID` bound to caller, `t === now`, bounds, out-of-window,
    `current` write denied
  - unauthenticated `AppConfig` read allowed, write denied
- **Allowlist sync test:** the UIDs in the generated rules and in the Dart endpoints equal
  `config/admin-auth-uids.json`; adding a UID to only one place fails the test.
- **Identity protocol tests** (Dart, extending `functions_dart/test`; the phase 1 spike is the
  template): exact-placeholder replacement (and refusal of anything else), crash injection after
  every step of link and create then retry, partial state cannot be taken over, abandoned-create
  reaping, lease expiry takeover, concurrency (same uid, same alias, same email, concurrent links
  of one record, merge versus link), merge into a target owned by another uid (reject and
  `replaceUid`), admin endpoints reject a forged `AuthIndex` entry and a forged `authuid`/role,
  the audit job reports every violation class. **Run against the production database handle
  (deployed check), not only `firebase_dart` on the emulator.**
- **Live-score aggregator tests:** older computation finishing last, random completion order,
  duplicate/replayed events, trusted time, `gameComplete` never set, per-tipper caps.
- **Conformance replay:** replay the captured client read/write set against the seeded emulator
  (`scripts/seed_rtdb_emulator.sh`): **1.4.0 and 1.4.1 against R1**, and **the R2 client against
  R2**. A separate suite confirms legacy and obsolete operations fail closed.
- **Update-flow test:** a widget test that `UpdateAppLink` builds and acts on web without
  touching `Platform`.
- **Manual smoke tests** on seeded emulators before each deploy, and the post-deploy
  verification list in section 5 step 5.
- **CI:** add rules, callable, aggregator and allowlist tests to the backend test commands.

## 8. Risks

- Lockout from a too-strict rule. Mitigation: R1 then R2, conformance replays, strict rollback
  file, post-deploy verification.
- Identity backfill mislinks a user. Mitigation: derive from Firebase Auth emails, replace only
  audited placeholders, flag all disagreements, never auto-link ambiguous matches.
- A wrong UID in the admin allowlist. Mitigation: independent verification against Auth, owner
  sign-off, sync test; a missing admin is recoverable by redeploy, a wrong one is a privilege
  grant, so verification is mandatory.
- Incomplete `DateUtcEpochMs` or `TipperPrivate` backfill. Mitigation: verified-complete gates;
  fail-closed behaviour is tested.
- `root.child` lookups add latency and have unproven production limits (the emulator showed
  none up to 40). Mitigation: keep to a handful per path; check during post-deploy verification.
- The production Dart database handle (REST or Admin SDK) is not the one exercised by the
  spikes. Mitigation: choose it in phase 4 and re-run the protocol tests against it.
- Firestore `tipLogs2` may be client-readable, defeating pre-kickoff secrecy. Mitigation: D11,
  inspected now; no secrecy claim until closed.
- Legacy tip shape in live data may fail `.validate`. Mitigation: validation accepts both.
- Users who do not update before a cutoff are locked out, and web users cannot recover with the
  current button. Mitigation: announcement with reload guidance, D13.
- Obsolete or modified clients keep running after a floor is raised. Mitigation: the rules
  reject their writes (tested); the gate is not relied on.
- Merge races with concurrent user activity (accepted, verified afterwards).

## 9. Open items for the owner

1. **Do now (no code):**
   - Raise `minAppVersion` to **`1.4.0`**. 1.4.0 is public in both stores and on web.
   - **Inspect the production Firestore rules** (console, Firestore Database, Rules) and tell me
     whether clients can read `tipLogs2` (D11).
   - Run `node scripts/verify_admin_auth_uids.mjs` (read-only; needs credentials that can read
     Auth and the database) and confirm each admin UID is the right person.
2. **Cutoff announcements.** Two events: the 1.4.0 floor now (light, off-season) and the R2 floor
   later (about one week after availability in both stores). Installed versions show a **fixed**
   block message ("This version of the app is no longer supported, please update the app from the
   app store.") with an Update App button that works on iOS and Android but **not on web**.
   Advance warning must go out of band (store release notes, FCM push to existing device tokens,
   a message to tippers, https://interview.coach/tipping) and include web reload guidance.
   Owner to confirm dates, wording and channels.
3. **Client versions in the wild.** After the 1.4.0 floor only 1.4.0 and 1.4.1 matter. Still
   useful: store version adoption, and whether 1.4.1 is released.
4. **Reference data before sign-in.** D10 makes startup auth-aware (required anyway for
   `/AllTippers`). Should `/Teams`, `/AllDAUComps` and `/DAUCompsGames` (public fixture and team
   data, no personal data) also be public-read to lower startup risk, or stay auth-required?
   Recommendation: auth-required, relying on D10.

## 10. Review log

| Review | Finding | Disposition |
|---|---|---|
| 1 | Claims trigger trusts public identity fields | Server-only identity writes (D1, D2, D4) |
| 1 | New-user creation not bootstrappable | `linkOrCreateTipper` (D2) |
| 1 | Per-key public config cannot support startup | D8: public-read `/AppConfig` |
| 1 | Claim refresh and merge lifecycle | Mapping instead of claims; D3 lifecycle |
| 1 | Compatibility contradiction | Gated cutover (section 5) |
| 1 | PII exposure | D6, in this release |
| 1 | Live-score authorization thin | D7 |
| 2 | Unsafe window while root is public and identity data is trusted | R1 deployed first; section 5 |
| 2 | Field immutability and deletion | Leaf-only grants, no tipper-node `.write` (D4); tests |
| 2 | Identity consistency during access | Bidirectional check in rules and callables (D1/D2) |
| 2 | "One transaction" not concrete | Claim primitives, ordered idempotent steps, leases, audit (D3) |
| 2 | Name edits bypass alias uniqueness | `updateTipperAlias` callable; `name` server-only |
| 2 | Started tips not immutable | Per-game `onValue` listeners (D5) |
| 2 | Merge when target already owned | Reject by default; explicit `replaceUid` (D3) |
| 2 | Dart admin endpoints scan `authuid` | Allowlist in R1 (D12), `AuthIndex` check in R2 (D1) |
| 2 | Version gate uses dotted version | Patch-bump floors (section 3 #4) |
| 2 | Aggregation: ordering, duplicates, trusted time, completion | D7; only an official score completes a game |
| 3 | 1.4.0 is an R1 compatibility floor, not the security release | Two floors (section 3 #4, section 5) |
| 3 | Version gate does not stop running sessions or modified clients | Rules reject obsolete writes; tested (section 5 R1, section 7) |
| 3 | Admin allowlist must cover rules **and** the Dart admin endpoints, be independently verified, be retired later | D12, `scripts/verify_admin_auth_uids.mjs`, sync test |
| 3 | Do not defer Firestore rules inspection; picks and identities are in `tipLogs2` | D11 raised to a blocker for the secrecy claim; owner inspects now; in this release |
| 3 | Spike proved the claim primitive, not the protocol; null-to-UID claim cannot replace a placeholder | `replaceIf` on the exact audited placeholder; crash/retry, leases and reaping proven (52 checks, mutation-checked) (D3) |
| 3 | Aggregator invocations can finish in reverse order | Version-guarded transaction on `current`; proven (D7) |
| 3 | Web update failure is operational, not off-season only | D13 and the announcement requirement |
| 3 | Raw emails cannot be RTDB index keys | `LogonIndex` keyed by SHA-256 (D2) |
| 3 | Distinguish API inspection from empirical testing | Phase report updated: REST ETag path inspected, not run (D3, report section 4) |
| 4 | Live audit command fails without credentials; deploy guard; UID classification (Auth decides account vs placeholder); rollback too broad; contact-field limits | Fail-fast credential check, guarded deploy script, Auth-driven classification, `r1-recovery` variant, limits documented (phase 3 report sections 1, 6, 7) |
| 5 | "Tests cannot reach production" overstated: the network guard covered only Node; loopback check; stub location; launcher and Dart; substring project match | OS boundary (`sandbox-exec`), explicit `FIREBASE_BIN` stub, exact project matching; the claim was retracted (phase 3 report section 8) |
| 6 | Smoke test served SDK 12.19.0, not the release's 12.18.0; broad `pkill`; backend admin operations untested; wording | Exact-SDK enforcement, recorded process groups, limits and wording corrected, rerun 43 of 43; backend checks listed as post-deploy (phase 3 report section 3) |
