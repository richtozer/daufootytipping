# Phase 3 report: identity audit and R1 rules

Companion to [DESIGN-database-rules.md](DESIGN-database-rules.md) (section 5 steps 0 and 1) and
[DESIGN-database-rules-phase1.md](DESIGN-database-rules-phase1.md).

**Status: R1 is deployed to production** (2026-10-06 13:03Z, commit `a5f9f52`, allowlist revision
`58f7e4904e46`, rules sha256 `959f840c20d9`; see section 6). The live rules were read back after
deploying and are identical to `database.rules.json`, and were still identical on 2026-10-19 with no
rollback. The Dart functions change that makes the admin endpoints check the same allowlist was deployed on
2026-10-19 (commit `f0820ef`, allowlist revision `58f7e4904e46`; see section 6). The admin endpoints were then verified from a real device: they accepted an allowlisted admin and
refused a database-role admin who is not on the list, and an allowlisted admin's database edit was
accepted (section 6). The production Firestore rules were also inspected and replaced (2026-10-19,
section 6). Phase 4 (server pieces) and R2 are not started.
**One production incident occurred during this phase** (section 8): a test I wrote deployed fixture
rules to production, and the owner rolled them back. The test isolation was then rebuilt (section 8).
`test:live` remains unrun pending review.

## 1. What was built

| File | Purpose |
|---|---|
| `config/admin-auth-uids.json` | The single source for the R1 admin allowlist. **Populated by the owner with 4 UIDs (revision `58f7e4904e46`); I have not independently verified them.** |
| `config/database.rules.r1.template.json` | The R1 rules, with `{{IS_ADMIN}}` and `{{SIGNED_IN}}` placeholders |
| `scripts/build_admin_allowlist.mjs` | Generates the rules and the Dart constant from the one list; `--check` detects drift; refuses an empty list |
| `config/generated/database.rules.r1.json` | Generated R1 rules (currently with no admins, so **not deployable**) |
| `functions_dart/bin/admin_allowlist.g.dart` | Generated compile-time allowlist for the Dart admin endpoints |
| `functions_dart/bin/server.dart` | Role scan **deleted**; the three admin endpoints use `requireAdminAuthUid` |
| `scripts/deploy-functions.sh` | New step 1b: refuses to deploy the Dart codebase with an empty or stale allowlist |
| `scripts/audit_identity.mjs` | Read-only identity audit (offline export or live), optional Firebase Auth cross-check |
| `scripts/verify_admin_auth_uids.mjs` | Read-only admin UID verification against Firebase Auth; runs offline from Firebase CLI exports or live; fails fast without credentials |
| `scripts/deploy-database-rules.sh` | Guarded database rules deployment: explicit `--project` (required with `--yes`), explicit `FIREBASE_BIN`, checks the file Firebase actually ships, records the allowlist revision; `--variant r1-recovery` for compatibility rollbacks |
| `config/generated/database.rules.r1-recovery.json` | Generated recovery ruleset: R1 minus validation strictness, plus legacy 1.3.x Stats writers; every allowlist and identity protection kept |
| `config/deployments/allowlist-deployments.jsonl` | Written by deployments (one entry so far, the 2026-10-06 R1 rules deployment): which allowlist revision each rules/functions deployment used |
| `rules_test/support/isolated.sh` (OS boundary), `support/no_production.mjs`, `support/safety.mjs`, `support/firebase_stub.sh`, `os_boundary.test.mjs`, `safety.test.mjs`, `deploy_scripts.test.mjs`, `deploy_functions.test.mjs`, a dedicated `rules_test/firebase.json` | Test isolation (section 8) |
| `scripts/lib/admin_access.mjs` | Shared helpers: Auth-export lookups, a guard that refuses an unignored export (password hashes), credential check with a clear error |
| `rules_test/r1.rules.test.mjs` | 39 R1 conformance and rejection tests |
| `rules_test/allowlist.test.mjs` | 18 generator, drift and sync tests |
| `rules_test/audit_identity.test.mjs` | 12 audit tests on synthetic data |
| `rules_test/verify_admin.test.mjs` | 15 tests: offline mode, export parsing, hash guard, and the no-credentials failure (sandboxed so it cannot reach production) |

## 2. The R1 rule set (as built)

**Reads.** Open for the data the shipped client reads, per path (`AppConfig`, `Teams`,
`AllDAUComps`, `DAUCompsGames`, `AllTippers`, `AllTips`, `Stats`, `Diagnostics`) because 1.4.x
attaches several listeners before sign-in. **`AllTippersTokens` requires a sign-in** and the
root and unknown paths are closed. This is a small tightening beyond the plan: the client only
reads tokens after sign-in, and the stale-token function has no callers.

**Writes** (all require a non-anonymous sign-in unless stated):

