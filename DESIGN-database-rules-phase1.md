# Phase 1 report: inventory and spike

Companion to [DESIGN-database-rules.md](DESIGN-database-rules.md). No app, function or rules
behaviour was changed. The only additions are `rules_test/` (spike tests) and these documents.

**Revision 2:** re-checked against the end-of-2026 export
(`test/data/...-export-42-end-comp-2026.json`, taken 2026-10-05). This replaced the earlier
end-of-2025 numbers, closed the two "needs live data" items, and corrected two statements from
revision 1 (marked **Corrected** below).

**Revision 3:** after the third design review. Adds the identity protocol spike (section 4.2), a
read-only admin UID verification script, and separates **empirical tests** from **API
inspection** (section 4.3). The 1.4.0 version floor supersedes the R1 compatibility baseline in
section 2.6, and production web was updated to 1.4.0+712 on 2026-10-05.

## 1. Summary

| Question | Result |
|---|---|
| Do the rules semantics the design relies on hold? | **Yes.** 47 of 47 emulator tests pass (section 3). |
| Can the Dart backend do compare-and-set claims? | **Yes, via `firebase_dart`'s `runTransaction`**: proven under contention (section 4.1). The project's REST ETag path is inspected only, not run (section 4.3). |
| Does the full identity protocol (not just one claim) hold? | **Yes, in the emulator.** 52 checks: exact-placeholder replacement, crash injection at every step then retry, partial states, abandoned creates, leases, aggregator ordering; mutation-checked (section 4.2). |
| Does the shipped client work under auth-required reads? | **No.** It attaches listeners before sign-in (section 2.3). Changes R1 and adds client work D10. |
| Is `authuid` empty for unlinked records? | **No.** 40 of 211 hold an email-address placeholder (2 active in 2026); 1 real UID is duplicated (section 5). |
| Do released clients write anything HEAD does not? | **Yes (corrected).** 1.3.x clients write legacy `Stats` branches as ordinary tippers (section 2.6). The **1.4.0 floor excludes them**, and R1 rejects their writes anyway. |
| Do device tokens fit "owner only"? | **No.** The client does cross-tipper token operations (section 2.4). New D9. |
| Is anything outside RTDB exposed? | **Unknown, and a blocker for the pre-kickoff secrecy claim.** Firestore `tipLogs2` holds picks and identities and has no rules in the repo; the owner must inspect the console rules (section 2.5, D11). |
| Is the kickoff backfill deterministic? | **Yes.** 2,121 of 2,121 games match the `DateUtc` format. |
| Is `AppConfig` safe to make public-read? | **Yes.** Live node (2026 export) has 10 keys and no secrets. |

## 2. Code inventory (verified against the code)

### 2.1 Reads
| When | Path | How |
|---|---|---|
| Before sign-in | `/AppConfig` | whole-node listener (`config_viewmodel.dart:128`) and child gets |
| Before sign-in (see 2.3) | `/Teams`, `/AllTippers`, `/AllDAUComps` | listeners from the view-model warm-up |
| After sign-in | `/DAUCompsGames/{comp}` | listener, `get`, `once` |
| After sign-in | `/AllTips/{comp}/{tipper}` | listener; per-game `get` for cross-comp lookups |
| After sign-in | `/Stats/{comp}/round_stats_backend_v1`, `live_scores_backend_v1` | listeners |
| After sign-in | `/Stats/{comp}/game_stats_backend_v1/{paid\|free}` | listener (cohort chosen by paid status) and per-game `get` |
| Admin | `/Stats/{comp}/scoring_status` | fixture banner stream |
| After sign-in | **`/AllTippersTokens` (whole collection)** | `once()` in the messaging service |
| Diagnostics | `.info/connected`, `/Diagnostics/androidResumeProbe`, `AppConfig/resumeProbe` | probes |

