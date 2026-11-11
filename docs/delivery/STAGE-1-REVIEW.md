# Stage 1 review evidence

Stage 1 delivers the local personal communications ledger: native SQLite storage,
parties and histories, interaction recording/editing, outstanding follow-ups,
local search, and PDF/JSON history export. The application entry point opens the
durable database in the platform application-support directory.

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
