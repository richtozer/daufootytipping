#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

## Install Flutter using git.
#git clone https://github.com/flutter/flutter.git --branch stable
#export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter using curl.
curl -sLO "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.29.0-stable.zip"
unzip -qq flutter_macos_3.29.0-stable.zip -d $HOME

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Install CocoaPods using Homebrew.
HOMEBREW_NO_AUTO_UPDATE=1 # disable homebrew's automatic updates.
brew install cocoapods

# Install CocoaPods dependencies.
cd ios && pod install # run `pod install` in the `ios` directory.

exit 0