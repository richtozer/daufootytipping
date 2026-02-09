# Android CI/CD Setup Guide

This guide explains how to set up the GitHub Actions workflow for Android builds and optional Google Play deployment.

## 🚀 What the Workflow Does

### Branches & Triggers
- **android-play.yml**: Single manual workflow for Android.
- **No push/PR auto triggers**: Workflow is intentionally manual to control GitHub Actions usage.

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
4. Run `android-play.yml` on `testing` with `deploy_track=internal`
5. Run `android-play.yml` on `main` with `deploy_track=production` for production releases

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
