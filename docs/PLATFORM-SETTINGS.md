# Platform settings: app identity, copyright and versions

Where each OS platform keeps the app's name, ID, company, copyright, version,
icon and data location, and which tests break if you change them.

`flutter create` only puts these values into the native project files once.
After that, Flutter does **not** keep them in sync, so a rename has to be
made in every file listed below.

`test/platform/platform_identity_test.dart` checks the values in this guide.
It runs in CI as part of `flutter test`. If you change a value on purpose,
update the matching constant at the top of that test.

## Shared values

| Setting | Value | Used by |
| --- | --- | --- |
| App ID | `com.repasscloud.mylittlecrm` | macOS, iOS, Android, Linux |
| Native test target ID | `com.repasscloud.mylittlecrm.RunnerTests` | macOS, iOS |
| Display name | `My Little CRM` | all platforms, plus `lib/app.dart` |
| Company | `RePass Cloud Pty Ltd` | macOS copyright, Windows file properties |
| Binary / package name | `my_little_crm` | `pubspec.yaml`, Windows/Linux executable, Dart imports |
| Version | `pubspec.yaml` → `version:` | all platforms (see [Versions](#versions)) |

> **Changing the app ID or company moves the user's data.** The database is
> stored at `getApplicationSupportDirectory()/crm.sqlite`
> (`lib/data/local/app_database.dart:24`), and every platform builds that
> folder from these settings. After a change, the app opens with an empty
> database, and the old file stays in the old folder. Any change after release
> needs a migration that copies the old file across.
>
> | Platform | Data folder is built from |
> | --- | --- |
> | macOS | bundle ID: `~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>/` |
> | iOS | bundle ID: a new ID is a different app with its own sandbox |
> | Android | `applicationId`: `/data/data/<applicationId>/` |
> | Windows | `Runner.rc` `CompanyName` and `ProductName`: `%APPDATA%\<CompanyName>\<ProductName>\` |
> | Linux | `APPLICATION_ID`: `~/.local/share/<APPLICATION_ID>/` |

## macOS

| What | File | Key / line |
| --- | --- | --- |
| App name (menu bar, Finder, About panel, `.app` name) | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME` (line 8) |
| Bundle ID | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_BUNDLE_IDENTIFIER` (line 11) |
| Copyright, first line (About panel) | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_COPYRIGHT` (line 14) |
| Copyright, second line | `macos/Runner/Info.plist` | `NSHumanReadableCopyright` (line 26) |
| Native test bundle ID | `macos/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER = …RunnerTests` (Debug/Release/Profile) |
| Native test host | `macos/Runner.xcodeproj/project.pbxproj` | `TEST_HOST` (3 places). Must match `PRODUCT_NAME` |
| Minimum macOS | `macos/Runner.xcodeproj/project.pbxproj` | `MACOSX_DEPLOYMENT_TARGET` (currently 12.0) |
| Sandbox / permissions | `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements` | sandbox, user-selected file read/write |
| Icon | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | PNGs + `Contents.json` |

### Copyright on two lines

An `.xcconfig` file can't hold a newline, and `\n` in it is passed through
literally. So the first line stays in `PRODUCT_COPYRIGHT`, and `Info.plist`
adds an XML newline (`&#10;`) before the second line:

```xml
<key>NSHumanReadableCopyright</key>
<string>$(PRODUCT_COPYRIGHT)&#10;All rights reserved.</string>
```

The About panel then shows:

```
Copyright © 2026 RePass Cloud Pty Ltd.
All rights reserved.
```

To check a build: `plutil -p "build/macos/Build/Products/Debug/My Little CRM.app/Contents/Info.plist" | grep -A1 Copyright`

### Renaming the app

`PRODUCT_NAME` sets both the `.app` folder name and the executable name.
`TEST_HOST` in `project.pbxproj` has both names hard-coded, so update all
three `TEST_HOST` lines whenever `PRODUCT_NAME` changes. If you don't, the
native tests fail with *"Could not find test host for RunnerTests"*. (This
happened after the PR #9 rename, and #19 fixes it.)

## iOS

| What | File | Key / line |
| --- | --- | --- |
| Home-screen name | `ios/Runner/Info.plist` | `CFBundleDisplayName` (line 10) |
| Short bundle name (internal, rarely shown) | `ios/Runner/Info.plist` | `CFBundleName` (line 18): `my_little_crm` |
| Bundle ID | `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` (Runner: Debug/Release/Profile) |
| Native test bundle ID | `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER = …RunnerTests` (3 places) |
| Signing team | `ios/Runner.xcodeproj/project.pbxproj` | `DEVELOPMENT_TEAM` (3 places) |
| Minimum iOS | `ios/Runner.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET` (currently 15.0) |
| Icon / launch screen | `ios/Runner/Assets.xcassets/`, `ios/Runner/Base.lproj/LaunchScreen.storyboard` | |

iOS has no About panel, so no copyright is set. The App Store copyright is
entered in App Store Connect. iOS's `TEST_HOST` points at `Runner.app` and
doesn't depend on the display name.

## Android

| What | File | Key / line |
| --- | --- | --- |
| Launcher name | `android/app/src/main/AndroidManifest.xml` | `android:label` (line 6) |
| App ID (Play Store identity) | `android/app/build.gradle.kts` | `applicationId` (line 19) |
| Kotlin namespace | `android/app/build.gradle.kts` | `namespace` (line 8) |
| Main activity | `android/app/src/main/kotlin/com/repasscloud/mylittlecrm/MainActivity.kt` | `package` line and folder path must match `namespace` |
| SDK levels | `android/app/build.gradle.kts` | `compileSdk`, `minSdk`, `targetSdk` (lines 9, 22, 23; default to Flutter's) |
| Release signing | `android/app/build.gradle.kts` | `signingConfig` (line 36): **still the debug key, so set this before publishing** |
| Backup rules | `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml` | backup is off on purpose |
| Icon | `android/app/src/main/res/mipmap-*/ic_launcher.png` | |

To change the namespace, move `MainActivity.kt` to the matching folder and
update its `package` line. Otherwise the app crashes on launch with
`ClassNotFoundException`.

Android has no copyright field. The Play listing holds it.

## Windows

Windows reads these from the executable's version resource (Explorer →
Properties → Details).

| What | File | Key / line |
| --- | --- | --- |
| Company | `windows/runner/Runner.rc` | `CompanyName` (line 92) |
| Description (Task Manager name) | `windows/runner/Runner.rc` | `FileDescription` (line 93) |
| Copyright | `windows/runner/Runner.rc` | `LegalCopyright` (line 96): one line only |
| Product name | `windows/runner/Runner.rc` | `ProductName` (line 98) |
| Internal / file name | `windows/runner/Runner.rc` | `InternalName`, `OriginalFilename` (lines 95, 97). Must match `BINARY_NAME` |
| Executable name | `windows/CMakeLists.txt` | `BINARY_NAME` (line 7) |
| Window title | `windows/runner/main.cpp` | `window.Create(L"…")` (line 30) |
| Icon | `windows/runner/resources/app_icon.ico` | referenced at `Runner.rc` line 55 |

`Runner.rc` is saved in code page 1252, so it uses `(C)` instead of `©`.
`CompanyName` + `ProductName` also set the data folder (see the warning above).

## Linux

| What | File | Key / line |
| --- | --- | --- |
| App ID (GTK / desktop file ID) | `linux/CMakeLists.txt` | `APPLICATION_ID` (line 10) |
| Executable name | `linux/CMakeLists.txt` | `BINARY_NAME` (line 7) |
| Window title | `linux/runner/my_application.cc` | `gtk_header_bar_set_title` (line 48), `gtk_window_set_title` (line 52) |

## Flutter / Dart side

| What | File | Key / line |
| --- | --- | --- |
| Package name (Dart imports) | `pubspec.yaml` | `name:` (line 1). Renaming it changes every `package:my_little_crm/…` import |
| Version | `pubspec.yaml` | `version:` (line 19) |
| Task-switcher / web title | `lib/app.dart` | `MaterialApp(title:)` (line 19) |
| Home app-bar title | `lib/app.dart` | line 91 |

## Versions

Set the version once in `pubspec.yaml` as `version: <name>+<build>`, for
example `1.0.0+15`, or override it per build with
`--build-name` / `--build-number`.

| Platform | `<name>` becomes | `<build>` becomes |
| --- | --- | --- |
| macOS / iOS | `CFBundleShortVersionString` | `CFBundleVersion` |
| Android | `versionName` | `versionCode` |
| Windows | `FileVersion` / `ProductVersion` major.minor.patch | build part |
| Linux | — | — |

## Where the database lives

The live ledger is one SQLite file, `crm.sqlite`, in the app's private
Application Support directory. `AppDatabase.defaultPath()` in
`lib/data/local/app_database.dart` resolves it at run time with
`path_provider`'s `getApplicationSupportDirectory()`; nothing is hardcoded and
nothing is stored inside the app bundle, so the file survives app updates and
new release builds (reviewed in #54).

| Platform | Resolved folder | Comes from |
| --- | --- | --- |
| macOS (App Sandbox) | `~/Library/Containers/com.repasscloud.mylittlecrm/Data/Library/Application Support/com.repasscloud.mylittlecrm/` | bundle ID |
| iOS | `<app container>/Library/Application Support/` | app container |
| Android | `/data/data/com.repasscloud.mylittlecrm/files/` | `applicationId` |
| Windows | `%APPDATA%\RePass Cloud Pty Ltd\My Little CRM\` (Roaming) | `CompanyName` + `ProductName` in `Runner.rc` |
| Linux | `$XDG_DATA_HOME/com.repasscloud.mylittlecrm/` (default `~/.local/share/…`) | `APPLICATION_ID` |

The ID values in the right-hand column are **part of the database path**.
Renaming one moves where the app looks, so existing users would see an
empty ledger. A rename needs a migration that copies the old file first.

macOS sandbox entitlements (`macos/Runner/*.entitlements`) are
`app-sandbox` plus `files.user-selected.read-write`, which the native save and
open pickers use for exports and imports. Debug/Profile also has `allow-jit`
and `network.server`, which Flutter needs for hot reload and debugging. There are no
temporary exceptions, so the Release entitlements are acceptable for Mac App
Store review. `test/platform/storage_location_test.dart` guards the file name,
the resolver and the entitlements.

Data persistence across updates depends on the update being the *same app* to
the OS: the same bundle ID / applicationId and, on Android, the same signing
key. On macOS, GitHub release builds are currently ad-hoc signed
(`CODE_SIGN_IDENTITY = "-"`). The container keeps the data, but macOS 14+
can ask the user to allow an app with a different signature to access it.
Developer ID or Mac App Store signing with a fixed Team ID avoids this.

## Tests and CI tied to these settings

| Test | What it depends on | Update when |
| --- | --- | --- |
| `test/platform/platform_identity_test.dart` | every value in this guide | you change an app ID, display name, company or binary name: update the constants at the top |
| `test/platform/storage_location_test.dart` | database file name and resolver, macOS entitlements | you move the database or change entitlements (needs a data migration) |
| `test/app_test.dart` | `'My Little CRM'` app-bar text in `lib/app.dart` | the in-app title changes |
| `macos/RunnerTests` (XCTest) | `TEST_HOST` → `PRODUCT_NAME`; test bundle ID | `PRODUCT_NAME` or the bundle ID changes |
| `ios/RunnerTests` (XCTest) | test bundle ID | the bundle ID changes |
| `integration_test/core_journey_test.dart` (CI: *macOS integration*) | builds and launches the macOS app | the macOS project stops building |
| Every Dart test | `package:my_little_crm/` imports | `pubspec.yaml` `name:` changes |

Run them:

```sh
flutter analyze && flutter test                                    # includes the platform identity checks
flutter test integration_test/core_journey_test.dart -d macos     # what CI runs on macOS
cd macos && xcodebuild test -workspace Runner.xcworkspace \
  -scheme Runner -destination 'platform=macOS' -only-testing:RunnerTests
```

## Rename checklist

1. Change the app ID in macOS `AppInfo.xcconfig`, both `project.pbxproj`
   files (app + `RunnerTests`), Android `build.gradle.kts` (`applicationId` +
   `namespace`, then move `MainActivity.kt`) and Linux `CMakeLists.txt`.
2. Change the display name in macOS `PRODUCT_NAME` (and the macOS `TEST_HOST` ×3),
   iOS `CFBundleDisplayName`, Android `android:label`, Windows `Runner.rc`
   `FileDescription`/`ProductName` + `main.cpp`, Linux `my_application.cc`, and `lib/app.dart`.
3. Change the company / copyright in macOS `PRODUCT_COPYRIGHT` and Windows
   `CompanyName`/`LegalCopyright`.
4. Update the constants in `test/platform/platform_identity_test.dart`.
5. Run the commands above, and plan a data migration if the app is already
   installed anywhere (see the warning at the top).