### 2.2 Writes
| Path | Shape | Who |
|---|---|---|
| `AppConfig/{currentDAUComp,minAppVersion,createLinkedTipper}` | `set` | admin |
| `AllDAUComps` | leaf paths (names, URLs, `combinedRounds2` round dates, overrides); `push` for a new comp; `downloadLock` set/clear | admin |
| `Teams` | leaf paths; new team | admin |
| `DAUCompsGames/{comp}/{game}/{attr}` | leaf paths via multi-path `update` | admin |
| `AllTippers` | **leaf paths** (`updateTipperAttribute`), whole-record `push` on create only, `remove` (merge, delete) | users (own), admin |
| `AllTippers/*/compsParticipatedIn` | written as a list | admin (paid toggle) |
| `AllTippersTokens/{tipper}/{token}` | `update`, `remove`, including **other tippers' nodes** | any client |
| `AllTips` | root `update` of one path (add), `update` at game path, `remove` game, `remove` tipper node (merge) | owner, admin |
| `Stats/{comp}/live_scores_backend_v1` (HEAD) | `update` with `{game}/current` and `{game}/history/{key}` | any tipper |
| `Stats/{comp}/{game_stats_v3,live_scores_v3,scoring_audit_v3,admin_scoring_freshness_probe}` (**released 1.3.x**) | `update`, `set`, `remove` | any tipper |
| Firestore `tipLogs2` | `add` | any client |

The admin tipper screens write **leaf field paths** (not whole records) except on create, which
is what the leaf-only grant model in design D4 needs.

### 2.3 Listeners start before sign-in (new, high impact)
After config loads and before the user signs in, a post-frame callback (`main.dart:476-492`)
constructs `TeamsViewModel`, `TippersViewModel` and `DAUCompsViewModel`. Their constructors
attach listeners on `/Teams`, `/AllTippers` and `/AllDAUComps` with no `onError` on the first
two. RTDB cancels a listener that a rule denies and does not re-attach it after sign-in. Effects:
- **R1 must keep reads open.** An auth-required read would break the shipped client for any
  signed-out launch.
- **R2 needs client change D10** (start protected listeners only after sign-in and link, add
  error handling, re-subscribe on auth change).

### 2.4 Device tokens (new)
`_removeTokenFromOtherTippers` reads the whole collection and deletes a device token from other
tippers. This is a cross-user operation. (The client's `deleteStaleTokens` did the same for stale
tokens, but it had no callers and has since been removed; the backend already deletes stale tokens
after each successful fixture download and removes tokens FCM reports as dead.) Fix: server callables
plus a scheduled cleanup, no client access (design D9).

### 2.5 Firestore (new, outside RTDB)
`gametip_viewmodel.dart:431` writes every tip, including who submitted it, to `tipLogs2`.
`firebase.json` has a Firestore emulator but no `firestore` rules entry, and there is no
`firestore.rules` file. The production rules are unknown. Tracked as design D11.

### 2.6 Released clients write more than HEAD (corrected)
Revision 1 said no client writes the legacy `_v3` Stats roots. That was true of HEAD only. The
writers were retired on 2026-07-29 (commit `0970b86`, "Retire client scoring writers"), but
clients at or above `minAppVersion` (`1.3.11`) still write, as ordinary signed-in users:
`game_stats_v3` (`update`), `live_scores_v3` (`update`, `remove`), `scoring_audit_v3` (`set`) and
`admin_scoring_freshness_probe` (`set`). In the 2026 data, `scoring_audit_v3` holds 7,612 entries
written between 2026-05-28 and 2026-08-14 by 58 distinct tippers (53 non-admins; 4,024 iOS, 2,946
Android, 642 web) running 1.3.10 and 1.3.11.

Consequences: the R1 compatibility baseline is the **union of every client version that can
still reach production**, not HEAD; a rule limiting `Stats` writes to admins would have broken
ordinary users; and these allowances are removed in R2, where the new version floor excludes
those clients.

## 3. Rules semantics spike

Run with:

```bash
cd rules_test && npm install && npm test
```
(`firebase emulators:exec --only database` on a `demo-` project; no production access.)

