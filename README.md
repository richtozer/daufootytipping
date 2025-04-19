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

View Model dependancy Tree
==========================

DAUCompsViewModel
├── GamesViewModel
│   ├── DAUCompsViewModel
│   ├── StatsViewModel
│   └── TeamsViewModel
├── StatsViewModel
│   ├── DAUCompsViewModel
│   ├── TipsViewModel
│   └── TippersViewModel
├── TipsViewModel
│   ├── GamesViewModel
│   └── DAUCompsViewModel
├── TippersViewModel
│   ├── FirebaseMessagingService
│   ├── GoogleSheetService
│   └── DAUCompsViewModel
└── FixtureDownloadService

GameTipsViewModel
├── TipsViewModel
├── DAUCompsViewModel
└── ScoringViewModel

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