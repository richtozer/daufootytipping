# Android CI/CD Setup Guide

This guide explains how to set up the GitHub Actions workflow for automated Android builds.

## 🚀 What the Workflow Does

### Branches & Triggers
- **android-ci.yml**: Manual only. Runs tests and build jobs. No Play deploy.
- **android-basic.yml**: Manual only. Builds artifacts and can deploy to Play tracks.
- **No push/PR auto triggers**: Android workflows are intentionally manual to control GitHub Actions usage.

### Build Process
1. **android-ci.yml**:
   - Test Job: Runs `flutter analyze` and `flutter test`
   - Build Job: Creates APK/AAB artifacts
2. **android-basic.yml**:
   - Build job: Creates APK/AAB artifacts
   - Deploy internal: Uploads to Play Internal when run on `testing`
   - Deploy production: Uploads to Play Production only when manually run on `main` with `production=true`

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

#### Required for Google Play Store deployment (android-basic.yml only)
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
2. Run `android-ci.yml` manually from GitHub Actions and confirm it builds/tests
3. Add `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` when you are ready for deploys
4. Run `android-basic.yml` on `testing` to upload to Google Play internal track

## 🔄 Workflow Status

Check your builds at: `https://github.com/YOUR_USERNAME/daufootytipping/actions`

## 🐛 Troubleshooting

### Common Issues:
- **Build fails**: Check Flutter version, dependencies
- **Signing fails**: Verify keystore secrets and Android configuration
- **Play Store fails**: Verify service account permissions and app bundle format

### Debug Tips:
- Enable debug logging in workflow: `ACTIONS_STEP_DEBUG: true`
- Check artifact downloads for build outputs
- Review Play Console logs for deployment issues
