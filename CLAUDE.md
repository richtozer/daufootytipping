# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Development Partnership

We're building production-quality Flutter/Dart code together. Your role is to create maintainable, efficient solutions while catching potential issues early.

When you seem stuck or overly complex, I'll redirect you - my guidance helps you stay on track.

## Workflow

### Research → Plan → Implement
Before implementing a feature, research the existing code and patterns, then present an implementation plan and get my agreement on it. Implement it with validation checkpoints.

During the research phase, prefer the `jcodemunch` MCP when available for symbol-level code exploration and targeted source retrieval. Use it for `search_symbols`, `get_symbol`, `get_file_outline`, and `get_repo_outline`. Keep using `rg` and direct file reads for exact string matches, literals, config values, and cases where the index may be missing or stale.

### Subagents
When a task has independent parts, such as exploring separate areas of the codebase or writing tests while implementing, subagents can work on them in parallel.

### Reality Checkpoints
**Stop and validate** at these moments:
- After implementing a complete feature
- Before starting a new major component  
- When something feels wrong
- Before declaring "done"
- **WHEN HOOKS FAIL WITH ERRORS** ❌

> Why: You can lose track of what's actually working. These checkpoints prevent cascading failures.

### Hook failures block the task
When a hook reports issues (exit code 2) — formatting, `flutter analyze`, forbidden patterns or any other check — treat every one as a requirement, not a warning: fix them all, re-run the failed command to confirm, then continue the original task.

## Working Memory Management

### When context gets long:
- Document current state before major changes
- Before working on any problem, always run pwd command and find out the current working directory.

## Codebase Architecture

### Technology Stack
- **Frontend**: Flutter/Dart (SDK >=3.14.0)
- **Backend**: Firebase (Realtime Database, Firestore, Cloud Functions, Auth, Analytics, Crashlytics)
- **State Management**: ChangeNotifier view models. Older screens rebuild through Provider; new code follows Drift Guards below
- **Dependency Injection**: watch_it/get_it service locator pattern

### Core Architecture Pattern
**"Database-First with Reactive Listeners"** - All state changes that persist use Firebase streams with reactive UI updates.

### ViewModel Dependency Tree
```
ConfigViewModel (root)
└── DAUCompsViewModel
    ├── GamesViewModel
    │   └── TeamsViewModel
    ├── TipsViewModel
    │   ├── GamesViewModel (shared)
    │   └── TippersViewModel
    └── StatsViewModel
        ├── GamesViewModel (shared)
        ├── TippersViewModel (shared)
        └── TipsViewModel (shared)

GameTipViewModel
├── TipsViewModel (+ its dependencies)
├── StatsViewModel (via di<TippersViewModel>())
└── DAUCompsViewModel
```

Service locator (watch_it) registration order: Config → DAUComps → Tippers → (Games, Tips, Stats dynamically)

### Development Commands
```bash
# Development with Firebase emulators
firebase emulators:start

# Standard Flutter commands
flutter pub get
flutter clean
flutter analyze                          # MANDATORY - must pass
flutter test                             # MANDATORY - must pass
flutter test test/path/to/test_file.dart # Run a single test file
dart format <changed files>              # MANDATORY - the files you changed, never a directory
node scripts/ratchet.mjs                 # MANDATORY - must pass (see Drift Guards)

# Backend tests
npm --prefix functions test              # TypeScript functions (node:test)
(cd functions_dart && dart test)         # Dart functions
(cd packages/dau_shared && dart test)    # Shared package
scripts/test-client-integration.sh       # Client classes vs the real callable server and rulesets (emulators)

# Firebase deployment
firebase deploy --only hosting
flutter build appbundle
```

### Branch Workflow & Releases
- Active development happens on `development` branch
- `testing` branch triggers the iOS TestFlight build via GitHub Actions
- `main` is the production branch

```bash
# Promote development → testing, deploy test web, bump build number on development, and push both branches:
scripts/promote-to-testing.sh

# Increment build number only (updates pubspec.yaml version):
scripts/bump_build_number.sh

# Deploy Cloud Functions (PRODUCTION - deliberate, separate step):
scripts/deploy-functions.sh --project <id>                # both codebases
scripts/deploy-functions.sh --project <id> --only dart    # functions_dart only
scripts/deploy-functions.sh --project <id> --only default # TypeScript only
```