| Area | R1 write |
|---|---|
| `AppConfig`, `AllDAUComps`, `Teams`, `DAUCompsGames` | allowlisted admins only |
| `AllTippers` collection | allowlisted admins (role, paid, authuid for merge, create, delete) |
| `AllTippers/{id}` create | a user, only with `tipperRole: 'tipper'`, `authuid == auth.uid`, no paid comps and no unknown keys |
| `AllTippers/{id}` leaves | `name`, `logon`, `email`, `isAnonymous`, `photoURL`, `acctCreatedUTC`, `acctLoggedOnUTC` by any signed-in user (status quo); `authuid`, `tipperRole`, `compsParticipatedIn` admin only |
| `AllTippers/{id}` validation | must keep `authuid` and `tipperRole`; role must be `admin` or `tipper`; typed leaves; binds admins too |
| `AllTippersTokens/{tipper}/{token}` | leaf only, any signed-in user (no parent wipe) |
| `AllTips/{comp}/{tipper}/{game}` | any signed-in user (status quo), shape validated; deleting a tipper's tips is admin only |
| `Stats/{comp}/live_scores_backend_v1/{game}/current` and `.../history/{key}` | any signed-in user (status quo) |
| every other `Stats` path (legacy `_v3`, audit, probe, backend branches, status) | **nobody** (server only), admins included |
| everything else (`Diagnostics`, identity indexes, unknown paths) | nobody |

Admin status is the **allowlist**, never a database role: a record that says `tipperRole: admin`
grants nothing (tested).

## 3. Verification

| Check | Result |
|---|---|
| R1 rules, 39 tests: reads, every admin-only area for allowlisted admins vs users vs anonymous vs unauthenticated vs a record-marked admin, own-record creation and its rejections, login-time leaf updates on a normal and a **legacy placeholder** record, identity immutability including delete and replacement, tokens, tips (compact, legacy, `z`, malformed, merge into legacy), live scores, ten legacy-writer operations rejected for **every** actor including admins, default deny | **39 of 39 pass** |
| **Mutation check** of the R1 template (13 deliberate weakenings: anonymous counted as signed-in, each create guard dropped, required-children validate dropped, `authuid`/`tipperRole` leaf grants, `AppConfig` opened, a legacy branch opened, token parent wipe, tip tipper-level delete, tip result unchecked, tokens readable unauthenticated) | **13 of 13 caught** |
| Allowlist generator and sync, 18 tests: UID shape, duplicates, empty list refused, fail-closed empty rules, no hard-coded UIDs in the template, committed outputs match the config, rules and Dart name the same UIDs, drift and hand-edit detection | **18 of 18 pass** |
| Identity audit, 12 tests on synthetic data: every finding category, no PII in findings, input never modified, Auth cross-check, CLI refuses to write email addresses to a non-ignored path | **12 of 12 pass** |
| Whole Node suite (`cd rules_test && npm test`, inside the OS boundary; the live-CLI suite is skipped) | **253 tests: 248 pass, 5 skipped** (credential directories that do not exist on this machine) |
| Dart spikes (`npm run test:dart`) | 10 + 52 checks pass |
| `functions_dart` tests | **91 pass** (88 before; the scan tests were replaced by allowlist tests, including "a forged database admin record grants nothing" and "authorization does not read the database") |
| `dart analyze` on `functions_dart` | no issues |

Bugs the tests caught in my own work: the generator silently did nothing (exit 0) when invoked
through a symlink, which would have let the **deploy guard pass an empty allowlist**; fixed by
comparing real paths and covered by a test. Earlier, the admin verification script used a removed
`firebase-admin` API.

**What the replay does not cover:** it encodes the client's operations from reading the code (shapes
from `Tipper.toJson`, `Tip.toJson` and the view models). The real released app has now been run
against the emulators with R1 applied; see "Real-client smoke test" below.

### Real-client smoke test

The released 1.4.0 (build 712) **web** build, driven through its own UI in a contained headless
browser against the emulators with the R1 rules loaded (`rules_test/smoke/`, README there). Synthetic
data only; the only admin the rules know is a fixture UID. It runs inside the same OS boundary as the
other tests (loopback only, no credentials).

**Result: 43 checks, 0 failed**, with the browser served exactly the Firebase JS SDK the release asks
for (**12.18.0**, the `firebase_core_web 3.11.0` default), from a clean seed.

How that was reached, because it changed the evidence. An earlier 43 of 43 run served SDK **12.19.0**:
my harness forced that version (the npm copy that happened to be installed), so it was not the released
client on its own SDK (found in review). The harness now reads the version the build asks for, refuses
to start unless exactly that version is served (`smoke/sdk`, pinned), does not override the app's
choice and aborts any request for another version. The first runs on the corrected SDK failed on
**harness faults only**: the modified-client scenario (S11) still imported a hard-coded 12.19.0, which
the stricter routing correctly refused; and my snapshot helper listed hundreds of saved snapshots
through `ls | head`, which dies of SIGPIPE under `pipefail`, so text checks failed even though the text
was on screen. Both are fixed (the helper now reads the file the command reports; text is matched in
the shell; checks wait for the condition instead of sleeping; an unreadable console log can no longer
count as "no denials"). The app's and the rules' behaviour were the same in every run.

