# Android Realtime Database Resume Staleness

**Status:** Unresolved, with a successful instrumented reproduction and completed independent review. Build 708 captured the failure end to end on a physical Pixel and showed that only a new Android process restored the games stream. The next candidate adds instrumentation only; no further recovery behavior has been selected.

**Report updated:** 5 September 2026

**Testing after 6 September 2026:** the comp closes and organic score changes stop, but the defect remains fully reproducible using self-authored writes to a dedicated test node or test competition. One boundary does break: cards constructed after the final round completes never subscribe to games updates, so the widget-level check silently stops being meaningful — most importantly after a cold start. Read *Post-season testing* before designing the next reproduction.

## Executive summary

After the app remains in the background for an extended period, an Android client can resume with stale Firebase Realtime Database (RTDB) state and continue displaying it. An instrumented release build reproduced the fault on a physical Google Pixel after an approximately 11-hour-51-minute background interval. The affected Friday fixtures had no crowd-sourced scores, the iOS client already showed the finalized official scores, and the Pixel continued to show missing official results.

The retained trace shows that the lifecycle handler ran, but `/.info/connected` remained `false`. Each resume pipeline exhausted all three 10-second `goOffline()`/`goOnline()` reconnect waits and then executed the fixture `get()`. Those reads returned the stale persisted snapshot in 18-50 ms, which `GamesViewModel` applied and the Tips widgets rendered correctly. Eight resume pipelines, a confirmed external `/AppConfig` probe, normal foreground use, and an Android Airplane-mode network transition did not refresh the games data.

After a Settings-level **Force stop**, a new process first emitted the same stale persisted games snapshot, then received the finalized server snapshot about 2.14 seconds later. This is the first captured stale-to-fresh comparison. It rules out the lifecycle gate, model application, and widget presentation as the primary failure in this reproduction, and narrows the problem to games-path synchronization state retained by the old Android process.

This is now confirmed to persist after both resume-related fixes:

1. Build 700 added an explicit fixture read when the app resumed.
2. Build 702 added an Android-only RTDB transport restart, waited for `/.info/connected`, and then performed the same fixture read.

Both approaches are covered by unit tests, but neither has demonstrated the required stale-to-fresh transition on a physical Android device after a long background interval. No further fix should be attempted until the next investigation establishes which part of the runtime path is failing.

## Field reports

### Original report against build 700

- Wake an Android client that had been in the background.
- The UI was immediately rendered from stale RTDB data.
- The client did not appear to receive or process newer backend data that should have refreshed the UI.
- Build 700 behaved the same as the versions before the first resume fix.

### Earlier report after the Android reconnect fix

- Device: physical Google Pixel.
- Background duration: several days.
- On resume, the Tips page continued to show live/interim scores for Saturday's games.
- At the same time, the iOS app showed the finalized fixture scores for those games.
- The Android app did not self-correct through normal use.
- Force-quitting and reopening the Android app loaded the finalized state.

The exact Android build number, Pixel model, Android version, battery-optimization settings, and background duration were not captured in that earlier report. The later instrumented reproduction below captured the build and background interval, but the Pixel model variant, Android version, and battery/background-restriction settings remain to be recorded.

## Instrumented physical-Pixel reproduction — 4-5 September 2026

### Test conditions

- Device: physical Google Pixel; exact model and Android version were not recorded.
- App: release-mode diagnostic build `1.4.0+708`.
- Process under test: `android-1788527640452948`.
- RTDB competition key: `-OlgMBuUZb3lUFu-MqNC`.
- App process started: `2026-09-04T13:14:00.554113Z`.
- App backgrounded: `2026-09-04T13:14:45.411667Z`.
- First failing resume: `2026-09-05T01:05:39.962459Z`, approximately 11 hours 51 minutes later.
- The reporter stated that the Friday games had finalized approximately nine hours before observation.
- The iOS client showed finalized scores at the same time.
- The affected games had no crowd-sourced/live scores. This removed live-score reconciliation as a possible source of the stale presentation.

The principal affected fixtures in the trace were:

| Game key | Stale Android value | Final value after cold start |
| --- | --- | --- |
| `nrl-27-198` | official scores `null` / `null` | `20` / `24` |
| `nrl-27-199` | official scores `null` / `null` | `50` / `20` |
| `afl-26-212` | official scores `null` / `null` | `107` / `74` |

### Controlled sequence and observations

| Step | Action | Observation |
| --- | --- | --- |
| 1 | Resume the long-backgrounded Pixel and inspect the Tips page. | The games were rendered as `startedResultNotKnown`, with null official and displayed scores and `liveScoreCount: 0`. |
| 2 | Allow the build-708 resume pipeline to run without intervention. | `/.info/connected` reported `false`; three reconnect attempts each timed out after 10 seconds; the fallback games `get()` returned stale values in 26 ms and reapplied them. |
| 3 | Repeat foreground/background captures while preserving the process. | The same pattern repeated. Across the complete experiment, eight resume pipelines in the old process made 24 timed-out reconnect attempts. None logged `connected: true` or a fresh games-listener snapshot. |
| 4 | Load/refresh a current web page in Chrome, return to Dau, and wait. | The Tips scores remained stale. The general-network check was not separately instrumented in the Dau trace, so its result relies on the reporter's execution of the workflow. |
| 5 | Add an inert `resumeProbe` child under `/AppConfig` from the backend while the Pixel remained on the stale Tips page. | At the exact confirmed probe timestamp, `2026-09-05T01:25:52Z`, all Tips game widgets rebuilt with no resume attempt or games-model notification. They rendered the same stale values. The diagnostic build did not log ConfigViewModel snapshots directly, so attribution to the probe is timestamp correlation, albeit confirmed by the reporter. |
| 6 | Turn Airplane mode on for 10 seconds, turn it off, restore connectivity, background and reopen Dau, and wait. | Two further resume attempts still reported `connected: false`, exhausted all reconnect retries, received no games-listener event, and returned the stale games snapshot from `get()` in 27 ms and 26 ms. |
| 7 | Force-stop Dau through Android Settings without clearing cache or storage, then relaunch it. | A new process was created. It first rendered persisted stale data, then received and rendered the finalized scores roughly two seconds later. |

