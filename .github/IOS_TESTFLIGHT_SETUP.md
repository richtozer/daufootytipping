# iOS TestFlight GitHub Actions Setup

This guide covers the iOS TestFlight workflow in `.github/workflows/ios-testflight.yml`.

## What it does

1. Builds an iOS IPA on a GitHub macOS runner.
2. Uses `pubspec.yaml` as the version/build source (`version: x.y.z+N`).
3. Uploads the IPA to TestFlight when configured to do so.

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

### Automatic (recommended)

1. From `development` with a clean working tree, run:
   - `scripts/promote-to-testing.sh`
2. Push both branches:
   - `git push origin testing development`
3. Workflow runs automatically on `testing` push.
4. Check TestFlight build processing in App Store Connect.

### Manual

1. Open GitHub `Actions`.
2. Select `iOS TestFlight Build`.
3. Click `Run workflow`.
4. Choose branch.
5. Set:
   - `upload_to_testflight`: `true` to upload, `false` to build artifact only
   - `changelog`: optional release notes text

## Notes

- The workflow runs automatically on `testing` pushes and also supports manual `workflow_dispatch`.
- The runner is pinned to `macos-26` and enforces Xcode/iOS SDK 26.
- Build number and version are pulled from `pubspec.yaml`.
- Keep Xcode Cloud release/upload workflows disabled if you want one release pipeline.

## iOS Release Runbook

1. Run `scripts/promote-to-testing.sh` from `development` with a clean working tree.
2. Push both branches with `git push origin testing development`.
3. In GitHub Actions, verify `iOS TestFlight Build` succeeded.
4. In App Store Connect, verify the new build appears in TestFlight and finishes processing.

## Promotion Script Notes

- `scripts/promote-to-testing.sh` fails fast unless:
  - current branch is `development`
  - working tree is clean (tracked, staged, and untracked)
- It merges `development` into `testing`, returns to `development`, bumps build number, and commits the bump.
