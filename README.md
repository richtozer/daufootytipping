# DAU Footy Tipping
DAU Tips is a Flutter application for participating in and managing footy tipping competitions. This README provides an overview of the project structure and its dependencies to help developers get started with the project.

## Project Structure
The project is organized into the following main directories and files:

### Key Directories and Files
- `lib/`: Contains the main Dart code for the application. It is structured using an MVVM (Model-View-ViewModel) approach, with common directories being:
    - `models/`: For data structures and business logic.
    - `pages/` or `views/`: For UI components (Flutter Widgets).
    - `view_models/`: For state management and presentation logic.
    - `services/`: For external communications (e.g., API calls, Firebase interactions).
- `assets/`: Stores static assets such as images, fonts (if any), and other resources like `html/` files.
- `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`: Platform-specific code and configurations for each target platform.
- `functions/`: Contains Firebase Cloud Functions written in TypeScript, used for backend logic.
- `pubspec.yaml`: Defines the project's Flutter and Dart dependencies, version, and other metadata.
- `firebase.json`: Configuration file for Firebase projects, specifying rules for Firebase services like Hosting, Functions, etc.

## Features
- User authentication (e.g., email, Google, Apple sign-in)
- Create and join tipping competitions
- Submit and view tips for various games/rounds
- View live scores and game results
- Competition leaderboards
- User profiles and statistics
- Admin functionalities for managing competitions, users, and games.
- Push notifications for reminders or game updates.

## Technology Stack
- **Flutter:** For cross-platform mobile, web, and desktop development.
- **Dart:** The programming language used for Flutter.
- **Firebase:** As the backend platform, including:
    - Firebase Authentication
    - Firebase Realtime Database
    - Firebase Firestore
    - Firebase Cloud Functions
    - Firebase Messaging (for push notifications)
    - Firebase App Check
- **State Management:** `Provider`, `GetIt`, `WatchIt`
- **Other notable packages:**
    - `http`: For making HTTP requests.
    - `json_serializable`: For JSON parsing.
    - `cached_network_image`: For displaying images from the internet.

## External Dependencies
The project relies on several dependencies, which are specified in the `pubspec.yaml` file. Here are some of the key external libraries:

- **Firebase:**
    - `firebase_core`: Core Firebase SDK, enabling Firebase services in Flutter.
    - `firebase_auth`: For user authentication with various providers (e.g., email, Google, Apple).
    - `cloud_firestore`: A flexible, scalable NoSQL cloud database for storing and syncing data.
    - `firebase_database`: Realtime NoSQL cloud database, often used for low-latency data synchronization. (See also the [video guide](https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw) on its use in this project).
    - `firebase_messaging`: Enables receiving and sending push notifications.
- **State Management:**
    - `provider`: A wrapper around `InheritedWidget` for managing state in a Flutter application.
- **Networking & Data:**
    - `http`: For making HTTP requests to fetch data from APIs.
    - `cached_network_image`: To display images from the internet and keep them in the cache for performance.
- **UI:**
    - `flutter_svg`: For rendering Scalable Vector Graphics (SVG) files.

## Getting Started

This section guides you through setting up the DAU Tips project for development.

### Prerequisites

Before you begin, ensure you have the following installed:

-   **Flutter SDK:** Follow the [official Flutter installation guide](https://flutter.dev/docs/get-started/install) for your operating system.
-   **Node.js and npm:** Required for Firebase Cloud Functions. Install from the [official Node.js website](https://nodejs.org/).
-   **Firebase CLI:** Install the Firebase Command Line Interface globally by following the [official Firebase CLI guide](https://firebase.google.com/docs/cli#setup_update_cli).
-   **IDE (Optional but Recommended):**
    -   Visual Studio Code with the [Flutter extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter).
    -   Android Studio with the [Flutter plugin](https://flutter.dev/docs/get-started/editor?tab=androidstudio).

### Setup Steps

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/your-username/dau-footy-tipping.git # Replace with the actual repository URL
    cd dau-footy-tipping # Make sure you are in the project root
    ```

2.  **Create and Configure Firebase Project:**
    *   Go to the [Firebase Console](https://console.firebase.google.com/) and create a new Firebase project (or use an existing one).
    *   **Enable Services:** In your Firebase project console, ensure the following services are enabled:
        *   Authentication (configure your desired sign-in methods like Email/Password, Google, Apple).
        *   Cloud Firestore (set up in Native Mode or Datastore Mode as per project needs - usually Native Mode for new projects).
        *   Realtime Database.
        *   Firebase Storage (if image/file uploads are a feature).
    *   **Register Apps:**
        *   **Android:**
            1.  In Firebase, add an Android app. The package name is typically found in `android/app/build.gradle` (look for `applicationId`).
            2.  Download the `google-services.json` file.
            3.  Place this file in the `android/app/` directory of your Flutter project.
        *   **iOS:**
            1.  In Firebase, add an iOS app. The Bundle ID is typically found by opening `ios/Runner.xcworkspace` in Xcode and checking the "General" tab for the Runner target.
            2.  Download the `GoogleService-Info.plist` file.
            3.  Place this file in the `ios/Runner/` directory of your Flutter project (you can drag and drop it into Xcode, ensuring it's added to the Runner target).

3.  **Install Application Dependencies:**
    This command fetches all the Dart/Flutter packages defined in `pubspec.yaml`.
    ```bash
    flutter pub get
    ```

4.  **Install Firebase Functions Dependencies:**
    The Firebase Cloud Functions are located in the `functions/` directory and have their own Node.js dependencies.
    ```bash
    cd functions
    npm install
    cd ..
    ```

5.  **Deploy Firebase Resources:**
    *   **Login to Firebase:** If you haven't already, log in to your Firebase account:
        ```bash
        firebase login
        ```
    *   **Select Project (Optional):** If you have multiple Firebase projects, you might want to set the active project:
        ```bash
        firebase use --add
        ```
        And select your project from the list.
    *   **Deploy:** The `firebase.json` file in this project is configured to deploy Firebase services such as Database rules, Cloud Functions, and Hosting configurations.
        ```bash
        firebase deploy
        ```
        Alternatively, you can deploy specific parts:
        ```bash
        firebase deploy --only functions,database,hosting
        ```
        (Note: `database` here refers to Realtime Database rules defined in `database.rules.json`. Firestore rules are typically deployed separately or via the console if not included in `firebase.json`'s `firestore` section, which is not present in the provided file).

6.  **Run the Application:**
    ```bash
    flutter run
    ```
    To run on a specific device or emulator, use `flutter devices` to list available device IDs and then:
    ```bash
    flutter run -d <your_device_id>
    ```

## Common Terminal Commands

Here is a summary of common terminal commands that are useful during the development of this project. For detailed setup, see the "Getting Started" section.

### Flutter: General Development
-   `flutter analyze`: Analyze Dart code for errors, warnings, and style issues.
-   `flutter test`: Run unit and widget tests in the project.
-   `flutter clean`: Remove the `build/` directory and other build artifacts to start fresh.

### Flutter: Building Applications
-   `flutter build apk`: Build a standard Android APK. Add `--release` for a release version.
-   `flutter build appbundle`: Build an Android App Bundle, required for publishing to Google Play.
-   `flutter build ios`: Build an iOS application archive (requires a macOS machine with Xcode).

### Firebase: Emulators
-   `firebase emulators:start`: Start the Firebase emulators for local development and testing. This typically includes emulators for Authentication, Firestore, Realtime Database, Functions, and Hosting, as configured in `firebase.json`.

### Firebase: Deployment
-   `firebase deploy --only functions`: Deploy your Cloud Functions.
-   `firebase deploy --only database`: Deploy Realtime Database rules (as specified in `firebase.json`).
-   `firebase deploy --only hosting`: Deploy your web app or static assets to Firebase Hosting.
-   `firebase deploy`: Deploy all Firebase resources (functions, database rules, hosting, etc.) as configured in `firebase.json`.

### Firebase Functions: Local Development (run from the `functions` directory)
-   `npm run lint`: Run the linter for the Cloud Functions TypeScript/JavaScript code.
    ```bash
    cd functions
    npm run lint
    cd ..
    ```
-   `npm run build`: Compile the Cloud Functions TypeScript code to JavaScript.
    ```bash
    cd functions
    npm run build
    cd ..
    ```

## Contributing
Contributions are welcome! Please open an issue or submit a pull request if you have any improvements or bug fixes.

=======
## License
=======
This project is licensed under the MIT License.