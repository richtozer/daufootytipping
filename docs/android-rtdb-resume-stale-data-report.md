# Android Realtime Database Resume Staleness

**Status:** Unresolved. The two shipped resume fixes have not solved the problem on a physical Android device. Investigate and reproduce before making another production change.

**Report updated:** 30 August 2026

## Executive summary

After the app remains in the background for an extended period, an Android client can resume with stale Firebase Realtime Database (RTDB) state and continue displaying it. The latest field observation was on a Google Pixel after the app had been backgrounded for several days: the Tips page still showed Saturday's live/interim game scores, while the iOS app showed the finalized fixture scores. The Android app did not recover through normal foreground use; force-quitting and reopening it was the only workaround found.

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

### Latest report after the Android reconnect fix

- Device: physical Google Pixel.
- Background duration: several days.
- On resume, the Tips page continued to show live/interim scores for Saturday's games.
- At the same time, the iOS app showed the finalized fixture scores for those games.
- The Android app did not self-correct through normal use.
- Force-quitting and reopening the Android app loaded the finalized state.

The exact Android build number, Pixel model, Android version, battery-optimization settings, and background duration were not captured in the report and should be recorded in the next reproduction.

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

## What the latest observation tells us

The Tips game card displays the interim-score banner only when crowd-sourced/live scores exist and at least one official fixture score is missing. When both official scores exist, the official values take precedence and stale live scores are ignored by the reconciliation logic.

Therefore, the latest symptom strongly suggests that the Android in-memory `Game` still lacked at least one finalized official score after resume. It is less consistent with a simple repaint failure or a stale live-score overlay on top of an otherwise current fixture. This is an inference from the current UI and model logic; it needs runtime evidence from the affected device.

The force-quit result is also important. A cold start recreates the Flutter object graph, native Firebase client state, subscriptions, and in-memory models, and it successfully obtained the finalized fixture. That narrows the fault toward state retained across Android background/resume rather than absent or incorrect backend data. It does not yet distinguish among:

- the expected lifecycle callback never running;
- the coordinator deciding no background transition occurred;
- the registered view model not being ready or not being the instance used by the visible page;
- RTDB reporting connected before the required data was synchronized;
- `get()` returning old persisted data or otherwise not delivering the current server snapshot;
- the fresh snapshot arriving but being dropped or overwritten by a later stale listener event;
- listeners failing to resume or being attached to stale state; or
- the model updating without the visible Tips dependency rebuilding.

## Known gaps in the current implementation and evidence

1. **No physical-device proof.** The fixes were not validated through a controlled, long-background reproduction on a physical Android device before promotion.
2. **No durable resume telemetry.** Current messages use developer logging. We do not have field evidence showing the lifecycle states, whether the handler ran, connection result, fixture values returned, model update, listener events, or UI rebuild for the failed resume.
3. **`/.info/connected` is only a transport signal.** It confirms that the SDK reports a live connection; it does not prove that every existing listener has caught up or that a later snapshot cannot overwrite the explicitly refreshed model.
4. **Only the fixture path is explicitly refreshed.** Tips, stats, tippers, and live-score paths continue to depend on their existing listeners. The connection restart affects the whole database instance, but the post-reconnect verification checks only fixtures.
5. **Mocks cannot model Android persistence and process suspension.** The current tests establish call ordering and application logic, not native SDK behavior under Doze, socket suspension, process retention, or disk-cache fallback.
6. **The successful force quit has not been instrumented.** We know cold start repairs the display, but not which cold-start event or read differs from resume.
7. **Reconnect failure is deliberately hidden from the refresh path.** Each connection wait can run for 10 seconds. With three attempts and the one- and two-second delays, the code can spend approximately 33 seconds failing to reconnect, log the final failure, and then continue to `get()`. If the native client remains disconnected, that read can fall back to stale cache and look like a successful refresh.
8. **Lifecycle delivery is not guaranteed.** The coordinator only refreshes after it observes `hidden`, `paused`, or `detached`; it intentionally ignores `inactive`. [Flutter documents](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html) that applications should not assume every lifecycle notification will be delivered. A missing background event could therefore cause the resume to be skipped entirely. A second resume received while a refresh is already running is also dropped rather than queued.
9. **Long-lived subscriptions are not recreated or health-checked.** The Android transport restart retains the Dart games, tips, and stats subscriptions. Their current listeners do not provide enough error or generation telemetry to show whether they resumed correctly.
10. **The presentation boundary is not traced.** The fixture refresh can succeed while a downstream card still fails to consume it. In particular, individual `GameTipViewModel` instances only subscribe directly to games updates while the competition is considered to have active rounds. This is a lower-confidence explanation than a stuck connection, but the existing evidence cannot rule it out.

## Independent read-only audit

An independent agent reviewed the current implementation and history without changing code. Its highest-priority hypothesis is that build 702 may be invoking the same failing native Android reconnect operation rather than repairing it.

Two upstream reports closely resemble the observed pattern:

