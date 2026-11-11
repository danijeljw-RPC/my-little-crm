# Stage 1 review evidence

Stage 1 delivers the local personal communications ledger: native SQLite storage,
parties and histories, interaction recording/editing, outstanding follow-ups,
local search, and PDF/JSON history export. The application entry point opens the
durable database in the platform application-support directory.

Database schema 2 adds Unicode-normalized search columns for party names,
summaries, contact names, and reference numbers. Opening a schema 1 database
backfills these columns transactionally while preserving the original display
values and records. New writes and query text use the same Dart lowercase
mapping; search continues in SQLite without scanning records in Dart per query.

## Native acceptance

On 11 November 2026, `flutter test integration_test/core_journey_test.dart -d macos`
built the macOS debug application and passed its native integration journey
(`+1: All tests passed`). The runner emitted a foregrounding warning but executed
the test successfully.

The journey uses fictional records and an isolated temporary SQLite file. It
creates two service records and a third through the interaction editor, searches
a partial case number, completes a follow-up through the UI, closes and reopens
the database, and verifies all three records survive and the completed follow-up
remains in party history while disappearing from the outstanding list.

The temporary database is removed after the successful journey. No connected
personal Android device was used. Windows, Linux, Android, and iOS native
acceptance remains to be performed on suitable hosts or disposable devices.
Platform scaffolding is not evidence of acceptance on those targets.

## Review scope

An independent branch pass examined persistence wiring, record creation,
search freshness after edits, history details, follow-up usability, and native
exports. Findings were sent to the implementation owners for correction:
incorrect hardcoded timeline dates, missing search navigation/date/method,
missing follow-up due dates, potential partial records from two saves, and stale
full-text rows after replacement updates. Those findings were corrected, along
with native FTS capability fallback and list refresh after saves and edits.
Final validation passed: static analysis found no issues, all 10 automated tests
passed, and the macOS native integration journey passed after the corrections.

PDF/JSON generation has automated content tests; the native save picker still
requires interactive acceptance on each release platform. Exports are readable
reports and are not encrypted backup/restore files. App lock, encrypted backup,
recovery, notifications, and calendar integration are later release stages.

## Repeatable commands

```sh
flutter analyze
flutter test
flutter test integration_test/core_journey_test.dart -d macos
```

See the README for host setup and the supported target list.

## Autonomous review — 12 November 2026

Reviewed the complete Stage 1 implementation against the core-local plan,
including application bootstrap, domain commands, persistence and migrations,
record editing, party histories, follow-ups, search, exports, platform manifests,
and CI. The fixes are on `codex/stage-1-review`.

Corrected findings:

- Party lookup/create now runs in one transaction and uses UUIDs, preventing
  simultaneous recordings from failing or creating duplicate Unicode parties.
- Creation timestamps are read inside the save transaction, preserving the first
  timestamp even when two first saves of an ID overlap.
- Schema 3 normalizes persisted UTC timestamps to six fractional digits. This
  repairs incorrect SQLite text ordering for records a microsecond apart.
  Migrations from versions 1 and 2 retain records, IDs, and optional fields.
- Search prioritizes exact reference matches, then exact party/contact/summary
  matches, then incidental matches; ties use newest timestamp and immutable ID.
  FTS summary search retains partial-word and punctuation-safe behavior. Partial
  metadata substring matching still uses SQLite LIKE scans; scalability for very
  large ledgers has not been benchmarked.
- Create commands accept all editor fields, and the missing update command now
  validates summaries, normalizes optional values, and preserves persisted party,
  ID, and creation timestamp. The editor uses these service operations.
- Party autocomplete is available during recording. Home records open editable
  history, and returning from history refreshes the home list. Removed an unused
  duplicate entry form.
- Load failures in home, parties, histories, and follow-ups now offer Retry.
  Search and completion failures show recoverable messages. Date-picker callbacks
  check the editor remains mounted.
- Android automatic backup is disabled and Android 12+ cloud/device transfer
  rules exclude private application storage. These settings follow
  [Android's backup documentation](https://developer.android.com/identity/data/autobackup).
  OS behavior on release devices remains part of platform privacy acceptance.
- The FTS4-specific integration fixture is restricted to native SQLite targets;
  Windows/Linux FFI SQLite uses FTS5 and runs the shared core journey.

Fresh verification on 12 November 2026:

- macOS integration: both native tests passed, including reopened FTS4 search
  and the offline record/editing UI, completion, and restart journey. The runner
  printed its known foregrounding warning and still executed both tests.
- `flutter build macos --debug --no-pub`: production entry point built successfully.
- `flutter build apk --debug --no-pub`: Android debug APK built successfully,
  including the backup manifest and extraction-rule resources. This was a build
  check, not Android device acceptance.
- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub`: all 37 tests passed.
- Automated tests cover the fixes above, including simultaneous saves, Unicode
  collisions, migrations, microsecond ordering, relevance, service validation,
  editor suggestions/navigation, and recovery after storage failures.

The implementation differs from the original framework sketch: it uses
sqflite/native SQLite and FFI repositories instead of Drift, constructor
injection instead of Riverpod providers, and Navigator routes instead of
GoRouter named routes. The reviewed workflows and persistence contracts are
covered by tests; adopting those frameworks is not required for the current
local workflow. Named/deep-link route contracts are not implemented.

Stage 1's core implementation is complete within the agreed scope. Native
save-picker interaction and release acceptance on Windows, Linux, Android, and
iOS remain part of the later platform-acceptance stage; this review does not
establish those results. PDF exports intentionally reject unsupported glyphs
with a JSON alternative. App lock, encrypted backup/recovery, notifications,
calendar integration, and cloud sync remain later-stage work.