| Id | Behaviour | Result |
|---|---|---|
| S1 | Leaf-only grants: create with role `tipper` and own uid allowed; role `admin`, other uid and unauthenticated create denied; direct write or delete of `authuid`/`tipperRole` denied; replacing or deleting an existing record denied | pass |
| S1 | Multi-location root `update()` with one denied leaf is **all-or-nothing** (permitted leaf not applied) | pass |
| S2 | A parent `.write` grant **cascades**; a child `.write: false` cannot revoke it | pass |
| S2 | A child `.validate` blocks changing a value but **not deleting it** | pass |
| S2 | A parent `.validate(hasChildren)` **does** block deleting a required child and replacing the record without it | pass |
| S2 | A blanket parent grant lets a user delete the whole record | pass (so no blanket grants) |
| S3 | Bidirectional lookup: valid mapping works; admin detected only when role is `admin`; missing index entry denies (the `child(null)` rule error evaluates to deny); a tampered index pointing at an admin record with a different `authuid` is denied; a dangling index is denied | pass |
| S4 | Kickoff lock: owner write before kickoff allowed, after denied; exact boundary behaves (write allowed at kickoff minus 1.5 s, denied after); owner delete locked after kickoff; **missing or non-numeric kickoff fails closed** | pass |
| S5 | Another tipper: per-game read denied before kickoff and allowed after; **tipper-level and comp-level reads denied even after kickoff**; owner can read own tipper node; admin can read the comp node; parent delete by owner denied, by admin allowed | pass |
| S7 | `t === now` accepts the RTDB server timestamp placeholder and rejects a client-supplied time; append-only (no overwrite, no delete) | pass |
| S8 | 4, 8, 10, 11, 20 and 40 `root.child` lookups in one rule all evaluate in the emulator | pass (see caveat) |
| S9 | A per-key public read does **not** permit the parent listener; a public-read parent does | pass |
| S10 | `auth.token.firebase.sign_in_provider` distinguishes anonymous users; `email_verified` is usable | pass |

Caveat on S8: the emulator showed no lookup limit, but production limits are not proven by the
emulator. Keep real rules to a handful of lookups per path and confirm during the post-deploy
verification.

One of my own assumptions was wrong along the way: an early version of three tests passed a
helper's return value out of `withSecurityRulesDisabled` (which returns `Promise<void>`). That was
a harness bug, fixed with a `peek` helper; the rule assertions were unaffected.

## 4. Dart spikes (empirical tests versus API inspection)

### 4.1 Compare-and-set claim (`cas_spike.dart`, 10 checks, run)

```bash
cd rules_test && firebase emulators:exec --only database --project demo-dau-rules "cd dart_spike && dart run bin/cas_spike.dart"
```

Exactly one of 25 concurrent claims wins; the slot holds the winner; a same-owner retry is
idempotent; a different owner is refused; a non-owner release is a no-op; owner release clears
it and it can be re-claimed; and three uids racing to link one record yield exactly one winner
with the index agreeing and no stray entries from the losers.

### 4.2 Identity protocol (`identity_protocol_spike.dart`, 52 checks, run)

```bash
cd rules_test && firebase emulators:exec --only database --project demo-dau-rules "cd dart_spike && dart run bin/identity_protocol_spike.dart"
```

This is the full protocol, not only a claim:
- **Placeholder replacement:** `replaceIf` on the **exact audited placeholder** succeeds; any other
  non-null value (including a different placeholder) is refused; a real uid is never replaced;
  three racing uids produce one winner; a uid already mapped elsewhere is refused and the
  original placeholder is restored (compensation).
- **Crash injection:** after **every** step of link (2 steps) and create (5 steps) the operation
  is retried; the audit is clean afterwards and exactly one record exists. A half-linked record
  is flagged by the audit and **cannot be taken over by a different uid**.
- **Conflicts:** duplicate alias and duplicate email are refused and roll back completely; four
  concurrent same-alias creates yield one winner; five concurrent taps by one uid yield one
  record.
- **Abandoned creates:** orphaned claims are flagged; the alias stays reserved while the intent is
  live; the reaper leaves a live intent alone and clears an expired one, after which the alias
  can be used again.
- **Leases:** a live lease is refused to other owners; the same owner can renew; of six
  contenders for an **expired** lease exactly one takes it over (exact-value compare-and-set).
- **Aggregator ordering:** an older computation finishing last does not overwrite a newer one,
  and 30 computations completing in random order leave the latest.

