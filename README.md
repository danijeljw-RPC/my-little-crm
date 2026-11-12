# My Little CRM

My Little CRM is a little CRM tool for home users who want to keep track of
their communications: who they spoke with and what was said.

## Why My Little CRM?

Important conversations and details can be scattered across services and
companies. Keeping your own record gives you something to refer back to and
helps you stay ahead.

## What it’s for

Use My Little CRM to keep track of:

- Who you communicated with
- What you discussed

My Little CRM is intended for personal, at-home use.

## Development

This Flutter application targets Windows, macOS, Linux, Android, and iOS. It
is local-first: the core app does not need an account or a network connection.

```sh
flutter pub get
flutter run -d macos # or ios, android, windows, linux
```

Install Flutter stable with its matching Dart SDK, then run `flutter doctor` and
install the toolchains it identifies for the host platform. Use `flutter devices`
to choose a device ID. Windows builds require Windows and Visual Studio C++ tools;
Linux builds require Linux and the desktop GTK toolchain; Apple builds require
macOS and Xcode; Android builds require the Android SDK. Web is not a release target.

To pick a target without looking up IDs, use the run helper. With no argument it
lists running devices, launchable emulators and (on macOS) shut-down iOS simulators;
with a name or ID it boots the simulator/emulator if needed and runs the app there.
Matching is case-insensitive, and extra arguments are passed to `flutter run`.

```sh
scripts/run.sh                    # macOS / Linux (zsh)
scripts/run.sh "iPhone 18 Pro"
scripts/run.sh macos --release
```

```powershell
.\scripts\run.ps1                 # Windows
.\scripts\run.ps1 windows
.\scripts\run.ps1 "swoovr-pixel"
```

These helpers, `flutter run` and `flutter build` always sign Android builds with
the debug key. Only release builds use the release key.

**To publish a release** for Android, macOS and Windows, bump the version in
`pubspec.yaml`, add a matching `CHANGELOG.md` section, then push a commit whose
whole message is `release` to `main`:

```sh
git commit --allow-empty -m release && git push origin main
```

GitHub Actions builds all three platforms and creates release `v<version>`.
`scripts/release.sh` still builds the signed APK locally. See
[release guide](docs/ANDROID-RELEASE.md).

## Stage 1 workflow

Record a company or person, communication method, date, summary, and optional
contact, references, commitment, and follow-up. Parties group interactions into
newest-first histories. Search finds notes, names, contacts, and references.
Complete follow-ups from the outstanding list; their records remain in history.
Open a party history to export its complete chronological history as PDF or JSON
through the native save dialog.

The primary SQLite database stays in the application's support directory. Core
recording, search, follow-ups, and export generation work offline without an
account. The destination selected in the native picker may itself be a cloud
provider. Export files contain readable personal records: keep them in a location
you trust. PDF/JSON exports are reports, not an encrypted restorable backup.

Stage 1 does not yet include app-entry PIN/biometrics, encrypted backup/restore,
recovery kits, notifications, calendar export, attachments, or cloud sync.
Android automatic cloud backup and device-transfer extraction of app storage
are disabled. Other operating-system backup behavior remains controlled by the
platform and its user settings. Device security protects the current local
database; app-level encryption follows in a separate security stage.

See [Stage 1 review evidence](docs/delivery/STAGE-1-REVIEW.md) for corrections,
migration behavior, and remaining platform-acceptance limits.

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test/core_journey_test.dart -d macos
flutter build macos --debug
```

## Continuous integration

Pull requests run the `Flutter validation` workflow. Configure branch
protection to require both of its checks before merging:

- `Flutter validation / Analyze and unit tests`
- `Flutter validation / macOS integration`

Use an emulator or disposable test device for the integration journey. It creates
a temporary SQLite database, records three interactions (including one through the editor), searches a partial case
number, completes a follow-up, reopens the database, and verifies all three records
remain in the party history. Replace `macos` with an available supported target
to repeat acceptance there. Platform folders alone do not establish acceptance
on all five operating systems.
