# Android release guide

How to sign, build and publish the My Little CRM Android APK so users can
download and install it directly (sideloading).

## 1. Release keystore (one-off; already done)

The release key lives outside the repo at
`~/.android-keys/mylittlecrm-release.jks` (alias `mylittlecrm`). It was created
with:

```bash
mkdir -p ~/.android-keys && chmod 700 ~/.android-keys

read -s "KS_PASS?Keystore password: "; echo
export KS_PASS

keytool -genkeypair -v \
  -keystore ~/.android-keys/mylittlecrm-release.jks \
  -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias mylittlecrm \
  -dname "CN=Danijel-James Wynyard-McClay, OU=Mobile, O=RePass Cloud Pty Ltd, L=Sydney, ST=NSW, C=AU" \
  -storepass:env KS_PASS \
  -keypass:env KS_PASS

unset KS_PASS
```

> **Back up the `.jks` file and its password in a password manager.** If you
> lose either one, you can't ship updates to existing installs: Android only
> installs an update over an existing app if both are signed with the same key.
> Users would have to uninstall, and an uninstall deletes their local data.

`.gitignore` (`android/.gitignore`) already excludes `*.jks`, `*.keystore` and
`key.properties`. Never commit either file.

To check the key:

```bash
keytool -list -v -keystore ~/.android-keys/mylittlecrm-release.jks
```

## 2. Create `android/key.properties` (git-ignored)

```properties
storePassword=<keystore password>
keyPassword=<same keystore password>
keyAlias=mylittlecrm
storeFile=/Users/danijeljw/.android-keys/mylittlecrm-release.jks
```

- A PKCS12 keystore has a single password, so `storePassword` and
  `keyPassword` are the same value.
- `storeFile` must be an absolute path. Gradle does not expand `~`.

## 3. Signing config in `android/app/build.gradle.kts` (already done)

`android/app/build.gradle.kts` signs release builds with this key whenever
`android/key.properties` exists. The signing setup lives **inside the single
existing `android { }` block**. Don't add a second `android { }` block: Gradle
applies both, and whichever comes last wins. That's how a release build ends up
signed with the debug key.

```kotlin
import java.io.FileInputStream
import java.util.Properties

plugins { /* unchanged */ }

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    // namespace, compileSdk, defaultConfig, ... unchanged

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: android/key.properties not found; ...")
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

Without `key.properties`, release builds fall back to the debug key so
`flutter run --release` still works. The warning only appears with
`flutter build -v`, so **always run the `apksigner` check in step 4** before
distributing.

## 4. Build

Bump the build number in `pubspec.yaml` before every release (for example
`1.0.0+15` → `1.0.0+16`). Android won't install an update whose `versionCode`
is lower than or equal to the installed one.

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk  (universal, works on any phone)
```

`--split-per-abi` produces smaller per-CPU APKs. For direct downloads, one
universal APK is simpler because users don't have to know their phone's CPU
type.

Verify the signature and record a checksum:

```bash
# apksigner is in the Android SDK build-tools
~/Library/Android/sdk/build-tools/<version>/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk

shasum -a 256 build/app/outputs/flutter-apk/app-release.apk
```

The certificate shown should be `CN=Danijel-James Wynyard-McClay, ...`, not
`CN=Android Debug`. Publish the SHA-256 checksum with the release so users can
confirm the file is genuine.

## 5. Host it

| Option | Effort | Notes |
|---|---|---|
| **GitHub Releases** (recommended) | Lowest | The repo is already on GitHub. Free, gives a permanent download link, and works with **Obtainium**, an app that auto-updates sideloaded APKs from GitHub Releases. The repo must be public, or the release assets need to be hosted somewhere public. |
| Cloudflare R2 or Pages | Low–medium | Gives you a custom domain such as `download.example.com/mylittlecrm.apk` and a landing page. Serve the file with `Content-Type: application/vnd.android.package-archive`. |
| Google Play | Highest | Needs a US$25 one-off developer account and an **AAB** (`flutter build appbundle`) instead of an APK. New personal accounts must run a closed test with 12+ testers for 14 days. Updates and trust are handled for you. |
| F-Droid | Medium | Fits an offline, privacy-focused app, but F-Droid builds from your source under its own rules. |

### Publishing on GitHub Releases

Release notes come from [`CHANGELOG.md`](../CHANGELOG.md):

```bash
VERSION=1.0.0
APK=build/app/outputs/flutter-apk/app-release.apk
cp "$APK" "my-little-crm-$VERSION.apk"
shasum -a 256 "my-little-crm-$VERSION.apk" > "my-little-crm-$VERSION.apk.sha256"

awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {f=1; next} /^## \[|^\[[0-9.]+\]:/ {f=0} f' \
  CHANGELOG.md > /tmp/notes.md

gh release create "v$VERSION" \
  "my-little-crm-$VERSION.apk" "my-little-crm-$VERSION.apk.sha256" \
  --title "My Little CRM $VERSION" --notes-file /tmp/notes.md
```

## What users do to install

1. Open the download link on their phone and download the APK.
2. Allow "Install unknown apps" for their browser or file manager when Android
   asks.
3. Tap the file and choose **Install**. Play Protect may warn that the developer
   is unknown. That's normal for sideloaded apps and they can install anyway.

Without Google Play there are no automatic updates. Users re-download each
release, or use Obtainium to track the GitHub Releases page.

## Release checklist

- [ ] `pubspec.yaml` build number bumped
- [ ] `CHANGELOG.md` has a section for the new version
- [ ] `flutter build apk --release` succeeded
- [ ] `apksigner verify --print-certs` shows the release certificate
- [ ] SHA-256 checksum generated
- [ ] GitHub release created with the APK, checksum and notes
- [ ] Installed over the previous version on a real device (data preserved)