**Mutation check:** loosening the placeholder rule to "any non-UID value" makes two checks fail,
so the tests can fail.

### 4.3 What was inspected but not run
- **REST ETag `runTransaction`** (`server.dart:1326`): code read, **not executed**. The spikes
  use `firebase_dart`'s `runTransaction` (the path the Dart Admin SDK wraps). Which database
  handle the deployed callables use (`_openBackendScoringDatabase` selects REST, Admin SDK or the
  emulator client at run time) is undecided; phase 4 chooses it and re-runs these tests against it.
- **`firebase_admin` for Dart** exposes `getUser` and `getUserByEmail`: read in the package source,
  not called. The backfill uses the Node Admin SDK.
- **Service-account bypass of rules in production:** not provable in the emulator; verified by the
  post-deploy checklist.
- **Rule lookup limits in production:** the emulator showed none up to 40 lookups; unproven there.

### 4.4 Admin UID verification script (`scripts/verify_admin_auth_uids.mjs`)
Read-only; the owner runs it with credentials. It checks each admin record's `authuid` against
**Firebase Auth** (exists, verified email matches the record, not shared) so the allowlist never
depends on the database field it protects. Tested end to end against the Auth and Database
emulators with synthetic data: it classified a good admin as OK and flagged an email mismatch, a
uid missing from Auth, and a placeholder. (An early version used the removed namespaced
`firebase-admin` API and would have failed in production; the emulator run caught it.) It has
**not** been run against production.

## 5. Data findings (end-of-2026 export; aggregates only)

The export is local and gitignored (`/test/data/`). No personal data is reproduced here. The
2025 export gave the same picture for identity, so the table notes only what changed.

| Check | 2026 result | Impact |
|---|---|---|
| Tippers | 211 (34 new since 2025, none removed); 80 active in 2026; roles 207 tipper / 4 admin | |
| Records with an `authuid` | 211 of 211 | |
| `authuid` is not a Firebase UID | **40 (19%), all are email addresses**, unchanged since 2025. **Only 2 are active in 2026** (776 tips, both paid) and only 1 has a recorded login | "Claimed" must be defined by Firebase Auth (D2). The backfill risk is small: 2 active users. Placeholders also expose email addresses publicly today (D6) |
| New 2026 records | 34, all with real UIDs, all `isAnonymous: false` | New registrations already store real UIDs |
| `authuid` values shared by two records | 4 groups: 3 placeholders, **1 real UID** (one record has 12 tips and a login, the other has neither) | The real-UID pair is a trivial manual merge or delete before backfill |
| Admins | 4; none with a placeholder; none sharing a UID | |
| Persisted anonymous tippers | **0** in both exports | Confirms anonymous users are local-only |
| Records without `logon` but with `email` | 13 | Link by email must work |
| Case or whitespace-insensitive duplicate `logon` / `email` | 3 / 2 (none of the `logon` groups involve a 2026 record) | Normalise before indexing; resolve manually |
| Alias collisions under normalisation | 4 groups (3 in 2025), **1 involves a record created in 2026**; plus 2 records whose name normalises to empty | Evidence that client-side-only uniqueness lets collisions through (D2). Alias backfill needs manual resolution; reject empty normalised aliases |
| Longest alias | 27 chars | Key limits are not a concern |
| `compsParticipatedIn` | list on 108, absent on 103 | Rules must tolerate absence |
| Extra legacy fields (`active`, `tipperID`) | on 84 and 135 records | Validation must tolerate unknown fields |
| Tips | 23,025 (2026), 26,432 (2025), 28,156 (2024), 31,374 (2023). **2026: 22,982 compact `{r,t}` (`t` an integer, epoch seconds) and 43 legacy-shaped**; earlier comps are entirely legacy (25,766 of the 2024 tips also carry `legacyTip`) | Validation must accept both shapes (D5). Result values are `a` to `e` in both shapes |
| Tip nodes whose tipper is missing | 0 | |
| Tokens | 61 tokens across 55 tippers, all string timestamps, none orphaned, **none registered under more than one tipper** | Cross-tipper token cleanup is rarely needed, which supports moving it server-side (D9) |
| Games | 2,121 across 5 comps; every `DateUtc` matches `yyyy-MM-dd HH:mm:ssZ`. A new `Winner` field is written on 851 | Epoch backfill is deterministic |
| `AllDAUComps` | new fields `fixtureDownloadLock`, `aflFixtureBaseline`, `nrlFixtureBaseline` (server-written); no `downloadLock` present at export time | Admin-write regardless |
| `AppConfig` | 10 keys: `adminCheckFixtureUrlURL`, `adminScoringRescoreURL`, `cloudFunctionsBaseURL` (Cloud Run hostnames), `createLinkedTipper`, `currentDAUComp`, `googleClientId`, `minAppVersion` (`1.3.11`), `outstandingTipsPushEnabled`, `resumeProbe` (25-char nonce), `useBackendScoringBranches` | **No secrets.** `useBackendScoringBranches` is referenced nowhere in current code (dead flag). Public read is safe on current contents |
| `Stats` (2026) | `game_stats_backend_v1` (with `paid` and `free` cohorts), `round_stats_backend_v1`, `scoring_status`, `scoring_idempotency_backend_v1`, and `scoring_audit_v3` (**7,612 entries, 4.5 MB**). Earlier comps also keep `*_v2` and `*_v3` branches | See section 2.6. The audit log is large and written by clients |
| Live scores | No `live_scores_*` data in the export | Not evidence of non-use: the backend deletes a game's live scores when the official score arrives (`server.dart:1957`). D7 stays |
| Top-level `Diagnostics` node | absent | The probe is a transient REST write |

