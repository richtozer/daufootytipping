# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Development Partnership

We're building production-quality Flutter/Dart code together. Your role is to create maintainable, efficient solutions while catching potential issues early.

When you seem stuck or overly complex, I'll redirect you - my guidance helps you stay on track.

## 🚨 AUTOMATED CHECKS ARE MANDATORY
**ALL hook issues are BLOCKING - EVERYTHING must be ✅ GREEN!**  
No errors. No formatting issues. No linting problems. Zero tolerance.  
These are not suggestions. Fix ALL issues before continuing.

## CRITICAL WORKFLOW - ALWAYS FOLLOW THIS!

### Research → Plan → Implement
**NEVER JUMP STRAIGHT TO CODING!** Always follow this sequence:
1. **Research**: Explore the codebase, understand existing patterns
2. **Plan**: Create a detailed implementation plan and verify it with me  
3. **Implement**: Execute the plan with validation checkpoints

When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."

For complex architectural decisions or challenging problems, use **"ultrathink"** to engage maximum reasoning capacity. Say: "Let me ultrathink about this architecture before proposing a solution."

### USE MULTIPLE AGENTS!
*Leverage subagents aggressively* for better results:

* Spawn agents to explore different parts of the codebase in parallel
* Use one agent to write tests while another implements features
* Delegate research tasks: "I'll have an agent investigate the widget tree while I analyze the state management"
* For complex refactors: One agent identifies changes, another implements them

Say: "I'll spawn agents to tackle different aspects of this problem" whenever a task has multiple independent parts.

### Reality Checkpoints
**Stop and validate** at these moments:
- After implementing a complete feature
- Before starting a new major component  
- When something feels wrong
- Before declaring "done"
- **WHEN HOOKS FAIL WITH ERRORS** ❌

> Why: You can lose track of what's actually working. These checkpoints prevent cascading failures.

### 🚨 CRITICAL: Hook Failures Are BLOCKING
**When hooks report ANY issues (exit code 2), you MUST:**
1. **STOP IMMEDIATELY** - Do not continue with other tasks
2. **FIX ALL ISSUES** - Address every ❌ issue until everything is ✅ GREEN
3. **VERIFY THE FIX** - Re-run the failed command to confirm it's fixed
4. **CONTINUE ORIGINAL TASK** - Return to what you were doing before the interrupt
5. **NEVER IGNORE** - There are NO warnings, only requirements

This includes:
- Formatting issues (dart format)
- Linting violations (flutter analyze)
- Forbidden patterns (dynamic without justification, missing null safety)
- ALL other checks

Your code must be 100% clean. No exceptions.

**Recovery Protocol:**
- When interrupted by a hook failure, maintain awareness of your original task
- After fixing all issues and verifying the fix, continue where you left off
- Use the todo list to track both the fix and your original task

## Working Memory Management

### When context gets long:
- Re-read this CLAUDE.md file
- Summarize progress in a PROGRESS.md file
- Document current state before major changes
- Before working on any problem, always run pwd command and find out the current working directory.

### Maintain TODO.md:
```
## Current Task
- [ ] What we're doing RIGHT NOW

## Completed  
- [x] What's actually done and tested

## Next Steps
- [ ] What comes next
```

## Codebase Architecture

### Technology Stack
- **Frontend**: Flutter/Dart (SDK >=3.8.0)
- **Backend**: Firebase (Realtime Database, Firestore, Cloud Functions, Auth, Analytics, Crashlytics)
- **State Management**: Provider pattern with ChangeNotifier
- **Dependency Injection**: watch_it/get_it service locator pattern

### Core Architecture Pattern
**"Database-First with Reactive Listeners"** - All state changes that persist use Firebase streams with reactive UI updates.

### ViewModel Dependency Tree (from README.md)
```
DAUCompsViewModel (root)
├── GamesViewModel
├── StatsViewModel  
├── TipsViewModel
├── TippersViewModel
└── FixtureDownloadService

GameTipsViewModel
├── TipsViewModel
├── DAUCompsViewModel
└── ScoringViewModel
```

