# Android CI/CD Setup Guide

This guide explains how to set up the GitHub Actions workflow for automated Android builds.

## 🚀 What the Workflow Does

### Branches & Triggers
- **Testing Branch**: Builds debug APK + release AAB, deploys to Google Play Store (Internal Testing)
- **Main Branch**: Builds release APK + AAB, deploys to Google Play Store (Internal Testing)
- **Pull Requests**: Runs tests and analysis only
- **Manual**: Can be triggered manually via GitHub UI

### Build Process
1. **Test Job**: Runs `flutter analyze` and `flutter test`
2. **Build Job**: Creates APK (debug/release) and AAB (testing + main)
3. **Deploy Job**: Uploads AAB builds to Google Play Internal Testing

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

#### Required for Google Play Store deployment
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

1. Add all required secrets (`ANDROID_*` and `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`)
2. Push to `testing`
3. Confirm the workflow builds and uploads to Google Play internal track

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
