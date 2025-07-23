# Android CI/CD Setup Guide

This guide explains how to set up the GitHub Actions workflow for automated Android builds.

## 🚀 What the Workflow Does

### Branches & Triggers
- **Testing Branch**: Builds debug APK, distributes to Firebase App Distribution
- **Main Branch**: Builds release APK + AAB, deploys to Google Play Store (Internal Testing)
- **Pull Requests**: Runs tests and analysis only
- **Manual**: Can be triggered manually via GitHub UI

### Build Process
1. **Test Job**: Runs `flutter analyze` and `flutter test`
2. **Build Job**: Creates APK (debug/release) and AAB (main branch only)
3. **Distribute Job**: Sends testing builds to Firebase App Distribution
4. **Deploy Job**: Uploads release builds to Google Play Store

## 🔧 Required Setup

### 1. GitHub Repository Secrets

Go to your repo → Settings → Secrets and variables → Actions, then add:

#### For Firebase App Distribution (Optional)
```
FIREBASE_APP_ID_ANDROID=1:123456789:android:abcdef123456
FIREBASE_SERVICE_ACCOUNT_KEY={"type": "service_account", "project_id": "..."}
```

#### For Google Play Store Deployment (Optional)
```
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON={"type": "service_account", "project_id": "..."}
```

### 2. Firebase App Distribution Setup (Optional)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project → App Distribution
3. Add your Android app if not already added
4. Go to Project Settings → Service Accounts
5. Generate new private key for "Firebase Admin SDK"
6. Copy the JSON content to `FIREBASE_SERVICE_ACCOUNT_KEY` secret

### 3. Google Play Store Setup (Optional)

1. Go to [Google Play Console](https://play.google.com/console/)
2. Go to Setup → API access
3. Create or link a Google Cloud project
4. Create a service account in Google Cloud Console
5. Download the JSON key file
6. Copy the JSON content to `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret
7. In Play Console, grant the service account "Release Manager" permissions

### 4. Android App Signing

For release builds, you'll need to configure app signing:

#### Option A: Upload Key (Recommended)
1. Generate a signing key:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Add to GitHub secrets:
   ```
   ANDROID_KEYSTORE_BASE64=<base64-encoded-keystore-file>
   ANDROID_KEY_ALIAS=upload
   ANDROID_KEY_PASSWORD=<your-key-password>
   ANDROID_STORE_PASSWORD=<your-keystore-password>
   ```
3. Update workflow to sign APK/AAB (see signing section below)

#### Option B: Google Play App Signing (Easier)
- Let Google Play manage signing
- Upload unsigned AAB files
- No additional secrets needed

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

## 🔐 Adding Signing to Workflow (If Needed)

If you need signed builds, add this step before building:

```yaml
- name: Configure Keystore
  run: |
    echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > android/app/keystore.jks
    echo "storeFile=keystore.jks" >> android/key.properties
    echo "keyAlias=${{ secrets.ANDROID_KEY_ALIAS }}" >> android/key.properties
    echo "storePassword=${{ secrets.ANDROID_STORE_PASSWORD }}" >> android/key.properties
    echo "keyPassword=${{ secrets.ANDROID_KEY_PASSWORD }}" >> android/key.properties
```

And update your `android/app/build.gradle`:
```gradle
android {
    ...
    signingConfigs {
        release {
            if (project.hasProperty('android.injected.signing.store.file')) {
                storeFile file(project.property('android.injected.signing.store.file'))
                storePassword project.property('android.injected.signing.store.password')
                keyAlias project.property('android.injected.signing.key.alias')
                keyPassword project.property('android.injected.signing.key.password')
            } else {
                def keystoreProperties = new Properties()
                def keystorePropertiesFile = rootProject.file('key.properties')
                if (keystorePropertiesFile.exists()) {
                    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
                    storeFile file(keystoreProperties['storeFile'])
                    storePassword keystoreProperties['storePassword']
                    keyAlias keystoreProperties['keyAlias']
                    keyPassword keystoreProperties['keyPassword']
                }
            }
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## 🎯 Getting Started (Minimal Setup)

1. **Just Testing**: The workflow will run tests on every push - no secrets needed
2. **Build Artifacts**: APK/AAB files will be uploaded as GitHub artifacts - no secrets needed
3. **Firebase Distribution**: Add Firebase secrets for beta testing
4. **Play Store**: Add Google Play secrets for automated releases

## 🔄 Workflow Status

Check your builds at: `https://github.com/YOUR_USERNAME/daufootytipping/actions`

## 🐛 Troubleshooting

### Common Issues:
- **Build fails**: Check Flutter version, dependencies
- **Signing fails**: Verify keystore secrets and Android configuration
- **Firebase fails**: Check Firebase project ID and service account permissions
- **Play Store fails**: Verify service account permissions and app bundle format

### Debug Tips:
- Enable debug logging in workflow: `ACTIONS_STEP_DEBUG: true`
- Check artifact downloads for build outputs
- Review Firebase/Play Console logs for deployment issues