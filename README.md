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
dotenv: Environment variables for the project.
analysis_options.yaml: Linter rules for Dart code analysis.

Dependencies
============
The project relies on several dependencies, which are specified in the pubspec.yaml file. Here are some of the key dependencies:

firebase_core: Core Firebase SDK for Flutter.
firebase_database: Firebase Realtime Database plugin for Flutter.
provider: State management library for Flutter.
flutter_localizations: Provides localizations for Flutter.
http: A composable, Future-based library for making HTTP requests.
intl: Provides internationalization and localization facilities.
Example pubspec.yaml

This is a useful video to get up to speed on how the Firebase Realtime Database is used in this project:
https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw

Legacy integration with Google sheets is based on this example:

https://gist.github.com/CodingDoug/44ad12f4836e79ca9fa11ba5af6955f7

Getting Started
===============
To get started with the project, follow these steps:

Clone the repository:

Install dependencies:

Set up Firebase:

Add your Firebase configuration files (google-services.json for Android and GoogleService-Info.plist for iOS) to the respective platform directories.
Run the application:

Contributing
============
Contributions are welcome! Please open an issue or submit a pull request if you have any improvements or bug fixes.

License
=======
This project is licensed under the MIT License. See the LICENSE file for more details.