The repeated old-process fixture reads were extremely fast despite the SDK reporting disconnected. Representative completions were 18-50 ms, including 26 ms on the first captured failure, 27 ms after the network transition, and 50 ms immediately before force stop. That timing, the absent connection event, and the unchanged values are consistent with cache fallback rather than a successful server round trip.

All eight old-process attempts had the same connection and data outcome:

| Attempt | Started UTC | Failed reconnects | `connected: true` observed | Approx. games `get()` time | Affected scores returned |
| --- | --- | ---: | --- | ---: | --- |
| 1 | `01:05:39.962` | 3 | No | 26 ms | null / null |
| 2 | `01:07:28.446` | 3 | No | 31 ms | null / null |
| 3 | `01:15:36.653` | 3 | No | 25 ms | null / null |
| 4 | `01:20:01.218` | 3 | No | 20 ms | null / null |
| 5 | `01:23:39.950` | 3 | No | 18 ms | null / null |
| 6 | `01:31:10.324` | 3 | No | 27 ms | null / null |
| 7 | `01:32:37.188` | 3 | No | 26 ms | null / null |
| 8 | `01:36:26.275` | 3 | No | 50 ms | null / null |

### Decisive cold-start boundary

Immediately before force stop, the old process completed resume attempt 8:

```text
01:36:26.274Z  attempt_started (old process)
01:36:26.285Z  sdk_reported_connection_state: false
01:36:59.818Z  third reconnect timed out; retries exhausted
01:36:59.868Z  fixture_get_returned: affected official scores still null
01:36:59.906Z  GamesViewModel applied the stale resume_get snapshot
```

The process was then force-stopped and relaunched:

```text
01:37:14.832Z  process_started (new process android-1788572234816239)
01:37:15.006Z  initial listener snapshot/model application used persisted stale values
01:37:17.155Z  games listener received finalized values
01:37:17.158Z  GamesViewModel applied finalized values and notified listeners
```

Fresh data therefore arrived approximately 2.32 seconds after process start and 2.14 seconds after the initial stale listener snapshot. The reporter observed the Tips scores change at approximately the same time.

### Boundaries established by this reproduction

| Boundary | Result |
| --- | --- |
| Android lifecycle callback and coordinator gating | Worked: every qualifying return logged a complete resume attempt. |
| Android reconnect helper | Failed: `goOffline()`/`goOnline()` never produced `/.info/connected == true` in the retained process. |
| Explicit fixture `get()` | Completed but returned the old games snapshot while disconnected. |
| Games listener in the retained process | Never delivered the finalized fixtures during the observed failure. |
| `GamesViewModel` snapshot application | Worked: it accurately applied the snapshot it was given, whether stale or fresh. |
| Tips presentation | Worked: widgets accurately rendered null stale values and later the finalized cold-start values. |
| Live/crowd-score reconciliation | Not involved: `liveScoreCount` was zero for the affected fixtures. |
| Android network transition | Did not repair the retained process. |
| New Android process | Recovered: stale disk cache was followed by a fresh listener snapshot within about two seconds. |

### What this confirms—and what it does not

This reproduction confirms that build 708's resume mitigation does not repair the failing process. It also confirms that the failure is upstream of `GamesViewModel` application and widget rendering: no finalized games snapshot reached those layers until process recreation.

The `/AppConfig` probe adds an important qualification. A backend config mutation was followed at the same timestamp by a full UI rebuild, while the games listener remained silent. This suggests that the process was not uniformly incapable of reacting to all RTDB-backed state. However, because the diagnostic build did not record the config snapshot itself or retain native logcat, the next reviewer should treat this as strong correlated evidence rather than direct proof of a healthy shared RTDB transport.

The evidence does **not** yet identify whether the retained fault is:

- a native games query/listener registration that has become stuck;
- broader native RTDB connection state with unusual local/config-event behavior;
- a Dart subscription that remains present but is no longer represented correctly in the native sync tree;
- an authentication, App Check, DNS, or token-refresh condition visible only in native logs; or
- a FlutterFire/native SDK defect matching one of the upstream reports.

It does show that repeatedly calling `goOffline()`/`goOnline()` on the same `FirebaseDatabase` instance, waiting for `/.info/connected`, issuing `get()` on the listened games path, and inducing an Android network transition are not sufficient recovery mechanisms for this captured state.

## Expected behavior

When the app returns to the foreground, finalized fixture data already present in the backend should replace any older live/interim scores. The Tips page should update without requiring a force quit, regardless of how long the process has been backgrounded.

## Attempt 1: explicit fixture refresh on resume

**Shipped in:** build 700
**Primary commit:** `7572556` — `Refresh fixture data after app resume`

