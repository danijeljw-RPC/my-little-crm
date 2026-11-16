# Changelog

All notable changes to My Little CRM are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [1.1.2] - 2026-11-16

Try My Little CRM in a browser: a disposable WebAssembly demo.

### Added

- **Browser demo** (#30): My Little CRM now runs in a browser, compiled to
  WebAssembly (`flutter build web --release --wasm --dart-define=DEMO_MODE=true`).
  The demo uses an in-memory SQLite database seeded with sample parties,
  interactions and follow-ups. Everything works as normal, and a banner says
  that changes are discarded on refresh. Nothing is stored in the browser,
  and no backend or account is needed. See `docs/WEB-DEMO.md`.
- `DEMO_MODE` build flag: the same throwaway, seeded demo on any platform. It
  never opens the real ledger.
- `scripts/web-demo.sh` builds the demo and serves it locally with the
  hosting headers it needs. A new `Web demo (Wasm)` CI job builds it and
  uploads the static site as an artifact.
- `scripts/web-demo.sh package` zips the demo for uploading to your own web
  server (`--base-href /path/` for a sub-folder). The site includes an
  `.htaccess` for Apache/cPanel and a `_headers` file for Cloudflare Pages
  and Netlify. `docs/WEB-DEMO.md#publish` covers uploading, nginx, Caddy,
  IIS and CDN headers, and how to check the result.

### Fixed

- Running in Chrome no longer shows a blank screen (#30).
  `scripts/run.sh chrome` and `scripts/run.ps1 chrome` now start the demo
  instead of refusing web targets.

### Changed

- Opening the database now goes through separate native and web openers,
  so the web build never loads `dart:io`, `dart:ffi` or the native sqflite
  plugin. The PDF report uses `compute`, which falls back to the page's
  thread in browsers.

## [1.1.1] - 2026-11-16

A printable report of the whole ledger, plus maintenance.

### Added

- **Export everything as PDF**: one readable report of every party, ordered
  by name, with its full history. The report opens with a contents section,
  and each party starts on a new page. It is **not encrypted** and **cannot
  be imported**; only the JSON export can be imported. The app says so
  before saving. Large ledgers are laid out in the background with a
  progress dialog (about 11 s for 50,000 interactions). If some text can't
  be drawn in the PDF, the message names the party it is in.

### Changed

- Removed unused packages (`flutter_riverpod`, `go_router`,
  `cupertino_icons`) and updated the others to their latest compatible
  versions. `docs/DEPENDENCIES.md` lists the versions held back on purpose.
- `scripts/run.sh` and `scripts/run.ps1` now refuse web targets such as
  `chrome` with an explanation, instead of starting to a blank screen. Web
  support is planned separately.

### Verified

- The database stays in each platform's private Application Support folder,
  outside the app bundle, and the macOS app is sandboxed with no exceptions.
  Nothing moved; existing data is untouched. See "Where the database lives" in
  `docs/PLATFORM-SETTINGS.md`.

## [1.1.0] - 2026-11-16

Record management, a desktop and tablet layout, and a full export for moving
to a new device.

### Added

- **Delete** an interaction from its editor, with confirmation and **Undo**.
  Deleted records disappear from history and search.
- **Party editor**: rename a party, merge a duplicate (such as a typo) into
  another party, or delete a party. Deleting states how many interactions go
  with it. Renaming to an existing name offers to merge instead.
- **Move an interaction** to a different party by changing its party in the
  editor. It keeps its record ID and creation time.
- **Follow-ups grouped** into Overdue, Due today and Upcoming. Overdue items
  are labelled in words as well as colour, and the navigation shows an
  overdue count.
- **Optional due time** for follow-ups. Without a time, a follow-up is due by
  the end of its day.
- **Export everything** to a single versioned JSON file, and import it into an
  empty ledger on a new device. The file is **not encrypted**, and the app
  says so before saving.
- **Responsive layout**: a navigation rail on tablets and desktop windows,
  lists and details side by side on wide windows, and the editor as a dialog
  instead of a full-width sheet.

### Changed

- Dates and times follow the device locale and 12/24-hour setting, with
  "Today", "Yesterday" and "Tomorrow" for nearby days. PDF reports use full
  dates.
- The home list loads 50 interactions at a time as you scroll, instead of the
  whole ledger on every change. With 50,000 interactions, the first page now
  loads in under 1 ms rather than about 0.7 s.
- Database schema 4 adds the follow-up time and indexes for the home and
  follow-up lists. Existing data upgrades automatically. Existing follow-ups
  stay day-only.

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

[1.1.2]: https://github.com/danijeljw-RPC/my-little-crm/releases/tag/v1.1.2
[1.1.1]: https://github.com/danijeljw-RPC/my-little-crm/releases/tag/v1.1.1
[1.1.0]: https://github.com/danijeljw-RPC/my-little-crm/releases/tag/v1.1.0
[1.0.0]: https://github.com/danijeljw-RPC/my-little-crm/releases/tag/v1.0.0
