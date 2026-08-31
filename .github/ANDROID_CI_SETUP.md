# Android CI/CD Setup Guide

This guide explains how to set up the GitHub Actions workflow for Android builds and optional Google Play deployment.

## 🚀 What the Workflow Does

### Branches & Triggers
- **android-play.yml**: Runs automatically on pushes to `testing` and also supports manual dispatch.
- **Automatic testing deploys**: A push to `testing` builds Android and uploads the AAB to the Play `internal` track.
- **Manual deploys**: Use `workflow_dispatch` for `none`, `internal`, or `production` when you need to run it explicitly.

### Build Process
1. **Validate dispatch**:
   - Ensures `deploy_track` matches branch policy:
   - `internal` only from `testing`
   - `production` only from `main`
2. **Build job**:
   - Runs `flutter analyze` and `flutter test`
   - Builds APK and AAB artifacts
3. **Deploy jobs**:
   - Optional Play upload based on `deploy_track` input (`none`, `internal`, `production`)

## 🔧 Required Setup

### 1. GitHub Repository Secrets

Go to your repo → Settings → Secrets and variables → Actions, then add:

#### Required for Android signing (release builds on `testing`/`main`)
```
ANDROID_KEYSTORE_BASE64=<base64-encoded-upload-keystore>
ANDROID_KEY_ALIAS=upload
ANDROID_KEY_PASSWORD=<your-key-password>
ANDROID_STORE_PASSWORD=<your-keystore-password>
```

#### Required for Google Play Store deployment (android-play.yml only)
```
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON={"type": "service_account", "project_id": "..."}
```

### 2. Google Play Store Setup

1. Go to [Google Play Console](https://play.google.com/console/)
2. Go to Setup → API access
3. Create or link a Google Cloud project
4. Create a service account in Google Cloud Console
5. Download the JSON key file
6. Copy the JSON content to `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret
7. In Play Console, grant the service account "Release Manager" permissions

### 3. Android App Signing

1. Use your existing upload keystore (`upload-keystore.jks`) from local development.
2. Create base64 content:
   ```bash
   base64 -i upload-keystore.jks | pbcopy
   ```
3. Add the copied value as `ANDROID_KEYSTORE_BASE64` in GitHub Actions secrets.
4. Add the keystore alias and passwords as `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, and `ANDROID_STORE_PASSWORD`.
5. Create a local `android/key.properties` from `android/key.properties.example`. This file is ignored by Git and should stay local only.

## 📦 Release Notes Directory (Optional)

Create release notes for Play Store:
```
android/
└── release-notes/
    ├── en-US/
    │   └── default.txt
    ├── es-ES/
    │   └── default.txt
    └── ...
```

## 🎯 Getting Started (Minimal Setup)

1. Add required signing secrets (`ANDROID_*`)
2. Run `android-play.yml` manually with `deploy_track=none` and confirm build/tests
3. Add `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` when you are ready for deploys
4. Promote changes from `development` to `testing` with:
   - `scripts/promote-to-testing.sh`
5. The script pushes `testing`, which triggers the automatic Android internal deploy
6. Run `android-play.yml` on `main` with `deploy_track=production` for production releases

## 🔁 Branch Promotion Script

- Script: `scripts/promote-to-testing.sh`
- Run from `development` only, with a clean working tree.
- It will:
  - merge `development` into `testing`
  - trigger the Android GitHub Actions workflow via the resulting `testing` push
  - switch back to `development`
  - bump `pubspec.yaml` build number
  - commit the bump on `development`

## 🔄 Workflow Status

Check your builds at: `https://github.com/YOUR_USERNAME/daufootytipping/actions`

## Android Resume Diagnostic Testing

The Android workflow compiles builds from `testing` with:

```text
--dart-define=ANDROID_RESUME_DIAGNOSTICS=true
```

Builds from `main` explicitly set the same value to `false`, so the diagnostic recorder, native RTDB logging, and admin diagnostics page are not included in production behavior.

### Install the internal build

1. Wait for **Android Play Build and Deploy** on the `testing` branch to finish successfully.
2. On the physical Android test device, use a Google account enrolled in the app's Play internal-testing track.
3. Open Google Play, update the app, and confirm the installed version/build matches the `testing` branch version in `pubspec.yaml`.
4. Sign in with an app administrator account. The Profile admin options should contain **Android Resume Diagnostics**. Its presence confirms the diagnostic flag is active.

### Capture the long-background failure

1. Open the Tips page while the target game has live/interim scores and record the displayed values and UTC/local time.
2. Press Home or lock the screen. Do not swipe the app away, force-stop it, or reboot the device.
3. While the app remains backgrounded, confirm the backend fixture changes to finalized official scores.
4. Leave the existing app process backgrounded for the intended interval. Test a shorter Doze/device-idle cycle first, then repeat overnight or for several days.
5. Resume directly into the existing app process and record whether the Tips page changes from interim to finalized without navigation or force quit.
6. Before force-quitting, open **Profile → Admin functions → Android Resume Diagnostics**, tap reload, then copy the newline-delimited JSON trace.
7. Save the trace with the device model, Android version, app build, background duration, network type/changes, battery optimization setting, exact game keys, and screenshots.
8. After preserving the stale-resume trace, force-quit and reopen the app. Copy the trace again so the cold-start sequence can be compared with the failed resume.

The first question for every run is whether the stale-data problem still reproduces with diagnostics enabled. The diagnostic `/.info/connected` observer can influence RTDB activity. If the diagnostic build does not reproduce, do not treat that as proof of a fix; compare it with a capture build that omits that observer while retaining native logging and the remaining breadcrumbs.

Traces survive force quit. Normal events are retained for 14 days, anomalous events for 30 days, and startup pruning enforces the 5,000-event limit.

## 🐛 Troubleshooting

### Common Issues:
- **Build fails**: Check Flutter version, dependencies
- **Signing fails**: Verify keystore secrets and Android configuration
- **Play Store fails**: Verify service account permissions and app bundle format

### Debug Tips:
- Enable debug logging in workflow: `ACTIONS_STEP_DEBUG: true`
- Check artifact downloads for build outputs
- Review Play Console logs for deployment issues
