# Android release preparation

The Play Store release must use a private upload key. Do not commit the key or
`key.properties`, and keep a secure backup of the keystore and its passwords.

## Create the upload key

Run this in PowerShell from the repository root. Replace the alias if desired.
`keytool` will prompt for passwords; do not put passwords in the command or send
them in chat.

```powershell
keytool -genkeypair -v `
  -keystore android\hifzai-upload-key.jks `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias hifzai-upload
```

Create `android\key.properties` with the values you used:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=hifzai-upload
storeFile=hifzai-upload-key.jks
```

The Gradle release build refuses to run when any signing value is missing. The
keystore and properties file are ignored by Git.

## Build the Play Store bundle

From the repository root:

```powershell
flutter pub get
flutter build appbundle --release
```

The Android App Bundle is written to
`build\app\outputs\bundle\release\app-release.aab`. Test this bundle on a device
or through a Play Console internal testing track before production release.

The Play Console listing, screenshots, app-access instructions, content rating,
data-safety answers, and public privacy-policy URL must also be completed. Review
Google Play's payments policy before enabling any external checkout for digital
features; this project currently uses Yoco, which is not a Play Billing
integration.
