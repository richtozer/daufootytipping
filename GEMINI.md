# DAU Footy Tipping App - Claude Code Assistant Guide

## Project Overview
DAU Footy Tipping is a Flutter application designed to manage and display footy tipping competitions, supporting AFL and NRL leagues. The app includes user authentication, game tipping, scoring, league management, and comprehensive statistics tracking.

## Project Structure
```
lib/              
├── models/              # Data models (games, tips, teams, competitions, etc.)
├── pages/               # UI pages organized by functionality
│   ├── admin_daucomps/  # Admin interfaces for managing competitions
│   ├── admin_teams/     # Team management interfaces
│   ├── admin_tippers/   # Tipper management and merging
│   ├── user_auth/       # Authentication pages
│   └── user_home/       # Main user interface (tips, stats, profiles)
├── services/            # Business logic and external service integrations
├── view_models/         # State management using Provider pattern
├── theme_data.dart      # App theming configuration
└── firebase_options.dart # Firebase configuration

functions/               # Firebase Cloud Functions (TypeScript/Node.js)
test/                   # Unit and widget tests with mock data
assets/                 # Static assets including team logos and icons
android/ios/web/        # Platform-specific code and configurations
```

## View Model Dependency Tree
```
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
```

## Technology Stack
- **Frontend**: Flutter (Dart SDK >=3.1.5 <4.0.0)
- **Backend**: Firebase (Realtime Database, Firestore, Authentication, Cloud Functions, Messaging)
- **State Management**: Provider pattern with dependency injection
- **Testing**: Flutter test framework with Mockito
- **Build Tools**: Flutter build system with build_runner for code generation

## Development Commands
```bash
# Essential Flutter commands
flutter pub get                    # Install dependencies
flutter run                       # Run app in development
flutter test                      # Run all tests
flutter clean                     # Clean build cache

# Build commands
flutter build appbundle           # Build Android App Bundle
flutter build apk --release       # Build Android APK
flutter build ios --release       # Build iOS release

# Code generation
flutter packages pub run build_runner build  # Generate JSON serialization code

# Firebase commands
firebase emulators:start          # Start Firebase emulators
firebase deploy --only hosting    # Deploy to Firebase hosting
```

## Key Features
- **Multi-league Support**: AFL and NRL competitions
- **User Authentication**: Firebase Auth with Google/Apple sign-in
- **Real-time Tipping**: Live game scoring and tip submission
- **Competition Management**: Admin tools for managing competitions, rounds, and fixtures
- **Statistics & Analytics**: Comprehensive leaderboards and performance tracking
- **Push Notifications**: Game reminders and score updates
- **Team Management**: Team logos, colors, and game history
- **Responsive Design**: Optimized for mobile platforms

## Firebase Integration
- **Firebase Realtime Database**: Primary data storage for real-time updates
- **Firestore**: Secondary storage for complex queries
- **Firebase Auth**: User authentication and authorization
- **Cloud Functions**: Server-side logic for notifications and data processing
- **Firebase Messaging**: Push notifications for game reminders
- **Analytics & Crashlytics**: App performance monitoring

## Key Dependencies
```yaml
# Core Firebase
firebase_core: ^3.4.0
firebase_database: ^11.1.0
firebase_auth: ^5.2.0
firebase_messaging: ^15.1.0

# State Management
provider: ^6.1.1
get_it: ^8.0.3
watch_it: ^1.4.0

# UI Components
flex_color_scheme: ^8.1.0
data_table_2: ^2.5.10
modal_bottom_sheet: ^3.0.0

# HTTP & Data
dio: ^5.3.4
http: ^1.1.2
json_annotation: ^4.8.1
```

## Testing Strategy
- **Unit Tests**: View models, services, and business logic
- **Widget Tests**: UI components and user interactions
- **Integration Tests**: End-to-end user flows
- **Mock Data**: Comprehensive test data in `test/data/` directory
- **Mocking**: Mockito for dependency injection testing

## Architecture Patterns
- **MVVM**: Model-View-ViewModel pattern with Provider
- **Repository Pattern**: Data access abstraction
- **Service Layer**: Business logic separation
- **Dependency Injection**: Using get_it for service location

## Important Configuration
- **App Version**: 1.2.20+436 (managed in pubspec.yaml)
- **Min SDK**: Android 21, iOS deployment target varies
- **Firebase Config**: Platform-specific configuration files included
- **App Icons**: Adaptive icons configured for all platforms

## Learning Resources
- [Firebase Realtime Database Tutorial](https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw) - Understanding the database structure used in this project

## Development Notes
- Uses Provider pattern for state management throughout the app
- Firebase Realtime Database is the primary data store
- Platform-specific code exists for iOS, Android, Web, and Desktop
- Cloud Functions handle server-side operations like notifications
- Mock data and comprehensive test coverage for reliable development