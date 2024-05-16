dar#!/bin/bash

# Function to delete iOS Pods
delete_ios_pods() {
    echo "Deleting iOS Pods..."
    cd ios
    rm -rf Pods
    cd ..
    echo "iOS Pods deleted."
}

# Function to delete Android Gradle files
delete_android_gradle() {
    echo "Deleting Android Gradle files..."
    rm -rf android/.gradle
    rm -rf android/app/build
    echo "Android Gradle files deleted."
}

# Function to clean Flutter project
clean_flutter_project() {
    echo "Cleaning Flutter project..."
    flutter clean
    echo "Flutter project cleaned."
}

# Main script
echo "Done. Cleaning all projects."
for pubspec_file in $(find . -name "pubspec.yaml"); do
    DIR=$(dirname "${pubspec_file}")
    echo "Cleaning ${DIR}..."
    (cd "$DIR" && delete_ios_pods && delete_android_gradle && clean_flutter_project)
done
echo "DONE!"