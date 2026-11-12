# Changelog

All notable changes to My Little CRM are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-12

First public release. My Little CRM is a private, offline-first ledger of your
personal communications: who you spoke with and what was said. It needs no
account and no network connection.

### Added

- **Record interactions** with a company or person: communication method, date,
  summary, and optional contact, references, commitment and follow-up.
- **Method icons** beside each communication type in the Method picker.
- **Party histories** that group every interaction with a company or person,
  newest first.
- **Follow-ups**: an outstanding list you can complete; completed follow-ups stay
  in history, and rescheduled ones reopen correctly.
- **Search** across notes, names, contacts and references. Results open the
  matching interaction directly and stay current after edits or new entries.
- **Export** a party's full chronological history as **PDF** or **JSON** through
  the native save dialog, with full Unicode support in PDFs.
- **Local storage** in an on-device SQLite database in the app's support
  directory. All features work offline.
- Native app name and icon on Android, iOS, macOS, Windows and Linux.

### Fixed

- Search keeps working consistently across SQLite versions, including Unicode
  normalisation of names and notes.
- Party histories are kept separate when names differ only in Unicode form.
- PDF exports no longer drop characters or produce incomplete files for
  non-Latin text.

### Security & privacy

- Android automatic cloud backup and device-transfer extraction of app data are
  disabled.
- Exports are readable reports, not encrypted backups. Store them somewhere you
  trust.

### Known limitations

Not yet included: app-entry PIN or biometrics, encrypted backup and restore,
recovery kits, notifications, calendar export, attachments and cloud sync.
App-level database encryption will come in a later security release. Until
then, your device's own security protects the local database.

### Installing on Android

1. Download `app-release.apk` from this release on your phone.
2. When prompted, allow your browser or file manager to install unknown apps.
3. Open the file and tap **Install**. Play Protect may warn about an unknown
   developer; this is expected for apps installed outside Google Play.

[1.0.0]: https://github.com/danijeljw-RPC/my-little-crm/releases/tag/v1.0.0