What a pass shows: the flows below work under R1 with the released client, and the escalation paths
exercised are refused. It does **not** show that all normal use works or that no escalation path
exists; the rules tests carry the wider matrix.

- **Normal use works under R1:** fresh sign-in, a placeholder-backed legacy account (ordinary login of
  an existing account does not write `authuid`; registration and admin merge do, and R1 accepts
  those), registration with the client-side alias collision check, tipping, anonymous browsing.
- **Admin use works for an allowlisted admin:** paid/unpaid edits, merge, god mode, role change.
- **The escalation is closed in the real client:** a user whose database role is `admin` but who is not
  on the allowlist still sees admin screens (the client trusts the database) and the rules refuse the
  write; the app shows its own failure message and the data is unchanged.
- **A modified client** using the same SDK is denied on all eleven attack writes; the known R1
  concession (editing another tipper's `logon`, K1) is pinned as a documented, accepted exposure.

What it did **not** exercise:

- **The backend.** Only the Auth, Database and Firestore emulators run, not Functions. Fixture
  download, rescore and the other admin endpoints are not tested against the Dart allowlist change by
  this run; the backend unit tests are the pre-deployment evidence, and these are explicit
  post-deployment checks (step 6).
- **Device token registration and reassignment.** Web push never registers in a headless browser, and
  a simulator would not necessarily prove it either. Covered by the rules tests; verify on a real
  device immediately after deployment (step 6). Treated as an accepted limitation before rollout.
- The iOS and Android builds, and Google/Apple sign-in.

The build is 1.4.0+712; 1.4.1 writes the same paths. The app was patched at startup only (demo
project, App Check skipped, emulator hooks enabled in a release build, Auth emulator hook added). Two
assertions in the first run failed because of my driver script (a navigation assumption, and a Back
click mistaken for Save); the app and the rules behaved correctly. The S9 denial check now requires
the app's failure message, the SDK's `permission_denied` and the unchanged data together, so it cannot
pass without the write having been attempted. The harness's process cleanup no longer uses name
patterns: it signals only recorded process groups and a browser carrying a per-run marker.

## 4. Identity audit on the end-of-2026 export (aggregates; no personal data)

`node scripts/audit_identity.mjs --file test/data/<export>.json`

| Finding | Count | Action before backfill |
|---|---|---|
| Tippers / active in the 2026 comp | 211 / 80 | |
| Admins; with a placeholder or missing uid | 4; 0 | verify the 4 UIDs (section 5) |
| Placeholder `authuid` (email addresses) / active in 2026 | 40 / **2** | record each exact string in `/Placeholders`; backfill the 2 active (paid) users first |
| Missing `authuid` | 0 | |
| Duplicate `authuid`: real UID / placeholder | **1** group / 3 groups | merge or delete the real-UID pair (one has a login and 12 tips, the other neither); placeholders shared by distinct people are fine but must be backfilled individually |
| Duplicate `logon` / `email` groups | 3 / 2 | resolve by hand before indexing |
| **A record's `logon` equals another record's `email`** | **5 records** | new finding; linking by either would be ambiguous: resolve by hand |
| Contact not trimmed and lower-case | 1 | normalise |
| Alias collisions under normalisation | 4 groups | resolve by hand |
| Alias empty or missing after normalisation | 2 | require a new alias |
| Alias longer than the 64-character cap | 0 | |
| Tip or token nodes for a missing tipper | 0 / 0 | |
| Games with an unparsable `DateUtc` | 0 of 2,121 | epoch backfill is deterministic |

The Firebase Auth cross-check (which proposes a backfill uid per placeholder and flags unverified
emails and uids already used by another record) was run on 2026-10-19; see below.

### With the Auth cross-check (run 2026-10-19, on the 5 October exports)

Run offline and read-only, inside the test suite's operating-system boundary (no network):
`node scripts/audit_identity.mjs --file test/data/db-now.json --auth-export test/data/auth-export.json`.
Firebase Auth is the authority: a record is an account only if its `authuid` exists in Auth. No
placeholder file was written (it would contain email addresses). Counts only:

| Finding | Shape-only audit (above) | With the Auth check |
|---|---|---|
| Tippers / active in 2026 | 211 / 80 | 214 / 80 |
| Admins; with a placeholder or missing uid | 4; 0 | 4; 0 |
| Placeholder-backed records / active in 2026 | 40 / 2 | **52 / 4** |
| Real-UID duplicate groups / placeholder groups | 1 / 3 | 1 / 3 |
| Duplicate `logon` / `email` groups | 3 / 2 | 3 / 2 |
| A `logon` equal to another record's `email` | 5 | 5 |
| Contact not trimmed and lower-case | 1 | 1 |
| Alias collision groups / empty aliases | 4 / 2 | 4 / 2 |
| Orphaned tips / orphaned tokens / missing `authuid` | 0 / 0 / 0 | 0 / 0 / 0 |
| Games with an unparsable `DateUtc` | 0 of 2,121 | 0 of 2,126 |

The 52 placeholder-backed records are:

- **37** plain email placeholders with no matching Auth account (1 active);
- **12** with a well-formed UID that does not exist in Auth and no account for their email (2 active):
  stale or deleted accounts, which is why the count is higher than the shape-only 40;
- **3** backfill candidates (Auth has exactly one account with the record's email, and none is already
  claimed by another record): 1 with a verified email and 2 with an unverified one (1 active).

Of the 13 Auth disagreements, 12 are the stale UIDs above and 1 is a record whose account exists but
whose verified email differs from the record's contact.

Reading: nothing here blocks R2; it is data work the migration must handle. The 4 active
placeholder-backed users would be relinked at their next login through the placeholder claim path
(`replaceIf`, design D3). An unverified backfill candidate must not be linked automatically, since an
unverified email may belong to someone else. The duplicates, collisions and cross-matching contacts need
the owner's decisions; an opaque-ID worklist (no names) can be produced. The exports are from 2026-10-05,
so refresh them before any backfill, and delete `test/data/auth-export.json` (it holds password hashes)
when finished.

## 5. Owner actions before R1 (status as of 2026-10-19)

R1 is deployed, so this section is now a record. Status of each action:

1. **Verify the admin UIDs: done.** The verification run found all four admin records in Firebase
   Auth, each with a matching, verified account and no shared UID (verdict OK for each); the owner
   then instructed the deployment.
2. **Inspect the production Firestore rules (D11): done 2026-10-19** (section 6): no client can read
   Firestore, and a version-controlled ruleset replaced the old one.
3. **Identity audit with the Auth check: done 2026-10-19**, on the 5 October exports (section 4). It
   gates the identity migration, not R1; its findings need the owner's decisions before that migration.
4. **`minAppVersion` 1.4.0: done.** Production reads `1.4.0` (checked 2026-10-06 and 2026-10-19).

The original instructions follow, kept for reference.

The scripts need data from production. **Option A needs nothing beyond the Firebase CLI you are
already logged into** and keeps the scripts offline; option B needs Google Application Default
Credentials (`gcloud auth application-default login`, then
`gcloud auth application-default set-quota-project dau-footy-tipping-f8a42`). A script run without
credentials now fails in about a second with these instructions, instead of hanging.

**Option A (offline):**

```bash
mkdir -p test/data
firebase database:get / --project dau-footy-tipping-f8a42 -o test/data/db-now.json
firebase auth:export test/data/auth-export.json --project dau-footy-tipping-f8a42
```

The Auth export contains **password hashes**. Keep it under `test/data/` (git-ignored; the scripts
refuse it inside the repo otherwise) and delete it when you have finished
(`rm test/data/auth-export.json`).

1. **Verify the admin UIDs** (the list is populated; this confirms it is right):
   `node scripts/verify_admin_auth_uids.mjs --db-file test/data/db-now.json --auth-export test/data/auth-export.json`
   (or, with Application Default Credentials, just `node scripts/verify_admin_auth_uids.mjs`).
   Confirm each admin is the right person; put the UIDs in `config/admin-auth-uids.json`; run
   `node scripts/build_admin_allowlist.mjs`; commit the regenerated files. The **deploy scripts and
   `--check-deploy` refuse an empty or stale list; the unit tests deliberately tolerate an empty
   one** so development can proceed, so a green test run does not by itself prove the list is
   populated.
2. **Inspect the production Firestore rules** (design D11) and tell me whether clients can read
   `tipLogs2`.
3. **Run the identity audit with the Auth check:**
   `node scripts/audit_identity.mjs --file test/data/db-now.json --auth-export test/data/auth-export.json --placeholders-out test/data/placeholders.json`
   (the placeholder file contains email addresses and is only written to a git-ignored path), then
   fix the items in section 4 by hand.
4. Raise `minAppVersion` to `1.4.0` and let some time pass.

## 6. R1 deployment procedure (rules deployed 2026-10-06; Dart functions deployed 2026-10-19)

Every deployment names its target project explicitly and is run only on the owner's explicit
instruction in chat, never by a test.

1. `cd rules_test && npm test && npm run test:unit && npm run test:dart` all green (they run inside the
   OS boundary and refuse to run without it);
   `node scripts/build_admin_allowlist.mjs --check` passes (it fails on an empty list).
2. **Smoke test with the real client** against the emulators with the R1 rules, fixture admin UIDs and
   no production credentials: **done** for the web build, on the release's exact Firebase JS SDK
   (section 3, `rules_test/smoke/`). It used a synthetic fixture rather than the export, and did not
   run Functions, push-token registration or the mobile builds; those are covered by backend unit
   tests, the rules tests and the post-deploy checks below.
3. **Install and commit the ruleset:**
   `node scripts/build_admin_allowlist.mjs --install-rules --variant r1`, then commit
   `database.rules.json` and the generated files.
4. **Deploy the Dart functions:** `scripts/deploy-functions.sh --project <id> --only dart`
   (`--dry-run` first). It now requires an explicit, exactly matching `--project`; it refuses an
   empty or stale allowlist and, on success, records the allowlist revision.
5. **Deploy the rules:** `scripts/deploy-database-rules.sh --project <the production project id>`
   (the project must be the active one, compared exactly).
   It refuses unless `database.rules.json` is exactly the generated R1 rules for the current
   allowlist, the list is non-empty and the tree is clean; it prints the allowlist revision and
   asks you to type `deploy`. `--dry-run` runs every check and stops. Commit
   `config/deployments/allowlist-deployments.jsonl` afterwards.
6. **Post-deploy verification:** an admin edits `AppConfig`; a normal user logs in (including one of
   the placeholder users); a tip is written and read; an admin runs a fixture download and a
   rescore (these are not covered by the smoke test, which does not run Functions); a scheduled
   scoring event fires; the reminders function runs; a new user registers; **a push token registers
   on a real iOS or Android device** (the smoke test cannot prove this); a 1.3.x client's write is
   rejected; an anonymous user browses read-only.

### What was done on 2026-10-06

- **Step 1, gates:** all passed with 0 failures: unit tests 149 (144 pass, 5 skipped), rules suite 253
  (248 pass, 5 skipped), Dart spikes all checks passed. The skips are the `test:live` suite and boundary
  checks for credential files that do not exist on that machine.
- **Step 2:** done (section 3).
- **Step 3:** the ruleset was installed and committed (`a5f9f52`). The existing indexes
  (`AllTippers`, `DAUCompsGames`) are preserved.
- **Step 4, Dart functions: deferred to 2026-10-19** (see below). The rules went first because R1 does
  not depend on the new functions: role writes are admin-only under R1, so the old database-role check
  in the admin endpoints can no longer be self-granted by a client.
- **Step 5:** `scripts/deploy-database-rules.sh --project dau-footy-tipping-f8a42 --yes --allow-dirty`
  (the tree was dirty only because of unrelated UI work in progress; the ruleset and config were
  committed and clean). Production `minAppVersion` was already `1.4.0`. The live rules were then read
  back with `firebase database:get /.settings/rules` and were identical to `database.rules.json`.
  The deployment record is committed (`4854bab`).
- **Step 6:** partly done, below.

### Dart functions deployment (2026-10-19)

`scripts/deploy-functions.sh --project dau-footy-tipping-f8a42 --only dart --yes`, from `f0820ef` with a
clean tree, on the owner's instruction (the competition is closed, so it is the off-season).

- The gate passed: allowlist check, manifest generation, analyzer and tests for `dau_shared` and
  `functions_dart`, then the Linux build. This deploy also ships whatever Dart backend dependency
  updates (`34f4c10`) were not already live.
- **The Firebase CLI exited with an error** (exit 2): four of the six functions
  (`admin-fixture-download`, `admin-scoring-rescore`, `scheduled-fixture-download`, `app-badge-count`)
  reported "Task index 0 failed: timed out after 30000ms", and `admin-check-fixture-url` and
  `backend-scoring-command` reported success. The script therefore did not write its deployment
  record or print its "Done" summary.
- **Verification that the code is live:** all six Cloud Run services have a latest ready revision
  created during the deploy (16:30:06 to 16:31:11Z), Ready, with 100% of traffic. The four reported
  failures are therefore a CLI-side timeout while waiting on slower revisions, not failed revisions.
  Each service answers an unauthenticated request with its own 401 or 403 from our code, and no
  error-level log entries appeared. The record was then written by hand with
  `node scripts/build_admin_allowlist.mjs --record functions`.
- **Verified afterwards, the same day, from a release build (1.4.1+713, `a187f5f`) on the owner's iPhone,
  read from the Cloud Run request logs:**
  - an allowlisted admin's rescore: `admin-scoring-rescore` returned **200** (16:57Z);
  - the same admin's fixture download: `admin-fixture-download` returned **200** (16:59Z), followed by
    a **200** from `backend-scoring-command`, the automatic rescore the download triggers;
  - **the refusal case:** the owner's own trusted test tipper, given the database role `admin` but
    not on the allowlist, got **403 PERMISSION_DENIED "User is not authorized as admin"** from
    `admin-scoring-rescore` (17:03Z), rejected before any work was done. The role was left as `admin`
    on that account deliberately: under R1 the allowlist decides, so the role confers nothing;
  - no other warnings or errors from any Dart function since the deploy, apart from the deliberate
    unauthenticated probes made during verification (401/403).
- A repeat run of the script would retry the four updates and may time out the same way; it is not
  needed for the code to be live, and only lets Firebase's own bookkeeping catch up.

### Post-deploy verification on production (2026-10-07)

A debug build (1.4.1+713) on the iPhone Duo simulator, run against production with the emulators off,
signed in as a standard tipper:

- it started cleanly with no runtime errors;
- it registered a push token (the tipper had none) and wrote its last-login time, and **both writes
  were accepted by R1**;
- the Tips tab (round headers with points and rank, game cards) and the Competition Leaderboard
  rendered live data with no error text.

Limits: the simulator's screen capture was blank for the agent, so screens were read through the
Flutter widget inspector; the Percentage Tipped page and the Profile tab (no admin options) were not
confirmed that way. Tipping was not possible because the competition is closed. The alias edit was
skipped on production, having been exercised against the same rules in the emulator (accepted, then
reverted).

### Admin database edit on production (2026-10-19)

From the owner's iPhone, signed in as an allowlisted admin, the owner marked the test tipper (their own
trusted test account) paid for the current comp, then unpaid again. Production was polled with
read-only CLI reads while they did it:

| Time (UTC) | The test tipper's `compsParticipatedIn` |
|---|---|
| before | empty |
| 17:16:13 | the 2026 comp key (marked paid) |
| 17:17:09 | empty again (marked unpaid) |

`compsParticipatedIn` is an admin-only field under R1, so both writes were accepted by the rules
for an allowlisted account. The tipper's data was back to its original state afterwards. The watcher
reported one false change at 17:16:31 (the Firebase CLI echoed a one-off error beside the same
value); direct reads at that moment showed no change.

### Firestore rules (2026-10-19)

**Finding.** The production Firestore rules were read-only through the Firebase Rules API (the
owner's gcloud login). There was one release, last changed 2025-04-23 (ruleset `5f0233f3`), and it
contained a single match: `tipLogs/{year}/{round}/{tipperId}/{gameId}/{tipTimestamp}` with
`allow write: if true` (the comment said "authenticated"; the rule was open to anyone). There was no
read rule anywhere, so everything not matched was denied. Consequences:

1. **Tip secrecy is not at risk from Firestore.** No client can read any Firestore data, so design
   D11's concern (picks and identities in `tipLogs2` being client-readable) does not apply.
2. **Tip logging had silently stopped.** The client moved from the nested `tipLogs/...` path to the flat
   `tipLogs2` collection on 2026-05-10 (`1c261ad`), but no rule covered `tipLogs2`, so every client write
   was denied and the client only logged the error. `tipLogs2` held 12,400 entries, all from
   2025-04-27 to 2025-07-27, and none after the change. The log for the rest of the 2026 season was not
   recorded and cannot be recovered; the tips themselves are in the Realtime Database.
3. **The old path was open to the internet** (anonymous writes), a spam and cost risk but not a
   disclosure.

**Fix** (`06cc9cb`): `firestore.rules`, with the `firestore` entry in `firebase.json`. A signed-in
tipper (not the anonymous browsing account) may create a `tipLogs2` entry that has `createdAt` equal to
the server time, a `submittedAtUTC` timestamp, string `tipperId`, `gameId`, `compId` and `tip`, a
`tipResult` of `a` to `e` or `z`, and at most 40 fields. All reads, updates and deletes and every other
path are denied, including the old nested path. The shape check is deliberately loose, so a field added
to the client later cannot silently stop logging again. `rules_test/firestore.rules.test.mjs` has 17
tests, including one that reads the client source's field list to catch drift, and the suite now runs a
Firestore emulator alongside the Database one. Seven deliberate breakages of the rules (reads opened,
updates opened, anonymous allowed, sign-in dropped, server time not forced, field cap removed, old path
reopened) were each caught.

**Deployment:** `firebase deploy --only firestore:rules --project dau-footy-tipping-f8a42`, at about
18:14Z. The live release (`cloud.firestore`, ruleset `1689f54a`) was read back and is identical to
`firestore.rules`. The previous rules text is in the commit message, as the rollback. The deployment
scripts and `config/deployments` cover only the Realtime Database and the functions, so this deployment
has no record file.

**Verified from the owner's iPhone:** a god-mode tip on the test tipper at 18:15:07Z landed in the
Realtime Database within seconds, and `tipLogs2` went from 12,400 to 12,401 three seconds later (a
24-field entry, app 1.4.1 build 713, ios, with the god-mode shape: submitted by someone other than the
tipper). An earlier attempt the same hour was inconclusive for the Firestore log: the phone's connection
to the database stalled, the write was only sent after a force-quit and relaunch, and the relaunched
process replays the database write without the logging step.

**Still to verify** (needs real accounts or devices): Apple and Google sign-in; new registration; push
delivery on a real device; scheduled scoring and the reminders function; a 1.3.x client's write being
rejected (covered by tests only). The admin endpoints and an allowlisted admin's database edit are
verified (above).

**Rollback ladder (use the smallest step that fixes the problem):**

1. **A compatibility problem with R1** (a legitimate client operation is rejected): deploy the
   tested **recovery ruleset**: `node scripts/build_admin_allowlist.mjs --install-rules --variant r1-recovery`,
   commit, then `scripts/deploy-database-rules.sh --variant r1-recovery --project <id>`. It keeps
   allowlisted admins, identity-field protection, no anonymous writes, no parent wipes and the
   closed backend branches; it relaxes only validation strictness and re-admits the legacy 1.3.x
   Stats writers. It is tested (including 4 of 4 mutations of its protections caught).
2. **Anything else:** fix forward and redeploy R1.
3. **Emergency only, a last resort:** `BACKUP-database.rules.json`. This restores unrestricted
   database writes, so it is an exceptional action, not the normal rollback. Re-run the identity
   audit afterwards.

## 7. Contact fields and the limits of the audit

R1 deliberately lets any non-anonymous user write `email` and `logon` on any record (a
compatibility concession: placeholder records and users matched by email cannot satisfy an owner
check). So **this audit can become stale immediately**, and it can never by itself justify trusting
those fields. Therefore:

- **No migration recomputes identity from the database.** The backfill uses a reviewed mapping
  file produced from Firebase Auth (the audit's backfill proposals: `tipperId`, proposed uid, the
  Auth email as evidence). The owner reviews and signs off the mapping; the migration applies only
  entries in that file.
- **Freeze and re-audit:** immediately before applying a mapping, the audit is re-run; the apply
  step aborts for any record whose `logon`, `email` or `authuid` no longer equals the audited
  snapshot, and replaces a placeholder only if it equals the exact audited string (design D3).
- **The admin verification proves consistency, not entitlement.** An Auth account whose verified
  email matches an admin record shows the record and the account agree; it does not show that the
  person should be an administrator. Your own confirmation of each admin remains essential.

Prerequisites, separated by what they gate:

| Gate | Needs |
|---|---|
| **R1 (the admin-security fix)** | **Done 2026-10-06:** verified admins; the 1.4.0 floor in place; the real-client emulator smoke test (web, exact SDK, section 3); guarded deployment and the recovery ruleset. **Dart functions deployed 2026-10-19** (the admin endpoints check the allowlist) |
| **Identity migration (later)** | duplicate identities, alias collisions and ambiguous contacts resolved; a reviewed mapping; a freeze and re-audit. These do not delay R1 |
| **Claiming pre-kickoff tip secrecy** | **Done 2026-10-19:** Firestore rules inspected (no client has read access) and replaced by a version-controlled create-only ruleset |

## 8. Incident and prevention

**What happened.** While testing `scripts/deploy-database-rules.sh` I ran it in a throwaway copy of
the repository with a stub `firebase`. The script prepended `~/.npm-global/bin` to the `PATH`, which
put the real `firebase` ahead of the stub, and the sandbox's copy of `.firebaserc` still named the
production project. Two tests therefore ran a real `firebase deploy --only database`, and the last
one left my recovery ruleset, with a fixture admin UID, live on the production database. I noticed
because the success-path tests exited 0 while the stub recorded nothing; I confirmed the live rules
with `firebase database:get /.settings/rules`. My attempt to restore the committed rules was
(correctly) blocked by the permission system, so the owner rolled back and verified the previous
production permissions. I have since confirmed read-only, twice, that the live rules equal the
committed `database.rules.json` with no fixture UID. Nothing else was changed in production.

**A claim I made and have to retract.** After my first round of fixes I wrote that the tests
"cannot reach production, whatever else is true". That was wrong. The reviewer was right on every
point: a Node preload is a *check*, not a *sandbox*; it does not see Bash, native executables, Dart
or Java. The accurate statement is below.

**What is actually enforced now, by layer.**

| Layer | Scope | What it does | Strength |
|---|---|---|---|
| **1. OS boundary** `rules_test/support/isolated.sh` (macOS `sandbox-exec`) | **every process the npm test commands start**: Node, Bash, native tools, Dart, Java (the emulators), and the Firebase launcher itself | no outbound network except loopback and unix sockets; the usual credential stores unreadable (Firebase CLI login, gcloud, gh, ssh, aws, azure, kube, docker, netrc, macOS Keychains directory); an explicit minimal environment (`env -i`), no credential or proxy variables, an **empty** `XDG_CONFIG_HOME` so no stored login is visible; **fails closed** (refuses to run) when no boundary exists | the real guarantee, for what it contains; proven by `os_boundary.test.mjs` |
| **2. Fail-closed gating** | every test that spawns a process | `sandboxEnv()` throws unless the runner declared the boundary (`OS_BOUNDARY=1`), and the canary refuses to attempt any external connection unless the OS first answers `EPERM` to a connect to 192.0.2.1 (an RFC 5737 documentation address that is never routed) | a stray `node --test x.test.mjs` refuses to run rather than running unprotected |
| **3. Node preload** `support/no_production.mjs` | Node processes only | refuses non-loopback connections and DNS (a **validated** IP in 127.0.0.0/8 or `::1`, or exactly `localhost`; `127.example.com`, `0.0.0.0` and `::` are refused); refuses `firebase`/`gcloud` unless the file is byte-identical to the checked-in stub (SHA-256) at the exact path named in `NO_PRODUCTION_STUB`; `gcloud` never | an early, friendly failure; **not** the safety mechanism |
| **4. Script-level conventions** | the scripts under test | explicit `FIREBASE_BIN`, no PATH prepend when a firebase is already resolvable, `--project` required (and required with `--yes`), project compared **exactly** after parsing `firebase use`, the stub refusing any non-`demo-` deploy, sandbox `.firebaserc` never copied from the repo | defence in depth |

**Evidence.** The boundary canaries prove, from inside it, that native `curl`, Bash (`/dev/tcp`),
Python and Dart cannot connect (by name or by address), that loopback still works for all of them,
that the credential stores that exist here are unreadable, that the runner drops a deliberately
hostile caller environment (credentials, proxies, a real `XDG_CONFIG_HOME`), and that every npm test
command goes through the runner. I broke each layer on purpose (removing the network deny, allowing
all outbound, making the Firebase config readable, no `OS_BOUNDARY`, passing the caller's
`XDG_CONFIG_HOME` or credentials through, the loopback `startsWith('127.')` bug, treating `0.0.0.0`
as loopback, identifying the stub by location instead of content, allowing any temp-dir `firebase`,
substring project matching, dropping the `--yes`/`--project` rule, the original unconditional PATH
prepend, omitting `--project` from the deploy line) and **every one is caught** (two were missed on
the first attempt and fixed by adding tests). A rules-for-future-tests scan enforces: no test names
the production project, none passes `process.env` to a child, every spawning test uses `sandboxEnv`,
and the npm scripts use the runner, the preload and `demo-` projects only.

**The five review findings.**

| Finding | Resolution |
|---|---|
| P1: the network restriction covered only Node APIs | OS-level boundary for the whole process tree, plus canaries for Bash, native, Python, Dart; the preload is demoted to an additional check |
| P2: `startsWith('127.')` accepted `127.example.com`; `0.0.0.0`/`::` called loopback | validated IPs only (`net.isIP`) or exactly `localhost`; `0.0.0.0` and `::` refused; tested for connect and DNS |
| P3: any `firebase` under the temp dir was allowed | only the byte-identical checked-in stub at the exact `NO_PRODUCTION_STUB` path; a copy elsewhere and a tampered stub are refused; `gcloud` never |
| P4: the launcher and the Dart command were outside `sandboxEnv` | every npm script, including the Firebase launcher and the Dart spikes, runs through the OS boundary; the scope claim is restated per layer above |
| P5: project check was a substring match | the active project is parsed from `firebase use` and compared for equality in both deploy scripts; tested with superstrings, prefixes, case, and both output shapes |
| `deploy-functions.sh` hardening required before the backend deployment | done: `--project` required (and with `--yes`), exact match, `FIREBASE_BIN`, no unconditional PATH prepend, `--dry-run`, explicit `--project` on the deploy line (source-checked); tested through refusal and dry-run paths only |

**Known limits, stated plainly.**
- The boundary is **macOS `sandbox-exec`** (deprecated by Apple, verified working on this machine).
  Elsewhere the runner **fails closed**. A Linux CI would need a container started with no network
  and no credentials, with `OS_BOUNDARY=1` declared; the canaries would then verify it. That path is
  untested here.
- It protects what the **npm scripts launch**. The `npm` process, your shell, and anything you run
  outside those scripts are not in it. Spawning tests refuse to run outside it (layer 2), but the
  rules and spike tests that only talk to the emulators do not spawn processes and are not gated.
- Unix sockets are allowed (the emulators and the system need them) and so is loopback, so the
  boundary does not stop a process talking to **other local services** on this machine. I have not
  proven that no credential is reachable through some other OS service (for example the keychain via
  system services); the credentials these tools actually use are files, which are denied.
- Passing the scans and mutation tests proves the cases tested, not that other paths are impossible.
- `test:live` and the real `deploy-*` scripts have never been run against anything real by these
  tests. `scripts/deploy-functions.sh`'s build steps are not exercised by any test.

**`test:live` stays unrun until the owner reviews it.** It uses `demo-dau-rules`, never names the
production project, gets only a sandboxed environment with loopback emulator hosts, is skipped unless
both emulator hosts are present, and now runs inside the OS boundary like everything else. It ran
twice during development, against the emulators, before the review that led to these changes.

## 9. Next

1. **Finish the post-deploy verification** (the "Still to verify" list in section 6), mainly with real
   accounts and devices. The admin endpoints and database edit are done.
2. **Phase 4 (server pieces) and the R2 client**, per the design. R1's known concession (any signed-in
   user can edit another tipper's `email` or `logon`) stays until R2.
