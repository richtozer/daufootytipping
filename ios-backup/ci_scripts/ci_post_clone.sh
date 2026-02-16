#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

# Read build metadata from pubspec.yaml (single source of truth).
PUBSPEC_VERSION=$(awk '/^version:/{print $2; exit}' pubspec.yaml)
if [ -z "$PUBSPEC_VERSION" ]; then
  echo "Failed to read version from pubspec.yaml"
  exit 1
fi
FLUTTER_BUILD_NAME="${PUBSPEC_VERSION%%+*}"
FLUTTER_BUILD_NUMBER="${PUBSPEC_VERSION##*+}"

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Install CocoaPods using Homebrew.
HOMEBREW_NO_AUTO_UPDATE=1 # disable homebrew's automatic updates.
brew install cocoapods

# Install CocoaPods dependencies.
cd ios && pod install # run `pod install` in the `ios` directory.

cd ..
flutter build ios --config-only --release --build-name "$FLUTTER_BUILD_NAME" --build-number "$FLUTTER_BUILD_NUMBER"

exit 0