- [FlutterFire issue #17769: Realtime Database fails to reconnect on Android](https://github.com/firebase/flutterfire/issues/17769)
- [Firebase Android SDK issue #7549: Realtime Database cannot reconnect](https://github.com/firebase/firebase-android-sdk/issues/7549)

Those reports describe Android clients that remain disconnected after backgrounding or an explicit disconnect, where `goOnline()` does not restore `/.info/connected` and an app restart does. They were closed without a demonstrated SDK fix, so they are supporting evidence for a hypothesis, not confirmation that this app has the same defect.

The dependency lock currently resolves `firebase_database` 12.4.2. The next investigation should capture the resolved native Android Firebase Database version from the actual failing build and compare its behavior with the upstream reports. The official Android [`Query.get()` documentation](https://firebase.google.com/docs/reference/android/com/google/firebase/database/Query#get()) is also important: it describes a server request that may fall back to local cache when the client cannot obtain server data. That behavior fits the masked-failure path above.

The audit ranked the current hypotheses as follows:

1. Native Android RTDB connection remains stuck; all reconnect waits fail, then the fixture read falls back to stale persisted data.
2. The lifecycle coordinator never sees the required background event, so no resume work runs.
3. The explicit refresh gets current data but a stale listener event subsequently rolls the model back.
4. The model becomes current but the visible game-card/view-model chain does not rebuild from it.

This order is a starting point for evidence collection, not a conclusion.

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

This does not change the report's own conclusion or its priority ordering. The strongest-supported account remains the one already stated in the existing audit above: the native connection may stay stuck after suspension, build 702 masks that by continuing to a cache-capable `get()` regardless, and force quit recovers by rebuilding the native client — and none of that can be confirmed without the device telemetry the report already calls for. This section's contribution is narrower than first written: a plausible, unconfirmed refinement of *why* the masked failure looks the way it does (`get()` reading through an unresynced listener), not new proof, and not a replacement for capturing lifecycle/connection/read telemetry on a physical device.

## Investigation requested before another fix

The next agent should remain in diagnosis mode until it can identify where the expected flow diverges on a physical Pixel. A useful investigation should produce evidence for each boundary below:

1. **Reproduce deliberately and classify the diagnostic effect.** Use a release/profile build on a physical Pixel, establish known interim fixture/live-score values, background the app, finalize the fixture in the backend, then resume. Start with shorter intervals and Doze simulation before repeating a genuine long-background test. Record whether the stale-data failure still reproduces with diagnostics enabled before interpreting the trace. A successful reproduction is usable evidence; a non-reproduction is ambiguous because the diagnostic connection observer may itself wake or heal RTDB activity. If diagnostics appear to suppress the problem, compare with a capture build that retains native logging and the other breadcrumbs but omits the pre-reconnect `/.info/connected` observer.
2. **Capture the complete lifecycle sequence.** Record every `AppLifecycleState`, timestamps, whether `_wasBackgrounded` was set, and whether the refresh was skipped because the view model was not registered.
3. **Correlate one resume attempt end to end.** Add a durable resume-attempt identifier to connection state changes, reconnect timing, fixture-read start/end/error, game keys and official-score presence, `GamesViewModel` notifications, live-score reconciliation, and the displayed game's values. Do not rely only on `dart:developer.log`, because the current field failures have no retained trace.
4. **Compare data sources.** At the moment of failure, compare the current backend fixture, the explicit `get()` result, the next games listener event, the in-memory `Game`, the live-score cache, and the values observed by the Tips widget.
5. **Look for rollback after refresh.** Determine whether a current explicit snapshot is applied and then replaced or mutated by a stale listener event.
6. **Compare resume with cold start.** Capture the same sequence after force quit to identify the first point at which cold start differs.
7. **Check platform conditions.** Record Android version, Pixel model, app build, network type and transition, battery optimization, background restriction, and whether the OS retained or recreated the process.
8. **Exercise Android suspension deliberately.** Test screen lock and Home-button backgrounding separately, use Android Doze/device-idle tooling for faster cycles, and then repeat with a natural overnight or multi-day interval.
9. **Collect native evidence.** Enable verbose native RTDB logging in a diagnostic build and capture Android logs alongside app-level breadcrumbs. Include authentication/App Check token events, connection false-to-true transitions, network changes, and battery restrictions.
10. **Use an integration/device test for the eventual regression gate.** Unit tests should remain, but the acceptance criterion must be a physical Android stale-to-fresh transition without force quit.

A compact decision matrix for each reproduction is:

```text
Did the lifecycle handler run?
    -> Did RTDB report a new live connection?
        -> Did get() contain the final fixture?
            -> Did GamesViewModel contain the final fixture?
                -> Did the linked round/card render the final fixture?
```

The first failed boundary distinguishes lifecycle, transport/cache, listener/model, and presentation failures before another fix is selected.

## Diagnostic implementation prepared for review

An instrumentation-only implementation is now available in the working tree. It is disabled by default and activates only in an Android build compiled with:

```text
--dart-define=ANDROID_RESUME_DIAGNOSTICS=true
```

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

## Acceptance criteria for a future fix

A future change should not be promoted solely because mocked tests pass. It should demonstrate all of the following:

- a physical Android client can remain backgrounded while a fixture changes from interim to finalized;
- resuming updates the Tips page to both finalized official scores without force quit;
- logs show which server/listener/model/UI events produced the update;
- the behavior is repeatable after a long background interval or a validated equivalent Android suspension scenario;
- iOS behavior remains unchanged; and
- automated coverage protects the specific failure point identified by the investigation.

Until that evidence exists, the issue should be treated as open and the current reconnect logic as an unsuccessful mitigation rather than a verified fix.
