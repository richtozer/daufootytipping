# Startup Profiling Report

## Goal

Measure and reduce time from app launch to:

- `startup.tips_page_stable`: the first stable Tips shell render
- `startup.tips_content_ready`: games + selected tipper tips initial data ready

This report summarizes the code changes, key timing runs, and the current regression questions for independent review.

## Final Code Changes

### 1. Added launch-to-stable and launch-to-content profiling

Files:

- `lib/main.dart`
- `lib/pages/user_home/user_home.dart`
- `lib/pages/user_home/user_home_tips.dart`

Changes:

- Start profiling spans at app launch:
  - `startup.tips_page_stable`
  - `startup.tips_content_ready`
- End `startup.tips_page_stable` when the Tips startup scroll first settles.
- End `startup.tips_content_ready` when both:
  - `gamesViewModel.initialLoadComplete`
  - `selectedTipperTipsViewModel.initialLoadCompleted`
  have completed.

Important note:

- `startup.tips_content_ready` originally ended in a post-frame callback, which produced misleading late values in one run.
- That bug was fixed. It now ends immediately when the underlying data futures complete.

### 2. Eager bootstrap of `TeamsViewModel`

Files:

- `lib/main.dart`
- `lib/view_models/games_viewmodel.dart`

Changes:

- Register `TeamsViewModel` as an app-level singleton during config bootstrap.
- Eagerly instantiate:
  - `TeamsViewModel`
  - `TippersViewModel`
  - `DAUCompsViewModel`
- `GamesViewModel` now reuses the shared `TeamsViewModel` instead of always constructing its own private instance.
- `GamesViewModel` only disposes the teams VM when it owns it.

Rationale:

- Profiling showed the biggest avoidable startup delay was waiting for the first teams snapshot after `GamesViewModel` construction.

### 3. Added VS Code startup profiling launch config

File:

- `.vscode/launch.json`

Added config:

- `Flutter iPhone 16 Pro + Startup Profiling`

This runs with:

- `--dart-define=STARTUP_PROFILING=true`

### 4. Kept one useful low-level games marker

File:

- `lib/view_models/games_viewmodel.dart`

Retained:

- `startup.games_snapshot_received`
- existing `startup.games_initial_load_complete`

Temporary high-noise instrumentation for teams/games breakdown was added during diagnosis and then removed after identifying the key bottleneck.

### 5. Increased RTDB persistence cache for non-emulator mobile runs

File:

- `lib/main.dart`

Changes:

- Realtime Database persistence cache increased from `20 MB` to `100 MB`
- persistence now applies to mobile runs whenever the app is not using the RTDB emulator

Effective behavior:

- `debug + emulator`: no RTDB persistence
- `debug + real device`: RTDB persistence enabled, `100 MB` cache
- `release + real device`: RTDB persistence enabled, `100 MB` cache

Rationale:

- startup profiling on emulator identified teams/games listener timing, but emulator runs do not exercise RTDB persistence
- on real devices, the previous `20 MB` cache cap looked conservative relative to the breadth of RTDB trees this app touches over time
- this change is intended to improve warm-start behavior and reduce cache eviction pressure on returning users

## Experiments Run

### A. Cached tipper only, before relaxed gate experiment

Observed `startup.tips_page_stable` runs:

- `868ms`
- `722ms`
- another baseline run: `781ms`

Interpretation:

- cached tipper improved auth handoff
- but the first stable Tips shell still averaged roughly `0.75s` to `0.85s`

### B. Relaxed `isUserLinked` / stats startup gate experiment

Observed `startup.tips_page_stable` runs:

- `775ms`
- `831ms`
- `732ms`

Interpretation:

- no meaningful improvement versus baseline
- this approach was reverted

Why it was rejected:

- full tipper snapshot processing was only about `30ms` to `40ms`
- tipper gating was not the dominant cost

### C. Deep profiling of games and teams startup

Temporary instrumentation showed:

- teams wait in games startup could be about `178ms`
- games deserialization was cheap, roughly `4ms` to `11ms`
- round linking was cheap, roughly `9ms` to `21ms`
- single-tipper tips load collapsed once games were ready