The first fix added a lifecycle coordinator to the root app widget. After a genuine background-to-resumed transition it:

1. Waited 500 ms.
2. Called `DAUCompsViewModel.refreshFixtureDataFromServer()`.
3. Delegated to `GamesViewModel.refreshFromServer()`.
4. Read the configured games path with `DatabaseReference.get()`.
5. Rebuilt the in-memory game list from the returned snapshot and notified listeners.

The coordinator also prevented overlapping refreshes and retried errors classified as transient RTDB disconnects after one and two seconds.

Relevant code:

- `lib/services/app_resume_refresh_coordinator.dart`
- `lib/main.dart`
- `lib/view_models/daucomps_viewmodel.dart`
- `lib/view_models/games_viewmodel.dart`

Tests added for this attempt verified lifecycle gating, retries, single-flight behavior, and that a fixture snapshot containing finalized scores updates the `GamesViewModel`. They did not exercise a native Android Firebase client, Android background suspension, disk persistence, or a stale-to-fresh transition against a real backend.

### Why attempt 1 was insufficient

The physical-device report from build 700 showed that an explicit `get()` did not guarantee a fresh UI in this runtime condition. The Firebase API can fall back to locally cached data when a server value cannot be obtained, so the read alone was not proof that the resumed client had re-established a healthy server connection. The test doubles always returned the supplied snapshot and could not reproduce the suspected native connection/cache state.

An earlier review suggested that `get()` always trusts an attached listener's cache. That should not be treated as established fact: the Android Firebase documentation describes `get()` as attempting the server and falling back to cache if necessary. The unresolved question is what the FlutterFire/native client actually did in this long-background scenario.

## Supporting change: live-score reconciliation

**Primary commits:**

- `c8f6cb7` — `Refresh game cards from live scores`
- `787fff6` — `Fix live score reconciliation after fixture refresh`

The Stats view model maintains live scores separately from the canonical fixture list. A fixture refresh replaces `Game` instances, so supporting work was added to:

- listen for `GamesViewModel` changes;
- reconcile cached live scores onto the current game instances;
- clear live scores that have disappeared; and
- ignore stale live scores when both official fixture scores are present.

Tests verify that live scores update current game cards and that stale live scores do not override a fixture with complete official scores. This work protects the UI once fresh fixture data reaches the in-memory games model; it does not establish that the Android client obtained that fresh fixture data after resume.

## Attempt 2: restart the Android RTDB connection before refreshing

**Shipped in:** build 702
**Primary commit:** `c9a7531` — `fix(android): resync realtime database on resume`

The second fix retained the explicit fixture refresh and inserted an Android-only connection reset before it:

1. Call `FirebaseDatabase.goOffline()`.
2. Call `FirebaseDatabase.goOnline()`.
3. Subscribe to `/.info/connected` and wait until it reports `true`, with a 10-second timeout.
4. Retry the reconnect after one and two seconds if it fails.
5. Continue to the fixture refresh even if all reconnect attempts fail.
6. Run the existing games-path `get()` and apply its snapshot.

The lifecycle coordinator was also tightened so an `inactive` event alone does not count as having entered the background. The intended runtime flow is now:

```text
Android background -> resumed
    -> 500 ms delay
    -> RTDB goOffline/goOnline
    -> wait for /.info/connected == true
    -> read fixtures with get()
    -> replace GamesViewModel games
    -> notify listeners
    -> StatsViewModel reconciles live scores
    -> Tips page rebuilds
```

Relevant code:

- `lib/services/app_resume_data_refresher.dart`
- `lib/services/app_resume_refresh_coordinator.dart`
- `lib/services/configured_realtime_database.dart`
- `lib/main.dart`

Tests added for this attempt verify:

- the reconnect happens before the fixture refresh on Android;
- reconnect is skipped on iOS;
- reconnect retries are bounded;
- reconnect failure does not prevent the fixture refresh;
- `goOffline()` precedes `goOnline()`;
- the helper waits for `/.info/connected == true` and times out otherwise; and
- an `inactive`-only lifecycle sequence does not trigger the refresh.

These tests compile and pass, but they use mocks and controlled streams. They do not prove that native RTDB listeners have resynchronized, that the subsequent fixture read is fresh, or that the Android UI has consumed the new state after a multi-day suspension.

## What the earlier uninstrumented observation suggested

The Tips game card displays the interim-score banner only when crowd-sourced/live scores exist and at least one official fixture score is missing. When both official scores exist, the official values take precedence and stale live scores are ignored by the reconciliation logic.

The symptom suggested that the Android in-memory `Game` still lacked at least one finalized official score after resume. It was less consistent with a simple repaint failure or a stale live-score overlay on top of an otherwise current fixture.

Before instrumentation, force quit only narrowed the fault toward state retained across Android background/resume. At that point the evidence did not distinguish among:

- the expected lifecycle callback never running;
- the coordinator deciding no background transition occurred;
- the registered view model not being ready or not being the instance used by the visible page;
- RTDB reporting connected before the required data was synchronized;
- `get()` returning old persisted data or otherwise not delivering the current server snapshot;
- the fresh snapshot arriving but being dropped or overwritten by a later stale listener event;
- listeners failing to resume or being attached to stale state; or
- the model updating without the visible Tips dependency rebuilding.

