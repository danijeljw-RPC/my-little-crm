# Android release guide

How to sign, build and publish the My Little CRM Android APK so users can
download and install it directly (sideloading).

**Quick version:** bump `pubspec.yaml`, add a `CHANGELOG.md` section, commit and
push, then run `scripts/release.sh --publish`. Everything else here explains
the setup behind that.

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

## 3. Debug vs release signing (already set up)

Release signing is **opt-in**. `android/app/build.gradle.kts` only uses the
release key when the build runs with `MLC_RELEASE_SIGNING=1`, and only
`scripts/release.sh` sets that. Every other build uses the debug key:

| How you build | Signed with |
|---|---|
| `scripts/run.sh <device>` / `.\scripts\run.ps1 <device>` | debug key |
| `scripts/run.sh <device> --release` / `flutter run --release` | debug key |
| `flutter build apk` (any mode) | debug key |
| **`scripts/release.sh`** | **release key** (verified) |

Day-to-day development and the run scripts work exactly as before. The release
key is only used when you deliberately cut a release. If
`MLC_RELEASE_SIGNING=1` is set but `android/key.properties` is missing or
incomplete, the build fails instead of silently using the debug key.

The signing setup lives **inside the single existing `android { }` block**.
Don't add a second `android { }` block: Gradle applies both, and whichever comes
last wins.

> **Debug and release builds can't replace each other on one device.** They're
> signed with different keys, so Android won't install one over the other. If
> you install a published release on your phone, a later `scripts/run.sh` on
> that phone makes Flutter uninstall it first, **which deletes the app's data**.
> Use an emulator or a separate device for development, or uninstall
> deliberately.

## 4. Build and publish with `scripts/release.sh`

Before each release:

1. Bump the version in `pubspec.yaml`. The build number after `+` must go up
   every release (`1.0.0+15` → `1.0.1+16`); Android won't install an update
   whose build number is lower than or equal to the installed one.
2. Add a `## [x.y.z] - YYYY-MM-DD` section to [`CHANGELOG.md`](../CHANGELOG.md).
3. Commit and push.

Then:

```bash
scripts/release.sh                     # build + verify only, nothing published
scripts/release.sh --publish           # build, verify, create GitHub release v<version>
scripts/release.sh --publish --draft   # same, as a draft to review on GitHub first
```

The script:

1. Reads the version from `pubspec.yaml`.
2. With `--publish`, checks *before* the slow build that `gh` is logged in,
   `CHANGELOG.md` has a section for the version, tag `v<version>` doesn't exist
   yet, there are no uncommitted changes, and `HEAD` is pushed.
3. Builds with `MLC_RELEASE_SIGNING=1 flutter build apk --release`: one
   universal APK that works on any phone.
4. Runs `apksigner verify` and **stops if the APK is signed with the debug key**.
5. Writes to `dist/` (git-ignored): `my-little-crm-<version>.apk`, its
   `.sha256` checksum, and `-notes.md` taken from `CHANGELOG.md`.
6. With `--publish`, runs `gh release create v<version>` on the current commit
   with the APK, checksum and notes.

The release certificate is
`CN=Danijel-James Wynyard-McClay, OU=Mobile, O=RePass Cloud Pty Ltd, L=Sydney, ST=NSW, C=AU`.
To check an APK by hand:

```bash
~/Library/Android/sdk/build-tools/<version>/apksigner verify --print-certs dist/my-little-crm-<version>.apk
```

## 5. Host it

| Option | Effort | Notes |
|---|---|---|
| **GitHub Releases** (recommended) | Lowest | `scripts/release.sh --publish` does it. Free, gives a permanent download link, and works with **Obtainium**, an app that auto-updates sideloaded APKs from GitHub Releases. The repo must be public, or the release assets need to be hosted somewhere public. |
| Cloudflare R2 or Pages | Low–medium | Upload the files from `dist/`. Gives you a custom domain such as `download.example.com/mylittlecrm.apk` and a landing page. Serve the file with `Content-Type: application/vnd.android.package-archive`. |
| Google Play | Highest | Needs a US$25 one-off developer account and an **AAB** (`flutter build appbundle`) instead of an APK. New personal accounts must run a closed test with 12+ testers for 14 days. Updates and trust are handled for you. |
| F-Droid | Medium | Fits an offline, privacy-focused app, but F-Droid builds from your source under its own rules. |

## What users do to install

1. Open the download link on their phone and download the APK.
2. Allow "Install unknown apps" for their browser or file manager when Android
   asks.
3. Tap the file and choose **Install**. Play Protect may warn that the developer
   is unknown. That's normal for sideloaded apps and they can install anyway.

Without Google Play there are no automatic updates. Users re-download each
release, or use Obtainium to track the GitHub Releases page.

## Release checklist

- [ ] `pubspec.yaml` version and build number bumped
- [ ] `CHANGELOG.md` has a section for the new version
- [ ] Changes committed and pushed
- [ ] `scripts/release.sh` succeeded (signer is the release certificate)
- [ ] `scripts/release.sh --publish` created the GitHub release
- [ ] Installed over the previous release on a real device (data preserved)