This pointed to eager teams bootstrap as the better lever.

### D. After eager `TeamsViewModel` bootstrap

Run 1:

- `startup.tips_page_stable 701ms`
- `startup.tips_content_ready 961ms`

This run also showed:

- `startup.games_wait_teams_complete 0ms`
- `startup.single_tipper_tips_loaded 1ms`

Run 2:

- `startup.tips_page_stable 776ms`
- `startup.games_initial_load_complete` at `~806ms` from launch
- `startup.tips_initial_load_complete` at `~810ms` from launch
- logged `startup.tips_content_ready 1631ms`

Interpretation of Run 2:

- the `1631ms` value was instrumentation error from the old post-frame implementation
- the real data-ready point was about `810ms`
- after fixing the metric, the expectation is that future `startup.tips_content_ready` values should align with the `games_initial_load_complete` / `tips_initial_load_complete` range

## Current Best Interpretation

What improved:

- `TeamsViewModel` is now ready before `GamesViewModel` needs it
- the previous late teams wait was effectively removed
- game processing itself is not expensive
- tip parsing for the selected tipper is not expensive once games are available

What likely matters now:

- first game snapshot arrival latency
- general realtime listener first-emission latency
- cache retention quality on real-device non-emulator runs, now that RTDB persistence uses a larger `100 MB` cap

What does **not** appear to be the main issue anymore:

- full tipper load
- tipper auth linkage gate
- games deserialization cost
- round-linking cost

## Remaining Risk Areas For Review

Another agent should specifically check:

1. `TeamsViewModel` lifecycle / ownership

- `GamesViewModel` now reuses DI `TeamsViewModel` when present.
- Check for accidental double-dispose or assumptions that each `GamesViewModel` owns a distinct teams instance.

2. DI registration behavior in `main.dart`

- `TeamsViewModel` is now registered before `needsRegistration` is evaluated for the other core VMs.
- Check whether active comp changes or re-registration flows could leave stale singletons alive longer than intended.

3. `startup.tips_page_stable` one-shot behavior

- `TipsTabState` uses a static `_startupStableLogged` guard.
- Check whether this is acceptable across hot reload, navigation resets, or app lifecycle edge cases.

4. `startup.tips_content_ready` semantics

- It now measures data readiness, not post-frame visibility.
- Confirm this is the intended product metric for “content ready.”

5. Shared `TeamsViewModel` impact on admin/team editing flows

- Admin pages access teams via `gamesViewModel.teamsViewModel`.
- Check whether moving to a shared singleton introduces unexpected cross-screen coupling.

## Files Changed In Final State

- `.vscode/launch.json`
- `lib/main.dart`
- `lib/pages/user_home/user_home.dart`
- `lib/pages/user_home/user_home_tips.dart`
- `lib/view_models/games_viewmodel.dart`
- `lib/services/startup_profiling.dart`
- `lib/view_models/teams_viewmodel.dart`
- `startup_profiling_report.md`

## Suggested Validation For Another Agent

1. Review DI and disposal behavior around `TeamsViewModel`.
2. Review whether `startup.tips_content_ready` should also require one completed UI build after the futures, or whether raw data readiness is the correct definition.
3. Run multiple profiled launches and compare:
   - `startup.tips_page_stable`
   - `startup.tips_content_ready`
   - `startup.games_snapshot_received`
   - `startup.games_initial_load_complete`
4. Check for regressions in:
   - comp switching
   - admin team editing
   - any code paths that instantiate `GamesViewModel` outside the normal startup flow
5. Validate warm-start behavior on a real mobile device with:
   - `USE_FIREBASE_EMULATORS=false`
   - repeated launches or relaunches after initial cache population
   - comparison before/after the `100 MB` cache increase

## Verification Run During This Work

- `flutter analyze` passed after each final patch state
- focused regression test used earlier in the session:
  - `test/view_models/tippers_viewmodel_cached_link_regression_test.dart`
