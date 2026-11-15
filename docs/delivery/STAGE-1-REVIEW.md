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

## v1.1.0 — 16 November 2026

Milestone v1.1.0 (#31–#39) adds record management (delete, rename, merge, moving
an interaction), grouped follow-ups with optional due times, a full-ledger JSON
export and import, locale-aware dates, a responsive layout, a paged home list
and broader CI. Database schema 4 adds `interactions.follow_up_has_time`
(existing follow-ups stay day-only) and two indexes. The migration is idempotent
and is covered by an upgrade test from a genuine schema 3 file.

### Large-ledger benchmark (#39)

`flutter test tool/benchmark/ledger_benchmark_test.dart` seeds an on-disk SQLite
ledger through FFI with 50,000 interactions across 2,000 parties: half have a
reference, a third have a contact, and one in 25 has a follow-up. It reports the
median of 7 runs after one warm-up. The machine was an Apple-silicon Mac on
macOS, using SQLite FTS5 through `sqflite_common_ffi`. Seeding took about 13.5 s.

| Operation | Schema 4, no new indexes | With new indexes |
|---|---:|---:|
| Old home reload: list all parties, then each history (N+1)¹ | 673 ms | 658 ms |
| New home first page (50, SQL join + `LIMIT`) | 41.4 ms | **0.4 ms** |
| New home next page (50, keyset cursor) | 13.4 ms | **0.4 ms** |
| Open follow-ups | 8.6 ms | **6.2 ms** |
| One party's history | 0.3 ms | 0.3 ms |
| Search `CASE-24680` (exact reference) | 38.4 ms | 38.3 ms |
| Search `refund` (FTS word, 12,500 hits) | 134.6 ms | 135.3 ms |
| Search `Party 1234` (party-name substring) | 38.6 ms | 38.5 ms |
| Search `Contact 42` (contact substring) | 40.2 ms | 40.2 ms |
| Search with no match | 37.0 ms | 37.0 ms |

¹ This already uses the batched reference loading added in 1.1.0. Version 1.0.0
also ran one reference query per row, so the real 1.0.0 home reload was slower
than this.

Indexes kept:

- `interactions_timestamp_id ON interactions(timestamp DESC, id DESC)` serves
  the newest-first home pages. It removes the full sort, giving about 100× on the
  first page.
- `interactions_follow_up ON interactions(follow_up_status, follow_up_due_at)`
  serves the outstanding follow-up list (about 28% faster).

Search is unchanged at about 40 ms on 50k records. Its cost is the `LIKE '%…%'`
substring scans on party, contact and reference columns, which B-tree indexes
cannot serve. That is acceptable for an interactive search box at this size. If
ledgers grow well beyond this, the next steps are trigram FTS for metadata and a
result limit; broad FTS matches such as `refund` spend most of their time
loading every hit.

### CI coverage (#35)

`Flutter validation` runs on every pull request:

| Job | Runner | Covers |
|---|---|---|
| Analyze and unit tests | ubuntu-latest | `flutter analyze`, and all unit and widget tests (in-memory and on-disk SQLite through FFI/FTS5) |
| macOS integration | macos-15 | Builds the macOS app and runs `integration_test/core_journey_test.dart` against native SQLite, including the FTS4 fallback and the v1.1.0 record-management journey |
| Linux integration | ubuntu-latest + xvfb | Builds the Linux desktop app and runs the same journey on the FFI/FTS5 path. The FTS4-only case is skipped there by design |

The macOS job had been commented out in the workflow. Its last runs passed in
about 4 minutes, and the only failure was a run cancelled by a newer push. It is
re-enabled with a concurrency group, so superseded runs are cancelled, and a
timeout. Android, iOS and Windows are still not exercised by CI. Their
acceptance remains with #7.

### Verification on 16 November 2026

- `flutter analyze`: no issues.
- `flutter test`: all unit and widget tests passed. New tests cover delete with
  FTS and reference cleanup, cascading party delete, rename including the Unicode
  conflict, merge, moving an interaction, keyset paging, the schema 3 to 4
  upgrade, export/import round-trip and rejection, date formatting at fixed
  locales, follow-up grouping at fixed times, compact and expanded layouts, and
  lazy home paging.
- `flutter test integration_test/core_journey_test.dart -d macos`: all 3 native
  tests passed.