The build-708 reproduction has now resolved most of these alternatives for the captured incident: the handler ran; `get()` returned stale values; no fresh games event arrived; the model applied exactly what it received; no rollback occurred; and the widgets rendered the model accurately. The unresolved boundary is inside or immediately below the retained games subscription/native RTDB synchronization state.

## Known gaps after the instrumented reproduction

1. **No native logcat from the failure window.** Native RTDB logging was enabled, but the phone was not attached to ADB. The durable JSON trace therefore lacks native connection, authentication, App Check, DNS, token-refresh, and sync-tree details.
2. **~~The resolved native Android SDK version is not recorded.~~ Resolved.** An earlier revision of this report stated `firebase_database` 12.4.2; that was wrong. Verified against `pubspec.lock` at build-708 commit `0c4bf52` and the resolved plugin sources, build 708 used:

   | Component | Version |
   | --- | --- |
   | `firebase_database` (Dart) | 12.5.0 |
   | `firebase_core` (Dart) | 4.14.0 |
   | Firebase Android BoM | 34.18.0 |
   | `com.google.firebase:firebase-database` (native) | 22.0.1 |

   The BoM is set by `FirebaseSDKVersion=34.18.0` in the `firebase_core` plugin's `android/gradle.properties`, and the project does not override it; the native `firebase-database` version follows from that BoM. The remaining task is to compare these versions against upstream defect reports and release notes, not to determine them.
3. **The config probe is correlated rather than directly traced.** The exact probe timestamp matches an otherwise unexplained full widget rebuild, but build 708 does not record ConfigViewModel snapshots or the probe value.
4. **Games subscription generations are not logged.** The trace shows no games event, but does not identify the native listener registration/generation or prove whether it remained registered below the Dart subscription.
5. **Other long-lived RTDB listeners were not individually traced.** The config result suggests non-uniform behavior, but Tips, Stats, and Tippers stream health was not recorded at the same boundary.
6. **Device conditions remain incomplete.** Exact Pixel model, Android version, battery optimization, background restriction, network type, VPN, and Private DNS settings were not recorded.
7. **The current failure fall-through remains misleading.** After approximately 33 seconds of failed reconnect attempts, the code continues to a cache-capable `get()` and reports the fixture refresh as completed even though no connection was established.
8. **Mocks cannot reproduce this state.** Existing tests establish call order and application behavior, but not native Android process retention, persistence, or listener recovery.
9. **The widget boundary stops being observable for newly built cards once the season ends.** `GameTipViewModel` decides once, in its constructor, whether to subscribe to `GamesViewModel`, and that decision is false for instances constructed after the final round completes. Existing instances keep working; new ones — notably every card in a process created by a cold start, which is how the September stale-to-fresh transition was proved — do not. A widget-level null result then fails to distinguish a broken fix from a subscription that was never created. See *Post-season testing* for the required workaround. This did not affect the September reproduction, which failed upstream of the model.

## Independent read-only audit

An independent agent reviewed the current implementation and history without changing code. Its highest-priority hypothesis is that build 702 may be invoking the same failing native Android reconnect operation rather than repairing it.

Two upstream reports closely resemble the observed pattern:

- [FlutterFire issue #17769: Realtime Database fails to reconnect on Android](https://github.com/firebase/flutterfire/issues/17769)
- [Firebase Android SDK issue #7549: Realtime Database cannot reconnect](https://github.com/firebase/firebase-android-sdk/issues/7549)

Those reports describe Android clients that remain disconnected after backgrounding or an explicit disconnect, where `goOnline()` does not restore `/.info/connected` and an app restart does. They were closed without a demonstrated SDK fix, so they are supporting evidence for a hypothesis, not confirmation that this app has the same defect.

~~The dependency lock currently resolves `firebase_database` 12.4.2.~~ **Corrected:** build 708 resolved `firebase_database` 12.5.0 on native `firebase-database` 22.0.1 via Firebase BoM 34.18.0 — see *Known gaps* item 2 for the verified table. The next investigation should compare that specific native version's behavior with the upstream reports. The official Android [`Query.get()` documentation](https://firebase.google.com/docs/reference/android/com/google/firebase/database/Query#get()) is also important: it describes a server request that may fall back to local cache when the client cannot obtain server data. That behavior fits the masked-failure path above.

Before device telemetry, the audit ranked the hypotheses as follows:

1. Native Android RTDB connection remains stuck; all reconnect waits fail, then the fixture read falls back to stale persisted data.
2. The lifecycle coordinator never sees the required background event, so no resume work runs.
3. The explicit refresh gets current data but a stale listener event subsequently rolls the model back.
4. The model becomes current but the visible game-card/view-model chain does not rebuild from it.

The build-708 reproduction strongly supports hypothesis 1 for this incident. It directly rules out hypothesis 2, found no evidence for hypothesis 3, and rules out hypothesis 4 as the primary cause because the same widgets rendered finalized values as soon as a fresh cold-start snapshot reached the model.

## Relevant older history

This area has had several Android RTDB lifecycle/persistence experiments, including commits `55a21bf`, `4528d3f`, `2eeb0e1`, and `6be3232`. Earlier versions also resubscribed individual view models on lifecycle resume before that observer-based approach was later removed. The next investigator should review those diffs for previously observed failure modes, but should not assume they describe the present bug.

## Second independent read-only analysis (30 August 2026, corrected)

*This section was reviewed by a third party across two rounds after its first version was written. Those reviews found real errors — a flawed proposed test, two overstated citations, an unsupported claim that two hypotheses "collapse" into one, and an incorrect open/closed status for two upstream issues. The text below is corrected accordingly; the retracted claims are kept visible, struck through, rather than silently removed.*

A second agent reviewed the current code (`lib/services/app_resume_refresh_coordinator.dart`, `lib/services/app_resume_data_refresher.dart`, `lib/services/configured_realtime_database.dart`, `lib/main.dart`, `lib/view_models/games_viewmodel.dart`, `lib/view_models/gametip_viewmodel.dart`) without changing it, and searched for upstream reports against `firebase_database`/FlutterFire/the native Android SDK. Its surviving contribution is narrow: one concrete mechanism the existing hypotheses had not named precisely (unconfirmed), and a corrected reading of the upstream issue corpus — which turns out to be thinner corroboration than this section first claimed. It does not change the report's priority ordering or its conclusion that device evidence must come before another fix.

### A more specific version of hypothesis 1: `get()` is called on the same reference that already has a live listener attached

`GamesViewModel` attaches a persistent `.onValue` listener to the games path once, in `_listenToGames()` (`lib/view_models/games_viewmodel.dart:74-81`), when the view model is constructed:

```dart
_gamesStream = _db.child(_gamesPath).onValue.listen((event) {
  _queueGamesSnapshotProcessing(event.snapshot);
});
```

`refreshFromServer()`, which both resume fixes ultimately call, then does:

```dart
Future<void> refreshFromServer() async {
  await _teamsViewModel.initialLoadComplete;
  await _dauCompsViewModel.initialDAUCompLoadComplete;
  await _applyGamesSnapshot(await _db.child(_gamesPath).get());
}
```

`_db.child(_gamesPath)` is the *same location* the long-lived listener is already attached to, and `_db` is the single shared `configuredRealtimeDatabase` instance. Firebase Realtime Database's `get()` is documented to fall back to local cache when it "is unable to return the server value" — but the more specific behavior worth verifying is that when a location already has an active listener, several Firebase engineers and issue threads describe `get()` as short-circuiting to that listener's already-synced value rather than always forcing a fresh round trip, on the theory that an active listener is assumed to be current. Search did not turn up an unambiguous, quotable sentence to that exact effect in the currently published docs (the official pages we could fetch only state the "falls back to cache if the server value can't be obtained" behavior), so **this should be treated as a hypothesis to instrument and confirm, not an established fact** — same evidentiary bar the rest of this report holds itself to.

If true, it means attempt 1 and attempt 2's "explicit fixture refresh" was never actually capable of proving freshness independent of the pre-existing `_gamesStream` listener: it reads through the same subscription.

~~That reframes the open question from "why didn't the explicit `get()` refresh get the server value" to "why didn't the pre-existing listener resync after the native connection reset" — i.e. hypotheses 1 and 2 in the existing audit collapse into a single question about the *listener's* resync, not the explicit read.~~ **Retracted.** A third-party review correctly pointed out this does not follow: "a stuck native connection" (hypothesis 1) and "the lifecycle coordinator never sees the required background event, so no resume work runs at all" (hypothesis 2) remain distinct and independently falsifiable — the second one never reaches `get()` or the listener at all. The `get()`/active-listener mechanism above is at most a refinement of hypothesis 1, not a merger of 1 and 2.

~~**Suggested test:** on resume, in addition to the existing `get()` call, issue a `get()` against a freshly created `DatabaseReference`/`FirebaseDatabase` path with no attached listener...~~ **Retracted — this test was wrong as proposed.** A new `DatabaseReference` object for the same path, obtained from the same `FirebaseDatabase`/`FirebaseApp` instance, is not an independent read: the Dart `DatabaseReference` is a thin locator, and the native SDK keys its sync tree and listener bookkeeping by path within one database instance, not by which Dart object made the call. Constructing another reference to `_gamesPath` off the same `_db` would still be routed through whatever state the existing listener has. A genuinely independent read would require a second `FirebaseApp`/`FirebaseDatabase` instance pointed at the same database URL — an experiment worth weighing against its own complexity and cost, not a free instrumentation add.

### The long-lived `_gamesStream` subscription is never recreated across resume

Both shipped fixes only call `goOffline()`/`goOnline()` on the shared `FirebaseDatabase` instance (`lib/services/configured_realtime_database.dart:44-55`) and then issue one `get()`. They never cancel/recreate `GamesViewModel._gamesStream` itself (contrast with `saveBatchOfGameAttributes()`, which does exactly that around writes). If the native listener object attached at app start is the thing left in a stuck/zombie state after a long background period, a database-level `goOffline()`/`goOnline()` cycle restoring `/.info/connected` does not by itself guarantee that *this specific listener* has resynced. Force-quitting fixes it because a cold start creates a brand-new listener object with no stale state to inherit.

**Proposed experiment (behavioral, not passive instrumentation — flagging that distinction per review feedback):** on resume, cancel and recreate `_gamesStream` before the fixture refresh, and log whether that changes the outcome. This is weak evidence either way on its own: the reporter on flutterfire#2590 (cited below) is reported to have said that cancelling and recreating subscriptions around pause/resume did **not** fix their equivalent failure — that detail comes from a reviewer's reading of the thread and has not been independently verified here — so a negative result would not rule out a stuck-listener mechanism, only this specific mitigation for it. Treat it as one input to the broader device-telemetry investigation the report already calls for, not a standalone diagnostic.

### Upstream evidence: some corroboration, correctly narrower than first stated

The original version of this section cited four upstream issues as equivalent evidence. A third-party review correctly flagged that they are not all the same failure mode; the corrected list:

- [FirebaseExtended/flutterfire#2590 — cannot restore RTDB connection after backgrounding; only a full app kill/restart recovers it](https://github.com/FirebaseExtended/flutterfire/issues/2590) — the strongest match. Same product (Realtime Database), same trigger (backgrounding), same workaround (force restart). **Closed** 2020-05-20 — the same day it was opened, carrying the label `blocked: customer-response`, with no demonstrated fix.
- [firebase-android-sdk#5510 — Realtime Database connection lost on Wi-Fi disconnect/reconnect and does not recover on its own](https://github.com/firebase/firebase-android-sdk/issues/5510) — same product, a related but distinct trigger (network transition rather than backgrounding specifically). **Closed** 2023-11-10, no demonstrated fix.
- ~~[firebase-android-sdk#2970 — Realtime Database repeatedly connects/disconnects every ~2 minutes while backgrounded]~~ **Correction:** on closer reading this issue's root cause was traced to the reporter's own code calling `DatabaseRef.get()` from a periodic ~30-minute `WorkManager` job alongside a long-running foreground service, not a plain background/resume cycle. It shows RTDB connection handling can be fragile under background conditions in general, but it is not a close match to this app's scenario and should not have been presented as equivalent-strength evidence.
- ~~[flutterfire#6355 — Firebase taking too long to reconnect after returning from background]~~ **Correction:** this issue is about **Cloud Firestore**, not Realtime Database — its errors are Firestore/DNS resolution failures (`Unable to resolve host firestore.googleapis.com`), and it is filed under `firebase_core` covering cross-SDK network setup, not the RTDB client. It is at best indirect evidence that Android background/DNS conditions can disrupt long-lived Firebase connections in general; it should not have been cited as if it were an RTDB-specific report.

~~...both still open with no confirmed root-cause fix from Firebase.~~ **Retracted — this was wrong.** A third-party review flagged that #2590 and #5510 are both closed, not open. Verified via the GitHub API, and the correction extends to every upstream issue this report cites, including the two in the original audit above:

```text
flutterfire#2590             closed 2020-05-20   (opened and closed same day)
firebase-android-sdk#5510    closed 2023-11-10
firebase-android-sdk#7549    closed 2025-11-17
flutterfire#17769            closed 2025-11-20
```

**Reading these states correctly matters.** The GitHub API reports `state_reason: completed` for all four, but that is the default for *any* manual close and is not a fix signal — it does not distinguish a resolved defect from a triage or stale-bot close. #2590 is the clearest case: closed the same day it was opened, under `blocked: customer-response`. None of the four carries a linked fix commit or PR, which is consistent with the original audit's own careful wording that #7549 and #17769 "were closed without a demonstrated SDK fix."

The corrected state of the upstream evidence is therefore weaker than either version of this section implied: four closed issues, none with a demonstrated fix, of which only one (#2590) closely matches this app's symptom. That is enough to say the defect class is real and recurring, and enough to say a Dart-level `goOffline()`/`goOnline()` retry loop cannot be assumed to succeed where a near-identical report shows it did not. It is **not** enough to justify another speculative behavioral change. If anything it argues the opposite: the upstream corpus cannot settle this, so the next move must be first-party evidence captured on the affected device.

At the time this section was written, that account still required device evidence. The 4-5 September build-708 reproduction now confirms the observable sequence: the retained process remains SDK-disconnected during the resume attempts, the cache-capable `get()` supplies stale data, and a new process receives a fresh games-listener snapshot. It still does not establish the internal native cause or prove the narrower active-listener short-circuit mechanism proposed above.

## Independent review outcome

The independent review agreed that the next build should remain in diagnosis mode and corrected three overstatements made while interpreting the first trace:

1. The build-708 `/.info/connected` observer ended with each resume pipeline. It was not running when the `/AppConfig` probe was written 99 seconds after attempt 5, so the trace does not prove that the config event occurred while the SDK reported disconnected. The old client retained state that prevented games synchronization, but the evidence does not yet distinguish games-listener state from shared transport state.
2. The post-season `GameTipViewModel` subscription decision is per instance and is made at construction. Existing instances keep listening; instances created after the completion threshold never start listening. This matters most on the cold-start comparison leg.
3. Build 708's resolved versions are `firebase_database` 12.5.0, `firebase_core` 4.14.0, Firebase Android BoM 34.18.0, and native `firebase-database` 22.0.1.

The agreed next experiment is therefore a continuously observed connection state plus backend-written nonces on both an existing listener and a newly attached listener. The trace must also record observer attachment and cancellation so readers can see exactly which time windows contain connection evidence. No further production behavior change should be selected merely from the fact that force stop works. Process recreation resets several layers at once; the smallest failed layer still needs to be identified.

## Diagnostic implementation used in the reproduction

The instrumentation is disabled by default and activates only in an Android build compiled with:

```text
--dart-define=ANDROID_RESUME_DIAGNOSTICS=true
```

The Android CI workflow enables this flag for APK and AAB artifacts built from `testing` and explicitly disables it for builds from `main`. Consequently, the Google Play internal-track build contains the diagnostic recorder and admin export page, while the production build does not.

The diagnostic build retains build 702's reconnect timing, retries, failure fall-through, and fixture refresh behavior. It adds:

- a process identifier and correlated resume-attempt identifier;
- every lifecycle decision made by `AppResumeRefreshCoordinator`;
- a short-lived `/.info/connected` observer attached when the qualifying resume starts, before the existing 500 ms delay;
- the most recent SDK-reported connection value and its age when `goOffline()` is about to run;
- reconnect attempt completion, failure, and final fall-through;
- the explicit fixture `get()` result for games within the recent eight-day window;
- listener snapshots received during and after the attempt, with late events left unattached but timestamped for correlation;
- the applied in-memory game values and `GamesViewModel` notification boundary;
- the score and banner values observed by visible Tips game cards, including throttled unattached observations after the attempt window; and
- native RTDB verbose logging for an attached Android log capture.

Events are serialized in order and appended one record at a time to an on-device JSONL file. The recorder does not re-encode or rewrite the retained buffer for each breadcrumb. On the next process start it removes unreadable or expired records and enforces the 5,000-event safety limit, evicting the oldest non-anomalous records first. Normal events are retained for 14 days; anomalous events and every event belonging to an anomalous attempt are retained for 30 days. Force-quitting does not clear the trace; the next process appends a new `process_started` event after startup pruning.

Admins can open **Android Resume Diagnostics** from the Profile admin options and copy the newline-delimited JSON trace. The panel is absent when the compile-time flag is disabled.

The connection observer is not passive. Attaching any RTDB listener may influence native connection activity, and the pre-reconnect observer is a real behavioral delta from the failing production build. The first capture question is therefore **"does the stale-data problem still reproduce with diagnostics enabled?"** The trace explicitly records `connection_observer_attached`, and its values are named `sdk_reported_connection_state`; they represent the SDK's local belief, not independent proof that the socket or data listeners are healthy. If the problem does not reproduce, that run cannot be treated as evidence that the production issue is fixed.

No conditional reconnect, listener recreation, second Firebase app, retry change, or other proposed mitigation is included in this diagnostic change.

### Build-709 diagnostic experiment

The build-709 candidate extends the recorder without changing recovery behavior:

- every resume-attempt connection observer records its generation, attachment, cancellation request, successful cancellation, error, and unexpected completion;
- every games listener records a generation across attachment, snapshot receipt, model application, error, completion, cancellation request, and successful cancellation;
- the existing `/AppConfig` listener records only whether `resumeProbe` is present and its value, avoiding unrelated config values;
- the diagnostics page can manually attach an extended `/.info/connected` observer and a fresh listener at `/Diagnostics/androidResumeProbe`;
- both extended subscriptions share a probe identifier and generation, and record their complete attachment/cancellation lifetime; and
- the client never writes either probe value. Both nonces must be written externally from the backend or Firebase console.

The extended probe is deliberately manual. Do not start it before the long background interval: adding listeners could influence RTDB connection activity and suppress the fault being investigated. Use this sequence:

1. Leave the diagnostic build in the background long enough to reproduce the stale-data state.
2. Resume and confirm that the games UI is stale. Do not force-stop the app.
3. Open **Android Resume Diagnostics**, copy the trace as a before-state, and press **Start probe**.
4. From the backend, write a unique **bare string or number** nonce to `/Diagnostics/androidResumeProbe`. Do not write a map or list: the recorder deliberately replaces structured probe values with their type name to keep the trace bounded.
5. Write a different unique bare string or number nonce to `/AppConfig/resumeProbe`.
6. If the selected competition is a dedicated test competition, change a known test fixture's official score to a unique test value. Do not mutate a canonical production or historical fixture. The games-listener trace records the received score and generation.
7. Wait at least one minute without triggering another resume pipeline, reload the diagnostics page, press **Stop probe**, and copy the complete trace.
8. Only after the trace is safely copied should the process be force-stopped for the cold-start comparison.

Interpret the simultaneous probe window as follows:

| Extended connection state | Fresh diagnostic listener | Existing config listener | Existing games listener | Interpretation |
| --- | --- | --- | --- | --- |
| `false` throughout | no nonce | no nonce | no update | Supports a shared retained transport/client failure. |
| `false` throughout | receives backend nonce | no backend nonce | no update | The connection indicator is contradicted by confirmed server delivery. New work succeeds while existing registrations remain stale. |
| `false` throughout | receives backend nonce | receives backend nonce | no update | The connection indicator is contradicted by confirmed server delivery; the existing config registration is alive and the games registration is specifically stale. |
| `false` throughout | receives backend nonce | receives backend nonce | receives test score and UI updates | The connection indicator is contradicted by confirmed server delivery and cannot be used as the recovery gate in this state. |
| `true` or transitions to `true` | receives nonce | receives nonce | no update | Supports a games-listener or games-query registration failure. |
| `true` or transitions to `true` | receives nonce | no nonce | no update | Supports multiple stale existing registrations rather than a failure to create new work. |
| `true` or transitions to `true` | receives nonce | receives nonce | receives new snapshot, UI remains stale | Moves the fault above RTDB into model/view-model/widget propagation. |
| `true` or transitions to `true` | receives nonce | receives nonce | receives test score and UI updates | Starting the extended probe coincided with full client recovery; the diagnostic listener attachment may itself have repaired the retained state. |
| any | listener error | any | any | Interpret the recorded error first; verify rules, authentication, and App Check before drawing a transport conclusion. |

A fresh listener may itself prompt RTDB to reconnect. If the connection observer changes to `true` immediately after the fresh listener attaches, that is evidence from the experiment, not proof that the pre-probe client was healthy. The observer lifetime and generation fields are required when interpreting every nonce timestamp.

## Post-season testing: what still works, and one gate that breaks the UI boundary

The 2026 comp closes on 6 September 2026. Organic fixture-score changes stop at that point. **This does not close the testing window for this defect**, but it does invalidate one boundary unless deliberately worked around.

### The reproduction does not require live season data

The failure needs only three things, none of them season-dependent:

1. a long background interval on a physical Android device;
2. a server-side write to a path the client is listening to; and
3. the client failing to observe that write.

A write made from the Firebase console or the app's admin screens is indistinguishable, from the RTDB client's perspective, from one made by the fixture update service. The games-path failure itself — not merely the `/AppConfig` probe — therefore remains fully reproducible after the season ends.

**Write to a dedicated test node or test competition, not to canonical scores.** Historical fixture values feed stats, ladders, and leaderboards, and returning clients still read them after the season. A test comp isolates the experiment from that blast radius and, per the gate discussion below, is needed anyway to keep the widget boundary observable. Being the only active client is an advantage: no interference and no user-visible risk. Backend deploys are also unblocked once the comp closes, so any experiment needing a function change becomes cheaper rather than harder.

### The gate that breaks post-season UI verification

`GameTipViewModel` decides once, in its constructor, whether to observe `GamesViewModel` at all (`lib/view_models/gametip_viewmodel.dart:112-114`):

```dart
_listensToGamesViewModel =
    _currentDAUComp.latestsCompletedRoundNumber() <
    _currentDAUComp.daurounds.length;
```

`latestsCompletedRoundNumber()` (`packages/dau_shared/lib/models/daucomp.dart:56-72`) returns the highest round number whose last kickoff is more than six hours in the past. Once the final round clears that window it equals `daurounds.length` and the comparison becomes false.

**The decision is per-instance and made once, at construction.** An earlier revision of this section claimed that every `GameTipViewModel` "stops subscribing" six hours after the final kickoff. That was wrong, and the correction matters for how the next test is designed:

- instances constructed *before* the threshold keep their games subscription for their whole lifetime, and continue to update normally;
- instances constructed *after* it never subscribe at all.

So the failure is not a moment when live cards go dark. It is a property of newly built cards — which means **it bites hardest on the cold-start leg of the comparison**, the exact leg this investigation depends on. In the September reproduction, the force-stop relaunch is what proved fresh data reaching the widgets; run that same relaunch after the season ends and every `GameTipViewModel` in the new process is constructed past the threshold, so an unchanged card would prove nothing.

`TipsViewModel` does still observe `GamesViewModel` (`lib/view_models/tips_viewmodel.dart:73,90`), and `GameTipViewModel` observes `TipsViewModel`, so a rebuild can still be triggered indirectly. That path is not a substitute: `_tipsUpdated` refreshes `_tip` and then calls `_syncTipGameScoring()`, which assigns the card's *existing* `game.scoring` onto the tip. Only `_gamesViewModelUpdated` — the gated path — replaces the `Game` the card renders from. An indirect notification can therefore repaint a card without changing the scores it shows.

**Consequence:** a post-season widget-boundary null result does not distinguish a broken fix from a subscription that was never created. The acceptance criterion "resuming updates the Tips page" is unsatisfiable as written for any card built after the threshold.

This gate is not implicated as the cause of the September reproduction — that failure was established at the RTDB layer, upstream of the model, with the games listener silent and the last observed `/.info/connected` reading false. It is a separate hazard affecting testing conducted after the season ends.

### Required workaround

Either of the following restores a valid test, in order of preference:

1. **Create a test competition whose rounds extend past the current date.** This keeps the gate open and preserves full end-to-end verification, including the widget boundary and the acceptance criteria below unchanged. Preferred, since it costs one admin-created comp and restores the complete signal.
2. **Verify at the model boundary instead of the UI.** The diagnostic trace records `games_listener_snapshot_received` and `games_model_applied` independently of any widget, which is sufficient to diagnose the RTDB fault. The September reproduction already established that the model-to-widget path renders correctly once fresh data reaches it, so this is a sound substitute for diagnosis — but it does not exercise the presentation boundary, so it cannot on its own satisfy the acceptance criteria.

Whichever is chosen must be stated explicitly in the next reproduction record, because a widget-boundary null result means something entirely different before and after the season ends.

## Acceptance criteria for a future fix

A future change should not be promoted solely because mocked tests pass. It should demonstrate all of the following:

- a physical Android client can remain backgrounded while a fixture changes from interim to finalized;
- resuming updates the Tips page to both finalized official scores without force quit;
- logs show which server/listener/model/UI events produced the update;
- the behavior is repeatable after a long background interval or a validated equivalent Android suspension scenario;
- iOS behavior remains unchanged; and
- automated coverage protects the specific failure point identified by the investigation.

**Post-season qualification.** The second criterion depends on `GameTipViewModel` observing `GamesViewModel`, which is disabled once the final round has completed (see the preceding section). After 6 September 2026 this criterion can only be satisfied against a competition with rounds extending past the current date. Substituting a model-boundary check does not satisfy it, and a fix must not be promoted on model-boundary evidence alone — the widget boundary is where two of the four original hypotheses lived.

Until that evidence exists, the issue should be treated as open and the current reconnect logic as an unsuccessful mitigation rather than a verified fix.