### Development Commands
```bash
# Development with Firebase emulators
firebase emulators:start

# Standard Flutter commands
flutter pub get
flutter clean
flutter analyze         # MANDATORY - must pass
flutter test           # MANDATORY - must pass
dart format lib/       # MANDATORY - must pass

# Firebase deployment
firebase deploy --only hosting
flutter build appbundle

# Video tutorial on Firebase integration:
# https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw
```

### Current State (See TODO.md)
- **18 failing tests** - Week 1 priority to fix
- 26 files with dynamic types needing concrete types
- 24 unnecessary StatefulWidgets to convert
- 30+ widgets missing const constructors
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

> **AUTOMATED ENFORCEMENT**: The flutter analyze hook will BLOCK commits that violate these rules.  
> When you see `❌ FORBIDDEN PATTERN`, you MUST fix it immediately!

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

## Implementation Standards
Use the "Database-First with Reactive Listeners" pattern for all state changes that need to persist in the database

### Our code is complete when:
- ✅ All linters pass with zero issues (`flutter analyze`)
- ✅ All tests pass (`flutter test`)
- ✅ Feature works end-to-end on multiple platforms
- ✅ Old code is deleted
- ✅ Proper documentation on all public APIs
- ✅ Proper null safety implementation
- ✅ No performance warnings in debug mode

### Testing Strategy
- **Complex business logic** → Write tests first (TDD)
- **UI components** → Write widget tests after implementation
- **User flows** → Add integration tests
- **Performance critical paths** → Add performance tests
- **Skip tests for** → Simple getters/setters, basic constructors

### Project Structure
```
lib/
├── main.dart              # Application entry point
├── models/               # Data models and entities
├── pages/                # UI screens/pages
├── services/             # Business logic and API calls
├── view_models/          # State management (Provider/Riverpod)
├── widgets/              # Reusable UI components
├── theme_data.dart       # App theming
└── constants.dart        # App constants

test/                     # Tests mirror lib/ structure
├── models/
├── services/
├── view_models/
├── widgets/
└── integration_test/     # Full app integration tests

functions/                # Firebase backend functions
├── src/                  # TypeScript source
└── lib/                  # Compiled JavaScript
```

## Problem-Solving Together

When you're stuck or confused:
1. **Stop** - Don't spiral into complex solutions
2. **Delegate** - Consider spawning agents for parallel investigation
3. **Ultrathink** - For complex problems, say "I need to ultrathink through this challenge" to engage deeper reasoning
4. **Step back** - Re-read the requirements
5. **Simplify** - The simple solution is usually correct
6. **Ask** - "I see two approaches: [A] vs [B]. Which do you prefer?"

My insights on better approaches are valued - please ask for them!

## Performance & Security

### **Flutter Performance**:
- No premature optimization
- Use `const` constructors liberally
- Implement proper widget rebuilding strategies (`Consumer`, `Selector`)
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

- This is always a feature branch - no backwards compatibility needed
- When in doubt, we choose clarity over cleverness
- Prefer composition over inheritance in Widget design
- Use Flutter's built-in widgets before creating custom ones
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

Avoid complex abstractions or "clever" code. The simple, obvious solution is probably better, and my guidance helps you stay focused on what matters.

## Flutter-Specific Best Practices

### Widget Design:
- **StatelessWidget first** - only use StatefulWidget when state is truly needed
- **Const constructors** - use them everywhere possible
- **Single responsibility** - each widget should have one clear purpose
- **Proper key usage** - use keys for widgets in lists or when identity matters

### State Management:
- **Provider/Riverpod** for app-wide state
- **setState** only for simple, local widget state
- **Avoid** global variables or static state
- **Proper disposal** of resources in StatefulWidgets

### Navigation:
- **Named routes** for complex navigation
- **Proper context management** - don't store BuildContext in fields
- **Navigator 2.0** for complex routing scenarios

### Common Flutter Pitfalls to Avoid:
- Widget overflow errors - use `Flexible`, `Expanded`, or `SingleChildScrollView`
- Calling `setState` after `dispose()` - always check `mounted`
- Not disposing controllers, listeners, or streams
- Using `Scaffold.of(context)` without proper context
- Forgetting to handle loading/error states in async operations