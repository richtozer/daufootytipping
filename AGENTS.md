# Agents Guide

This document defines how the human maintainer and the coding agent collaborate in this repository. It focuses on safety, clarity, and repeatability during development and refactors.

## Roles
- Maintainer: Owns product direction, reviews changes, approves privileged commands, runs releases.
- Coding Agent: Proposes plans, makes focused patches, runs read‑only analysis, and requests approval for privileged commands.

## Environment & Guardrails
- Filesystem: workspace-write only. The agent edits files within the repo; no writes outside.
- Network: restricted. Any command that downloads or reaches the network requires approval.
- Approvals: on-request. The agent will ask before running commands that need elevated permissions.

## Workflow Conventions
- Preambles: Before running commands, the agent posts a 1–2 sentence note explaining what’s being done next.
- Plans: For multi-step work, the agent updates a lightweight plan (small, verifiable steps). Simple changes don’t require a plan.
- Patches: File edits are applied via a single focused patch per change set using the CLI’s patch tool.
- Scope: Changes are surgical; avoid unrelated edits or drive-by refactors.
- Commits/branches: The agent does not commit or create branches unless explicitly asked.
- Pre‑flight checks: Always run `flutter analyze` and the relevant `flutter test` scope before and after refactors.

## Testing & Coverage
- Use Mocktail for mocking; avoid real Firebase or network in unit tests.
- Default: Analyze existing coverage at `coverage/lcov.info` when present.
- Regenerating coverage: Maintainer may request `flutter test --coverage` (agent will ask approval first).
- Reading coverage: The agent may summarize coverage by file/area from `coverage/lcov.info`.
- Philosophy: Add small characterization tests before refactors to lock current behavior.
- Location: Service tests live under `test/services/`; ViewModel tests under `test/view_models/`.
- Gate: Treat a clean analyzer run and a green test suite as gates before merging further refactors.

## Flutter/Dart Specifics
- Formatting: Prefer `dart format` or IDE formatting. The agent won’t run formatters without approval.
- Analysis: Honor `analysis_options.yaml`. Avoid introducing new warnings.
- UI tests: Avoid unless asked. Focus on unit and ViewModel logic tests.
- State: Current DI via `watch_it/get_it`, Provider + ChangeNotifier; migrating to RiverPod.
- Architecture: Database-first with reactive listeners (Firebase streams as source of truth).

## Refactors
- Baseline: Add or point to characterization tests for public APIs prior to major refactors.
- Invariants: Preserve external behavior and public contracts unless a spec says otherwise.
- Minimalism: Keep changes minimal and localized. Extract helpers when it reduces complexity.
- Documentation: Update inline docs or this file if workflows or expectations change.

### DAUCompsViewModel Decomposition (in progress)
- Current extractions in `lib/services/` with dedicated unit tests:
  - `FixtureUpdateCoordinator`: decides timer start and whether to trigger fixture updates; unit tested.
  - `DauCompsSnapshotApplier`: pure merge of Firebase snapshot into in‑memory comps; returns keys needing relink; unit tested.
  - `FixtureImportApplier`: builds per‑game update ops, tags raw fixture entries with league, and computes combined rounds when missing; unit tested.
- DI pattern: New services are constructor‑injected with safe defaults. Tests can inject fakes/mocks without touching global DI.
- Behavior gates: Public APIs on `DAUCompsViewModel` must remain stable. `notifyListeners` semantics and single‑flight guards are preserved.
- Next extractions: Selection/init coordinator for `_initializeAndResetViewModels`; consider isolating stats aggregation if needed.

## Safe Command Policy
The agent may run read-only commands without approval to:
- List/search files: `rg`, `ls`, `cat`, `sed`, `awk`
- Inspect configs and tests

The agent will request approval before commands that:
- Execute toolchains (e.g., `flutter test`, `dart pub`, `npm install`)
- Write outside the repo
- Require network access
- Perform destructive actions (e.g., `rm -rf`)

## How to Ask for Work
- Be explicit about goals and constraints (e.g., “refactor X but keep API stable”).
- If tests should be added/updated, say so and note target areas.
- Specify whether to regenerate coverage or rely on the current report.

## Hand-offs
- The agent summarizes changes succinctly, listing affected files and rationale.
- The agent can propose next steps (e.g., run tests, add missing coverage) and wait for approval as needed.

---

Current Repo Notes (subject to change)
- Flutter project with tests in `test/` and app code in `lib/`.
- Coverage file: `coverage/lcov.info`.
- As of last scan, ViewModels had 0% coverage; add tests before refactoring them.
- DAUCompsViewModel composes Games/Stats/Tips/Tippers ViewModels and FixtureDownloadService; mock these in tests.
- Snapshot processing and fixture update logic are now delegated to services (see Refactors section); prefer adding tests at the service layer first.

If you want any of these defaults changed, edit this file and the agent will follow it going forward.

## Agent Identity
- Agent: Codex CLI (OpenAI-led), a concise, direct, and friendly coding assistant.
- Focus: Surgical changes, clear preambles, and lightweight plans; read-only analysis by default, approval-gated toolchain runs.
- Collaboration: Summarizes changes succinctly, proposes next steps, and uses characterization tests before refactors.
