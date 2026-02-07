# iOS TestFlight GitHub Actions Setup

This guide covers the manual iOS TestFlight workflow in `.github/workflows/ios-testflight.yml`.

## What it does

1. Builds an iOS IPA on a GitHub macOS runner.
2. Uses `pubspec.yaml` as the version/build source (`version: x.y.z+N`).
3. Optionally uploads the IPA to TestFlight.

## Required GitHub Secrets

Add these under repo `Settings` -> `Secrets and variables` -> `Actions`.

### iOS signing secrets

```
IOS_BUILD_CERTIFICATE_BASE64=<base64 of Apple Distribution .p12>
IOS_P12_PASSWORD=<password for .p12 certificate>
IOS_BUILD_PROVISION_PROFILE_BASE64=<base64 of App Store .mobileprovision>
IOS_KEYCHAIN_PASSWORD=<random temporary keychain password for CI>
```

Generate the base64 values on macOS:

```bash
base64 -i /path/to/dist-cert.p12 | tr -d '\n' | pbcopy
base64 -i /path/to/profile.mobileprovision | tr -d '\n' | pbcopy
```

### App Store Connect API secrets

```
APP_STORE_CONNECT_ISSUER_ID=<issuer id>
APP_STORE_CONNECT_KEY_ID=<key id>
APP_STORE_CONNECT_API_KEY_P8=<full contents of AuthKey_XXXXXX.p8>
```

## How to run

1. Open GitHub `Actions`.
2. Select `iOS TestFlight Build`.
3. Click `Run workflow`.
4. Choose branch.
5. Set:
   - `upload_to_testflight`: `true` to upload, `false` to build artifact only
   - `changelog`: optional release notes text

## Notes

- The workflow is manual only (`workflow_dispatch`) to avoid accidental uploads.
- Build number and version are pulled from `pubspec.yaml`.
- Keep Xcode Cloud release/upload workflows disabled if you want one release pipeline.
