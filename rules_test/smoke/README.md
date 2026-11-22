# Real-client smoke test

Runs the **released app** (default: 1.4.0 build 712) through its own UI, in a headless browser, against
the local emulators with the **R1 rules**. It answers a question the rules unit tests cannot: does
the *real client* still work under R1, and what do R1 and the real client do when a write is refused?

Everything runs inside the operating-system boundary (`../support/isolated.sh`): **no network except
loopback, no credentials, an empty Firebase config directory**. That is a strong boundary, verified by
canary tests, not a proof that no path exists; see `../README.md` for its limits.

```bash
# from rules_test/
smoke/prepare_app.sh                    # build the released app (a few minutes); records the Firebase JS SDK it needs
(cd smoke/sdk && npm install --save-exact firebase@<that version>)   # once; the only step that needs the network
smoke/up.sh                             # emulators + synthetic seed + R1 rules + servers (refuses on an SDK mismatch)
smoke/scenarios.sh                      # drive the app, assert the database after every step
smoke/down.sh
```

`up.sh r1-recovery` loads the recovery ruleset instead. Exit status 1 if any check fails.

## What is real and what is patched

The app is built from a **disposable git worktree** of the release tag under `.work/` (your working
tree is never touched). `patch_app.py` changes only startup wiring, nothing else:

| Patch | Why |
|---|---|
| Web Firebase options name the demo project `demo-dau-rules` | the copy never names production |
| App Check skipped | no reCAPTCHA or App Check traffic |
| The emulator hooks the app only enables in a debug build are enabled in this release build | so the app talks to the emulators |
| `FirebaseAuth.useAuthEmulator` added | the released app has no Auth emulator hook |

Every page, view model and write path (login linking, registration, tipping, admin edits, merge, god
mode, anonymous browsing) is the released code. 1.4.0 and 1.4.1 write exactly the same database paths.

## How it is driven, and how it stays contained

* **Browser:** `playwright-cli` with the cached headless Chromium, started and every call made through
  the OS boundary (the CLI keeps a daemon; calls from outside it could relaunch an unprotected
  browser, so none are made). Chrome's own sandbox cannot nest inside the boundary, hence
  `--no-sandbox`; the boundary is the sandbox.
* **UI:** Flutter draws to a canvas, so the test enables Flutter's accessibility layer and drives
  elements by their labels.
* **Firebase JS SDK:** the Flutter web plugin loads it from Google's CDN, which the boundary refuses
  (the first runs failed exactly this way). The app asks for the version its `firebase_core_web`
  plugin defaults to (12.18.0 for 1.4.0+712); `prepare_app.sh` reads that from the build and
  `up.sh` refuses to start unless `smoke/sdk` holds exactly that version. `route.js` serves the
  local files over loopback, **does not override the app's choice**, aborts any request for a
  different version, and the run stops if that happens. No network is involved.
* **Cleanup never kills by name or pattern.** `up.sh` starts every background process as the leader
  of its own process group and records its PID and start time; `down.sh` signals exactly those
  groups. The browser carries a unique per-run marker on its command line and the session is closed
  by name first, so another Playwright browser (or your own emulators) can never be matched.
* **Data:** synthetic (`fixture.mjs`): a fixture admin UID that is the *only* admin the loaded R1
  rules know, a normal tipper, a placeholder-backed legacy tipper (its `authuid` is an email
  address, as in the real data) and a second tipper. No real users or identifiers.
* **Assertions:** after each step `state.mjs` reads the database and Auth emulator through the Admin
  SDK, so pass/fail never depends on reading pixels. The app's `permission_denied` events are read
  from the browser console (the RTDB SDK logs them as warnings).

## Scenarios and last result

Last full run (released 1.4.0+712 web build, served exactly its Firebase JS SDK 12.18.0, R1 rules, clean seed): **43 checks, 0 failed.**

| | Scenario | What it shows |
|---|---|---|
| S1 | Fresh sign-in, normal tipper | login writes only `acctLoggedOnUTC`/`acctCreatedUTC` on the user's own record; nothing else changes |
| S2 | Placeholder-backed account (`authuid` is an email) | the client links by email and signs in; ordinary login of an existing account does not write `authuid` (registration, S3, and admin merge, S6, do, and R1 accepts those) |
| S3 | Registration | unverified email turned away; client-side alias collision check; the new record is accepted (role `tipper`, real UID, no paid comps) |
| S4 | First tip | the `{r,t}` tip shape passes R1 validation |
| S5 | Admin paid / unpaid | `compsParticipatedIn` edits by the allowlisted admin work |
| S6 | Admin merge | source record deleted, target takes identity and logon, tip moved |
| S7 | God mode | the admin writes a tip under another tipper |
| S8 | Admin role change | `tipperRole` edit by the allowlisted admin works |
| S9 | **Escalation** | a user whose database role is `admin` but who is not on the allowlist sees admin screens (the client trusts the database), and the rules refuse the write: the app reports the failed save, the SDK logs `permission_denied`, and the data is unchanged |
| S10 | Anonymous browsing | reaches Stats, no tipper record is created |
| S11 | Modified client, same SDK | 11 attacks denied, valid writes allowed, anonymous and signed-out visitors denied, and the known R1 concession (K1: editing another tipper's `logon`) is pinned |

Write the denial checks so they cannot pass vacuously: S9 asserts the app's own failure message **and** the
SDK's `permission_denied` **and** the unchanged data, because an unchanged value alone also results from a
click that never happened (the first version of S9 clicked Back instead of Save and "passed" that check).

## What a pass proves, and what it does not

It shows that **the flows listed above work** under R1 with the released client, and that **the
escalation paths exercised (S9, S11) are refused**. It does not show that all normal use works, or
that no escalation path exists; the rules tests (`../r1.rules.test.mjs`) carry the wider matrix.

## What is not covered

* **The backend.** Only the Auth, Database and Firestore emulators run, not Functions. Fixture
  download, rescore and the other admin endpoints are therefore not exercised against the Dart
  allowlist change; the backend unit tests are the pre-deployment evidence and these are explicit
  post-deployment checks (`../../DESIGN-database-rules-phase3.md`, section 6).
* **Device token registration and reassignment.** Web push needs a service worker and Google's
  messaging servers, so no token is ever registered in this browser. Those writes are covered at the
  rules level (`r1.rules.test.mjs`), not by the real client.
* **iOS and Android builds**, and the Google and Apple sign-in flows (email/password and anonymous
  only). The write paths are shared Dart code, but the platform shells are not exercised.
* **1.3.x clients.** Their legacy writers are covered by the rules tests and by the modified-client
  matrix (S11), not by running that build.
* The headless browser is software-rendered and the UI is driven through the accessibility layer, so
  steps rely on timing and labels. One run hit a browser-tab crash that did not reproduce.
