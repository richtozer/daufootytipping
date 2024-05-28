# 1. Create 'ci_scripts' folder in your main project directory
# 2. Create 'ci_post_xcodebuild.sh' inside of it
# 3. Make it an executable by running 'chmod +x $ci_post_xcodebuild.sh'

set -e # fails build if any command fails

if [ ${CI_XCODEBUILD_EXIT_CODE} != 0 ]
then
    exit 1
fi

if [[ - $CI_APP_STORE_SIGNED_APP_PATH ]]; # checks if there is an AppStore signed archive after running xcodebuild
then
    BUILD_TAG=${CI_BUILD_NUMBER}
    VERSION=$(cat ../${CI_PRODUCT}.xcodeproj/project.pbxproj | grep -m1 'MARKETING_VERSION' | cut -d'=' -f2 | tr -d ';' | tr -d ' ')

    git tag ${CI_PRODUCT}/Release/$VERSION\($BUILD_TAG\)

    git push --tags https://${GIT_AUTH}@github.com/USER_NAME/REPOSITORY.git
fi

# use workflow Environment to configure your GIT_AUTH variable - username:personalAccessToken
# see https://gist.github.com/Berhtulf/ab3fb663187e7644410c0401b207aa45 for more information