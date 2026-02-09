DAU Footy Tipping
=================
DAU Footy Tipping is a Flutter application designed to manage and display footy tipping competitions. This README provides an overview of the project structure and its dependencies to help developers get started with the project.

Project Structure
=================
The project is organized into the following main directories and files:

Key Directories and Files
lib/: Contains the main Dart code for the application, including models, view models, and UI components.
assets/: Stores static assets such as images and fonts.
android/, ios/, linux/, macos/, web/, windows/: Platform-specific code and configurations.
functions/: Contains Firebase Cloud Functions.
pubspec.yaml: Defines the project's dependencies and environment settings.
firebase.json: Firebase configuration file.

View Model dependency Tree
==========================

here's the complete dependency structure between the view models:

  🏗️ View Model Dependencies

  Core Root View Model Tree

  ConfigViewModel (root config)
  │
  └── DAUCompsViewModel (DAU competition management)
      ├── GamesViewModel
      │   └── TeamsViewModel
      ├── TipsViewModel
      │   ├── GamesViewModel (shared)
      │   └── TippersViewModel
      └── StatsViewModel
          ├── GamesViewModel (shared)
          ├── TippersViewModel (shared)
          └── TipsViewModel (shared)

  GameTipViewModel Tree

  GameTipViewModel
  ├── TipsViewModel
  │   ├── GamesViewModel
  │   └── TippersViewModel
  ├── StatsViewModel (via di<TippersViewModel>())
  └── DAUCompsViewModel (via _currentDAUComp)

  📊 Detailed Dependency Matrix

  | View Model             | Depends On                                               | Key Relationships      |
  |------------------------|----------------------------------------------------------|-----------------------------------------|
  | ConfigViewModel ⚙️     | None (root)                                              | Provides app config to others        |
  | DAUCompsViewModel 🔧   | ConfigViewModel                                          | Creates/competitive loading with others |
  | GamesViewModel 🏈      | DAUCompsViewModel, TeamsViewModel                        | Depends on teams for game  construction  |
  | TippersViewModel 👤    | DAUCompsViewModel (in merge operations), ConfigViewModel | Used for user linking      |
  | TipsViewModel 💡       | GamesViewModel, TippersViewModel, DAUCompsViewModel      | Core game/tip linkage        |
  | StatsViewModel 📊      | GamesViewModel, TippersViewModel, DAUCompsViewModel      | Calculates scoring across all data        |
  | TeamsViewModel 📋      | None (data layer)                                        | Provides teams to GamesViewModel        |
  | GameTipViewModel 🎯    | TipsViewModel + all its dependencies                     | Higher-level tip management        |
  | SearchQueryProvider 🔍 | None (UI state only)                                     | Independent utility        |

  🔗 Service Registration Patterns

  Service Locator (watch_it) registrations:
  - ConfigViewModel - Always registered first
  - TippersViewModel - Registered with Config parameter
  - DAUCompsViewModel - Registered with Config parameters
  - StatsViewModel - Dynamically registered by DAUCompsViewModel
  - GamesViewModel - Created per DAUComp instance
  - TipsViewModel - Created per DAUComp/Tipper combo

  📈 Data Flow Architecture

  1. Initialization Order:
  Config → DAUComps → Tippers → (Games, Tips, Stats dynamically)
  2. Communication Patterns:
    - Database-driven: Config, Teams, DAUComps from DB
    - Provider pattern: ChangeNotifier with notifyListeners()
    - Dependency Injection: watch_it service locator
  3. Reactivity:
    - Stream subscriptions for real-time DB updates
    - ChangeNotifier listeners for UI updates
    - Cross-model listeners via service locator

External Dependencies
=====================
The project relies on several dependencies, which are specified in the pubspec.yaml file. Here are some of the key dependencies:

firebase_core: Core Firebase SDK for Flutter.
firebase_database: Firebase Realtime Database plugin for Flutter.
provider: State management library for Flutter.
http: A composable, Future-based library for making HTTP requests.

This is a useful video to get up to speed on how the Firebase Realtime Database is used in this project:
https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw


Getting Started
===============
To get started with the project, follow these steps:

Clone the repository:

Install dependencies:

Set up Firebase:

Add your Firebase configuration files (google-services.json for Android and GoogleService-Info.plist for iOS) to the respective platform directories.
Run the application:

GitHub Build and Release Workflows
==================================

This project uses GitHub Actions for both iOS and Android builds.

iOS (`.github/workflows/ios-testflight.yml`)
---------------------------------------------
- Trigger:
  - Automatic on push to `testing`
  - Manual via `workflow_dispatch`
- Runner:
  - `macos-26` with enforced Xcode/iOS SDK 26 checks
- Output:
  - IPA artifact upload
  - TestFlight upload (unless manual run sets `upload_to_testflight=false`)
- Versioning:
  - Build name and build number come from `pubspec.yaml` (`version: x.y.z+N`)

iOS release runbook
-------------------
1. Bump build number:
   - `scripts/bump_build_number.sh`
2. Commit and push to `testing`.
3. Confirm `iOS TestFlight Build` passes in GitHub Actions.
4. Confirm build appears and finishes processing in TestFlight.

Android (`.github/workflows/android-basic.yml`)
------------------------------------------------
- Trigger:
  - Manual only (`workflow_dispatch`)
- Workflow behavior:
  - Runs analyzer/tests and builds APK/AAB artifacts
  - Optional Play deploy controlled by `deploy_track` input:
    - `none`
    - `internal` (testing branch only)
    - `production` (main branch only)
- Versioning:
  - Build name/build number also come from `pubspec.yaml`

Common build/version command
----------------------------
- Increment build number in `pubspec.yaml` from any working directory:
  - `scripts/bump_build_number.sh`

Common Terminal Commands
========================

Here is a summary of the most common terminal commands used when developing this project:

firebase deploy --only hosting
flutter build appbundle
firebase emulators:start
flutter pub get
flutter clean
firebase emulators:start

Contributing
============
Contributions are welcome! Please open an issue or submit a pull request if you have any improvements or bug fixes.

License
=======
This project is licensed under the MIT License. See the LICENSE file for more details.