Precondition for `promote-to-testing.sh`: must be on `development` with a clean working tree.

`promote-to-testing.sh` does NOT deploy Cloud Functions. Firebase Functions have no
preview channel the way Hosting does, so every function deploy is a production deploy:
TestFlight/Play-internal testers and real users share one backend. Deploy them
deliberately with `deploy-functions.sh`, and keep function changes backward compatible
with the client version currently on `main`.

### Current State
- Test suite currently passes (`flutter test --no-pub`)
- Some files still use `dynamic` and need concrete types
- Some StatefulWidgets hold no state and should become StatelessWidgets
- Widget const constructor cleanup is complete; keep new widgets const by default
- Large complex widgets need decomposition (650+ lines)

## Flutter/Dart-Specific Rules

### FORBIDDEN - NEVER DO THESE:
- **NO dynamic** without strong justification - use concrete types!
- **NO setState() in loops** - use proper state management!
- **NO** keeping old and new code together
- **NO** migration functions or compatibility layers
- **NO** versioned function names (processV2, handleNew)
- **NO** Navigator.push() without proper context management
- **NO** hardcoded strings - use constants or localization
- **NO** missing dispose() - clean up resources in StatefulWidgets
- **NO** missing await on async operations
- **NO** using ! operator without strong justification
- **NO** TODOs in final code

> `flutter analyze` must pass with zero issues; fix any violation of these rules that it or a hook reports before moving on.

### Required Standards:
- **Delete** old code when replacing it
- **Meaningful names**: `userId` not `id`, `userName` not `name`
- **Early returns** to reduce nesting
- **Const constructors** wherever possible for performance
- **Proper null safety**: handle nulls explicitly, avoid `!`
- **Widget tests** for UI components
- **Proper async/await**: handle Futures correctly
- **Use StatelessWidget** when possible - avoid StatefulWidget unless needed
- **Implement proper dispose()** in StatefulWidgets for cleanup
- **Expensive Build methods** Make sure build methods do not wait on expensive methods

## Drift Guards

This app has about 200 tippers and one maintainer who does not review every change. Code that only
ever gets added to becomes a machine nobody can follow, so these rules exist to make each change leave
the codebase no more complicated than it found it.

### The ratchet
`node scripts/ratchet.mjs` compares the code with `config/ratchet-baseline.json` and runs in CI on
every push to `development`. Each number may fall but not rise:
- the length of every source file over 600 lines (a new file may not pass 600)
- `dynamic` in `lib`
- service locator calls (`di<...>`, `di.register...`) in `lib/view_models`
- Provider widgets (`ChangeNotifierProvider`, `MultiProvider`, `Consumer`, `Selector`) in `lib`

When it fails, put the new behaviour in a new service or widget, or shrink something first. When your
change lowers a number, run `node scripts/ratchet.mjs --update` and commit the baseline with it.
**Never raise a number in the baseline or change what the script counts. Only the maintainer does
that: stop and ask.**

### Rules
- **Size the solution to the app.** For a one-off operation such as a migration step or a data repair,
  prefer a short runbook step the maintainer performs over new modes, tools or automation.
- **Temporary means listed.** Anything built for a migration, a coexistence period, a platform limit or
  a deferred upgrade gets a row in `docs/temporary-mechanisms.md`, with the condition that removes it,
  in the same change.
- **Moving behaviour deletes the old path.** When behaviour moves to the backend or to another class,
  delete the old code and every branch that depended on it in the same change. Leave no stub that
  returns a constant.
- **Do not patch a patch.** If a fix needs another flag, timer or retry added to logic that already has
  some, stop and propose a simpler design instead.
- **One way to wire state.** A view model or service receives what it depends on through its
  constructor. A widget finds a view model with `di<...>()` and rebuilds with `ListenableBuilder`; do
  not add `addListener` with `setState`, and do not add Provider widgets.
- **Docs change with the code.** If a change makes a statement in a `.md` file false, fix that file in
  the same commit. Do not write line, file or test counts into docs.
- **Scratch output goes in `.tmp/`**, which is ignored. Do not leave logs or reports in the repo root.

