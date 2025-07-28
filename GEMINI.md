# DAU Footy Tipping App - Gemini Development Guide

## Project Overview
DAU Footy Tipping is a Flutter application designed to manage and display footy tipping competitions, supporting AFL and NRL leagues. The app includes user authentication, game tipping, scoring, league management, and comprehensive statistics tracking.

---

## 1. Core Development Workflow
To ensure all changes are safe, robust, and maintainable, the following workflow must be strictly followed for every feature addition, bug fix, or refactoring task.

### Step 1: Analyze the Request & Existing Code
- Thoroughly understand the user's goal.
- Investigate the relevant sections of the codebase, including view models, services, and UI pages.

### Step 2: Assess Test Coverage
- Before modifying code, locate the corresponding test file (e.g., for `lib/services/foo.dart`, examine `test/services/foo_test.dart`).
- Analyze the existing tests to determine if the logic to be changed is adequately covered.

### Step 3: Propose and Write New Tests (If Needed)
- If test coverage is insufficient for the task, **I must inform you and propose writing new tests before implementing the change.**
- This ensures a safety net is in place to prevent regressions and verify the new logic.

### Step 4: Implement Code Changes
- Write clean, idiomatic Dart/Flutter code that aligns with the existing project structure and conventions.
- For state management, adhere to the architectural goals outlined in Section 2.

### Step 5: Mandatory Verification
- After any code modification, I must run the following commands in order and report their results:
  1.  `flutter analyze`: To check for static analysis warnings, errors, and lints first.
  2.  `flutter test`: To run all unit and widget tests.
- **A task is not complete until `flutter analyze` reports no issues and all tests pass.** I will not consider my job done until these checks are clean.

---

## 2. Architectural Goals

### State Management Migration: from Provider to Riverpod
- **Objective**: Incrementally migrate the application's state management from the current `Provider`/`get_it`/`watch_it` stack to **`flutter_riverpod`**.
- **Strategy**:
    - **New Features**: All new features (view models, UI pages) **must** be implemented using Riverpod providers.
    - **Existing Features**: When an existing feature is modified, the associated view models and widgets should be refactored to use Riverpod as part of that task.
    - **Coexistence**: The old and new state management systems will coexist during the transition.

---

## 3. Project Structure & Technology

### Project Structure
```
lib/
├── models/              # Data models (games, tips, teams, competitions, etc.)
├── pages/               # UI pages organized by functionality
├── services/            # Business logic and external service integrations
├── view_models/         # State management (migrating to Riverpod)
...
```

### Technology Stack
- **Frontend**: Flutter (Dart SDK >=3.1.5 <4.0.0)
- **Backend**: Firebase (Realtime Database, Firestore, Authentication, Cloud Functions, Messaging)
- **State Management**: **Riverpod** (migrating from Provider/get_it/watch_it)
- **Testing**: Flutter test framework with Mockito

### Key Dependencies (Aspirational)
The goal is to consolidate around the following core packages.
```yaml
# Core Firebase & State Management
firebase_core: ^3.4.0
firebase_database: ^11.1.0
firebase_auth: ^5.2.0
flutter_riverpod: ^2.5.1 # Target state management

# Deprecated (to be removed)
provider: ^6.1.1
get_it: ^8.0.3
watch_it: ^1.4.0
...
```

## 4. Development Commands
```bash
# Essential Flutter commands
flutter pub get                    # Install dependencies
flutter run                       # Run app in development
flutter analyze                   # Run static analysis (Mandatory before testing)
flutter test                      # Run all tests (Mandatory after analysis passes)
flutter clean                     # Clean build cache
```
---
