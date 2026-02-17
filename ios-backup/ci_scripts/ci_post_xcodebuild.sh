#!/bin/zsh

# 1. Create 'ci_scripts' folder in your main project directory
# 2. Create 'ci_post_xcodebuild.sh' inside of it
# 3. Make it an executable by running 'chmod +x $ci_post_xcodebuild.sh'

set -e # fails build if any command fails

if [ ${CI_XCODEBUILD_EXIT_CODE} != 0 ]
then
    exit 1
fi

if [[ -n $CI_APP_STORE_SIGNED_APP_PATH ]]; # checks if there is an AppStore signed archive after running xcodebuild
then
    PUBSPEC_VERSION=$(awk '/^version:/{print $2; exit}' "$CI_PRIMARY_REPOSITORY_PATH/pubspec.yaml")
    if [[ -z "$PUBSPEC_VERSION" ]]; then
        echo "Failed to read version from pubspec.yaml"
        exit 1
    fi
    VERSION="${PUBSPEC_VERSION%%+*}"
    BUILD_TAG="${PUBSPEC_VERSION##*+}"
    TAG_NAME="${CI_PRODUCT:-"ios-"}-$VERSION+$BUILD_TAG"

    if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        echo "Tag $TAG_NAME already exists. Skipping tag push."
    else
        git tag "$TAG_NAME"
        git push --tags https://${GIT_AUTH}@github.com/richtozer/daufootytipping.git
    fi
fi

# use workflow Environment to configure your GIT_AUTH variable - username:personalAccessToken
# see https://gist.github.com/Berhtulf/ab3fb663187e7644410c0401b207aa45 for more information