## Implementation Standards
Use the "Database-First with Reactive Listeners" pattern for all state changes that need to persist in the database

### Our code is complete when:
- ✅ All linters pass with zero issues (`flutter analyze`)
- ✅ All tests pass (`flutter test`)
- ✅ The ratchet passes (`node scripts/ratchet.mjs`)
- ✅ Feature works end-to-end on multiple platforms
- ✅ Old code is deleted
- ✅ Proper documentation on all public APIs
- ✅ Proper null safety implementation
- ✅ No performance warnings in debug mode

### Testing Strategy
- **Complex business logic** → Write tests first (TDD)
- **Reproducible bugs** → Before changing any code, write a regression test that reproduces the bug and run it to show it fails. Then apply the fix and show the same test passes. The failing run proves the test actually catches the bug.
- **UI components** → Write widget tests after implementation
- **User flows** → Add integration tests
- **Performance critical paths** → Add performance tests
- **Skip tests for** → Simple getters/setters, basic constructors

### Driving the running app
To check behaviour in the running app, run a debug build and connect to it through the `dart` MCP
server (`dtd`: `listDtdUris`, then `connect`). Do not navigate by screenshots.
- Read what is on screen as text from the semantics tree (`widget_inspector`, `vm_service`).
- Find and tap widgets with `flutter_driver_command` by semantics label or `Key`, never by coordinates.
  Driver commands only work in a build that calls `enableFlutterDriverExtension()`; the app does not
  do this by default.
- After each flow, check `get_runtime_errors`. After a code change, hot reload.
- When a widget cannot be found because it has no label, give it a `Semantics` label or a `Key`. This
  also helps VoiceOver and TalkBack users.
- Use screenshots only for visual questions such as layout, alignment, theming and clipping.

### Project Structure
```
lib/
├── main.dart              # Application entry point
├── models/               # Data models and entities
├── pages/                # UI screens/pages
├── services/             # Business logic and API calls
├── view_models/          # State management (Provider + ChangeNotifier)
├── widgets/              # Reusable UI components
├── theme_data.dart       # App theming
└── constants/            # App constants

test/                     # Tests mirror lib/ structure
├── models/
├── services/
├── view_models/
├── widgets/
└── integration/          # Integration tests against the emulators

functions/                # Firebase backend functions
├── src/                  # TypeScript source
└── lib/                  # Compiled JavaScript
```

## Problem-Solving Together

When you're stuck or confused:
1. **Stop** - Don't spiral into complex solutions
2. **Delegate** - Consider spawning agents for parallel investigation
3. **Step back** - Re-read the requirements
4. **Simplify** - The simple solution is usually correct
5. **Ask** - "I see two approaches: [A] vs [B]. Which do you prefer?"

My insights on better approaches are valued - please ask for them!

## Performance & Security

### **Flutter Performance**:
- No premature optimization
- Use `const` constructors liberally
- Rebuild only what changed: wrap the smallest subtree in a `ListenableBuilder` or `ValueListenableBuilder`
- Use `ListView.builder` for large lists
- Implement proper image caching and loading
- Profile with Flutter DevTools before claiming performance improvements
- Monitor widget rebuilds with `debugPrintBuildLog`

### **Security Always**:
- Validate all user inputs
- Use `dart:math` Random.secure() for cryptographic randomness
- Implement proper Firebase security rules
- Use secure storage for sensitive data (flutter_secure_storage)
- Validate data from external APIs
- Never log sensitive information

## Communication Protocol

### Progress Updates:
```
✓ Implemented user authentication (all tests passing)
✓ Added login/logout flow with proper state management
✗ Found issue with widget rebuilding - investigating
```

### Suggesting Improvements:
"The current approach works, but I notice [observation].
Would you like me to [specific improvement]?"

## Working Together

- Client code needs no backwards-compatibility layers; Cloud Functions changes must stay compatible with the client on `main` (see Branch Workflow & Releases)
- When in doubt, we choose clarity over cleverness
- Prefer composition over inheritance in Widget design
- Use Flutter's built-in widgets before creating custom ones

Avoid complex abstractions or "clever" code. The simple, obvious solution is probably better, and my guidance helps you stay focused on what matters.