## 6. Effects on the design (all applied to DESIGN-database-rules.md v6)

1. R1 keeps **reads open** and protects writes only.
2. New **D10**: authentication-aware client startup (required for R2).
3. New **D9**: device-token callables and scheduled cleanup; no client access to tokens.
4. New **D11**: Firestore rules follow-up.
5. D2: "claimed" is verified against Firebase Auth; placeholders are overwritten on link.
6. D5: `.validate` accepts both tip shapes and tolerates unknown legacy keys.
7. D4: added required-children validation as defence in depth, based on S2.
8. D7: the aggregator must keep the `current` shape the Dart backend parses; `gameComplete`
   is not used in scoring decisions, so dropping it is safe.
9. D3: compare-and-set is proven on both Dart paths.
10. R1 baseline is every released client version at or above `minAppVersion` and it permits the
    legacy `Stats` branch writes (section 2.6); the conformance replay must cover 1.3.11, 1.4.0
    and 1.4.1.
11. D3 and the identity backfill are smaller than feared: 2 active placeholder users, 1 real-UID
    duplicate pair, 3 `logon` duplicate groups and 4 alias collision groups.
12. `AppConfig` public-read is confirmed safe; no key needs to move.
13. **Two version floors** (D, section 3 #4): `1.4.0` is an R1 compatibility floor; the R2 floor
    is a later release with all security client changes. Legacy Stats allowances are dropped from
    R1; the rules reject obsolete writes whatever the gate does.
14. **Admin allowlist (D12)** in R1 for both the rules and the Dart admin endpoints, independently
    verified, retired in R2.
15. **D3** now specifies `replaceIf` on the exact audited placeholder, durable create intents,
    leases with expiry takeover and a reaper, all proven in section 4.2. `LogonIndex` keys are
    hashes.
16. **D7** now version-guards the aggregator's write of `current` (proven).
17. **D11 / D13:** Firestore inspection is an owner action now and in this release; the update
    button must work on web and announcements include reload guidance.

## 7. Not done, and why

- **Production Firestore rules.** Not in the repo, not printable by the CLI, and deliberately not
  probed from here. The owner inspects them (design D11). Until then the pre-kickoff secrecy
  claim is open.
- **Client versions in use.** Store adoption cannot be seen from the repo. After the 1.4.0 floor
  only 1.4.0 and 1.4.1 matter; adoption still sets the length of the R2 window.
- **Admin UIDs.** The verification script is built and tested on synthetic data but not run
  against production.
- **Production rule limits, service-account bypass and the production database handle.** Not
  provable in the emulator (section 4.3).
- **R1 rule set and conformance replay.** Phase 3 in the design, not phase 1.
