# Core Local CRM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the offline, searchable personal CRM foundation for Windows, macOS, Linux, Android, and iOS.

**Architecture:** A Flutter client owns all user data in a versioned local SQLite database. Presentation code calls repository interfaces through focused application services; database, clock, and notification-facing concerns stay behind adapters so the core remains deterministic and testable. This plan implements the core record flow only; backup/recovery, device locking, and future cloud sync have separate security-sensitive plans.

**Tech Stack:** Flutter/Dart, SQLite with Drift, Riverpod, GoRouter, Material 3, `flutter_test` and `integration_test`. *(As built: sqflite and sqflite FFI, constructor injection, Navigator; see "As built" below.)*

**Spec:** `docs/superpowers/specs/2026-11-11-my-little-crm-design.md`

## As built

**Status:** Stage 1 is complete (see `docs/delivery/STAGE-1-REVIEW.md`). Every step below is ticked. Where the result differs from the plan, the step carries an *As built* note. Updated for v1.1.1 (#40).

The implementation kept the plan's contracts (domain types, `CrmService`, repository interfaces, tests per task) but not three of its framework choices:

| Plan | As built | Why |
| --- | --- | --- |
| Drift database and `Drift*Repository` adapters | `sqflite` on Android, iOS and macOS; `sqflite_common_ffi` on Windows, Linux and in tests. `AppDatabase` in `lib/data/local/app_database.dart` with hand-written, versioned migrations (now schema 4), and `LocalPartyRepository` / `LocalInteractionRepository` | Direct SQL control over FTS5/FTS4 fallback and Unicode-normalized search columns, with no code generation step |
| Riverpod `ProviderScope` and providers | Constructor injection: `main.dart` builds `CrmService` with its repositories and clock and passes it to `MyLittleCrmApp` | The service graph is small. The unused `ProviderScope` and the `flutter_riverpod` package were removed in v1.1.1 (#8) |
| GoRouter `MaterialApp.router` with named routes | `MaterialApp` with an adaptive navigation shell (bar/rail) and `Navigator` pushes | No deep links are needed yet. `go_router` was never imported and was removed in v1.1.1 (#8). Named/deep-link routes are not implemented |

Other differences, noted at their steps: no separate `interaction_timeline.dart` or `export_history_screen.dart` file, no `SearchResult` type, and substring (`LIKE`) rather than indexed matching for party/contact/reference search.

### Open follow-ups from Stage 1

- #7: platform and native export (save-picker) acceptance on Windows, Linux, Android and iOS. Only macOS native acceptance has been run.
- #30: the plan excluded web. Running in Chrome now fails at start-up, and the issue has been re-scoped to a WebAssembly demo with an in-memory database.
- Later stages the plan deferred: #44 portable local backup and restore, #43 offline notifications and reminders, #41 cross-platform architecture and build configuration. App lock and calendar export have no issue yet.

## Global Constraints

- Support Windows, macOS, Linux, Android, and iOS from one Flutter codebase.
- Use SQLite as the primary local source of truth; the core works without a connection.
- This is a private personal communications ledger, not a sales pipeline, team CRM, or hosted account product.
- Record timestamp, method, party, contact, summary, reference numbers, commitment, and optional follow-up.
- Keep party histories chronological and make party/contact/reference/text search fast.
- No product backend, API, managed user account, hosted copy of records, PostgreSQL/Supabase support, or third-party messaging integration in this plan.
- Do not collect personal details.

## Review Focus

- A user records two interactions for one party and both appear in a single newest-first timeline; test in Task 4.
- A note containing a reference number and punctuation is found with a partial global search; test in Task 5.
- A new interaction without a contact, reference, commitment, or follow-up saves without placeholder data; test in Task 3.
- A completed follow-up no longer appears in the outstanding list but remains in the interaction history; test in Task 4.
- An edit must preserve an interaction's immutable ID and creation timestamp while updating its details; test in Task 3.

---

## File Structure

- `pubspec.yaml`: Flutter SDK/package constraints and developer tooling.
- `lib/main.dart`: application bootstrap and provider scope. *(As built: bootstrap and constructor injection, no provider scope.)*
- `lib/app.dart`: theme, router, and responsive application shell. *(As built: no router; Navigator.)*
- `lib/core/clock.dart`: injectable time abstraction.
- `lib/domain/*.dart`: immutable entities, value objects, repository contracts, and use-case services.
- `lib/data/local/app_database.dart`: Drift database and migrations. *(As built: sqflite/FFI database and migrations.)*
- `lib/data/local/*_repository.dart`: SQLite implementations of repository contracts.
- `lib/features/parties/*`: party list, party editor, and party-history UI.
- `lib/features/interactions/*`: quick interaction editor and timeline widgets.
- `lib/features/search/*`: global search UI and result grouping.
- `lib/features/follow_ups/*`: outstanding follow-up list and completion actions.
- `test/domain/*`, `test/data/*`, `test/features/*`: unit, database, and widget tests.
- `lib/features/export/*`: local PDF and JSON party-history exporters plus share/save adapters.
- `integration_test/core_journey_test.dart`: end-to-end local workflow on supported device targets.

### Task 1: Create the cross-platform Flutter foundation

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/app.dart`
- Create: `test/app_test.dart`
- Modify: `README.md`

**Interfaces:**
- Produces: `MyLittleCrmApp` root widget and a `ProviderScope` bootstrap used by every later feature.

- [x] **Step 1: Write a failing widget test for the app shell**

```dart
testWidgets('shows the My Little CRM home shell', (tester) async {
  await tester.pumpWidget(const MyLittleCrmApp());
  expect(find.text('My Little CRM'), findsOneWidget);
  expect(find.text('Interactions'), findsOneWidget);
});
```

- [x] **Step 2: Run the widget test to verify it fails**

Run: `flutter test test/app_test.dart`
Expected: FAIL because the Flutter application has not been created.

- [x] **Step 3: Scaffold `MyLittleCrmApp` in `lib/app.dart`**

Use a Material 3 `MaterialApp.router` with stable routes for interactions, parties, search, and follow-ups. Configure Windows, macOS, Linux, Android, and iOS platform folders through Flutter's standard project tooling; do not introduce web as a release target.

*As built:* a plain `MaterialApp` with a navigation bar/rail shell and `Navigator` pushes (no GoRouter). The `ProviderScope` bootstrap in Interfaces was replaced by constructor injection and removed in v1.1.1 (#8). Web is still not a target, but #30 has re-scoped it to a WebAssembly demo.

- [x] **Step 4: Run static analysis and the widget test**

Run: `flutter analyze && flutter test test/app_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add pubspec.yaml analysis_options.yaml lib test README.md
git commit -m "feat: scaffold cross-platform CRM app"
```

### Task 2: Define the domain model and use-case contracts

**Files:**
- Create: `lib/core/clock.dart`
- Create: `lib/domain/models.dart`, `lib/domain/repositories.dart`, `lib/domain/crm_service.dart`
- Create: `test/domain/crm_service_test.dart`

**Interfaces:**
- Consumes: Flutter foundation from Task 1.
- Produces: `Party`, `Interaction`, `FollowUp`, `CommunicationMethod`, `PartyRepository`, `InteractionRepository`, and `CrmService` used by Tasks 3–6.

- [x] **Step 1: Write failing domain tests for interaction creation and follow-up completion**

```dart
expect(created.timestamp, fixedNow);
expect(created.partyId, party.id);
expect(created.followUp!.status, FollowUpStatus.open);
await service.completeFollowUp(created.id);
expect((await service.getInteraction(created.id)).followUp!.status,
       FollowUpStatus.completed);
```

- [x] **Step 2: Run the domain tests to verify they fail**

Run: `flutter test test/domain/crm_service_test.dart`
Expected: FAIL because domain contracts and service do not exist.

- [x] **Step 3: Implement immutable domain types and `CrmService`**

Define `createInteraction(CreateInteractionCommand command)`,
`updateInteraction(UpdateInteractionCommand command)`,
`completeFollowUp(InteractionId interactionId)`, and
`searchInteractions(String query)`. Require a non-empty party name and summary;
default the timestamp from `Clock.now()`; all optional record fields remain null
when absent.

- [x] **Step 4: Run the domain tests**

Run: `flutter test test/domain/crm_service_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/core lib/domain test/domain
git commit -m "feat: define CRM domain services"
```

### Task 3: Persist parties and interactions in local SQLite

**Files:**
- Create: `lib/data/local/app_database.dart`, `lib/data/local/party_repository.dart`, `lib/data/local/interaction_repository.dart`
- Create: `test/data/local_repositories_test.dart`

**Interfaces:**
- Consumes: repository contracts and model types from Task 2.
- Produces: `DriftPartyRepository` and `DriftInteractionRepository`, bound as the production repository providers in `lib/main.dart`. *(As built: `LocalPartyRepository` / `LocalInteractionRepository`, constructor-injected.)*

- [x] **Step 1: Write failing repository tests for optional fields and editing**

```dart
final saved = await interactions.save(minimalInteraction);
expect(saved.contactName, isNull);
expect(saved.referenceNumbers, isEmpty);
final edited = await interactions.save(saved.copyWith(summary: 'Updated note'));
expect(edited.id, saved.id);
expect(edited.createdAt, saved.createdAt);
```

- [x] **Step 2: Run the repository tests to verify they fail**

Run: `flutter test test/data/local_repositories_test.dart`
Expected: FAIL because the SQLite schema and repositories do not exist.

- [x] **Step 3: Implement `AppDatabase` schema and repository adapters**

Create normalized party and interaction tables plus a reference-number child table. Store timestamps in UTC, preserve interaction IDs and creation timestamps on update, and add a migration baseline at schema version 1. Use an in-memory Drift database in tests and a platform SQLite file in production.

*As built:* `LocalPartyRepository` and `LocalInteractionRepository` over sqflite (native) or sqflite FFI (desktop and tests), passed to `CrmService` in `lib/main.dart` instead of being bound as providers. Tests use `AppDatabase.inMemory()` (FFI) or the in-memory repositories in `lib/domain/repositories.dart`. The schema baseline is now at version 4. The production file is `crm.sqlite` in the platform Application Support directory (#54).

- [x] **Step 4: Run database and domain tests**

Run: `flutter test test/data test/domain`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/data lib/main.dart test/data
git commit -m "feat: persist local CRM records"
```

### Task 4: Build interaction entry, party timelines, and follow-up completion

**Files:**
- Create: `lib/features/interactions/interaction_editor.dart`, `lib/features/interactions/interaction_timeline.dart`
- Create: `lib/features/parties/party_list_screen.dart`, `lib/features/parties/party_history_screen.dart`
- Create: `lib/features/follow_ups/follow_ups_screen.dart`
- Create: `test/features/interaction_workflow_test.dart`

**Interfaces:**
- Consumes: `CrmService` and production repository providers from Tasks 2–3.
- Produces: routed screens for party creation, fast interaction recording, chronological history, and outstanding follow-ups.

- [x] **Step 1: Write failing widget tests for timeline grouping and completion**

```dart
expect(find.text('BrightSure Insurance'), findsOneWidget);
expect(find.text('Revised quote promised'), findsOneWidget);
await tester.tap(find.byTooltip('Complete follow-up'));
await tester.pumpAndSettle();
expect(find.text('Revised quote promised'), findsNothing);
```

- [x] **Step 2: Run the widget tests to verify they fail**

Run: `flutter test test/features/interaction_workflow_test.dart`
Expected: FAIL because feature screens do not exist.

- [x] **Step 3: Implement the fast record and history workflow**

Use one compact editor with party autocomplete/create, method picker, automatic timestamp, optional contact/reference/commitment/follow-up fields, and a save action. Render party histories newest-first; render only open follow-ups in the due list, while retaining completed items in the timeline.

*As built:* the timeline lives in `lib/features/interactions/recent_interactions_list.dart` and the party history screen (no `interaction_timeline.dart`). Screens are opened with `Navigator`, not named routes.

- [x] **Step 4: Run feature, database, and domain tests**

Run: `flutter test test/features test/data test/domain`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/features test/features
git commit -m "feat: add interaction histories and follow-ups"
```

### Task 5: Add indexed global search

**Files:**
- Modify: `lib/data/local/app_database.dart`, `lib/data/local/interaction_repository.dart`, `lib/domain/repositories.dart`
- Create: `lib/features/search/search_screen.dart`
- Create: `test/data/search_test.dart`, `test/features/search_screen_test.dart`

**Interfaces:**
- Consumes: SQLite repositories and `CrmService.searchInteractions` from Tasks 2–3.
- Produces: `SearchResult` and a global search route used by the app shell.

- [x] **Step 1: Write failing database tests for partial reference and text search**

```dart
expect((await repository.search('8419')).single.partyName,
       'BrightSure Insurance');
expect((await repository.search('premium disputed')).single.interactionId,
       interaction.id);
```

- [x] **Step 2: Run the search tests to verify they fail**

Run: `flutter test test/data/search_test.dart test/features/search_screen_test.dart`
Expected: FAIL because global search is not implemented.

- [x] **Step 3: Implement SQLite-backed `search(String query)` and the search screen**

Use SQLite FTS for interaction summaries and indexed matching for party, contact, and reference values. Ignore blank queries, escape FTS special characters, order results by relevance then newest timestamp, and display the matching party, date, method, and summary excerpt.

*As built:* `search` returns `List<Interaction>` (no `SearchResult` type), and the screen resolves each party. Summaries use FTS5 with an FTS4 fallback. Party, contact and reference matching uses Unicode-normalized `LIKE` substring scans rather than an index. That measures about 40 ms on 50,000 interactions (`docs/delivery/STAGE-1-REVIEW.md`, #39).

- [x] **Step 4: Run all search tests and analysis**

Run: `flutter analyze && flutter test test/data/search_test.dart test/features/search_screen_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/data/local lib/domain lib/features/search test/data test/features
git commit -m "feat: add local interaction search"
```

### Task 6: Export a party communication history as PDF or JSON

**Files:**
- Create: `lib/features/export/history_export_service.dart`, `lib/features/export/export_history_screen.dart`
- Create: `test/features/history_export_service_test.dart`

**Interfaces:**
- Consumes: party timelines and interaction records from Tasks 2–4.
- Produces: `HistoryExportService.exportPdf(PartyId partyId)` and `HistoryExportService.exportJson(PartyId partyId)`, each returning an export document containing the complete ordered history.

- [x] **Step 1: Write failing export tests for portable content**

```dart
final json = await service.exportJson(brightSure.id);
expect(json.content, contains('BS-841902'));
expect(json.content, contains('Revised quote promised'));
expect(json.content, contains('"party"'));
```

- [x] **Step 2: Run the export tests to verify they fail**

Run: `flutter test test/features/history_export_service_test.dart`
Expected: FAIL because the export service does not exist.

- [x] **Step 3: Implement local PDF and JSON export**

JSON must be a versioned, UTF-8 document containing the complete party record and all its interactions in chronological order. The PDF must identify the party, generation time, and all interaction details in readable chronological order. Write exports through the native save/share picker only; no data leaves the device unless the user selects a destination.

*As built:* export is started from the party history screen, so there is no `export_history_screen.dart`. The PDF refuses text the bundled NotoSans font cannot draw and suggests JSON. The native save picker is accepted on macOS only; the other platforms are tracked in #7. v1.1.0 added a whole-ledger JSON export (#37), and v1.1.1 adds a whole-ledger PDF report (#52).

- [x] **Step 4: Run the export tests and analysis**

Run: `flutter analyze && flutter test test/features/history_export_service_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/features/export test/features
git commit -m "feat: export party histories as PDF and JSON"
```

### Task 7: Verify the end-to-end offline journey and release documentation

**Files:**
- Create: `integration_test/core_journey_test.dart`
- Modify: `README.md`

**Interfaces:**
- Consumes: complete local application from Tasks 1–6.
- Produces: a repeatable local-device acceptance check and setup instructions for each target platform.

- [x] **Step 1: Write the end-to-end journey test**

```dart
// Create BrightSure, record a phone interaction, search BS-841902,
// then mark its follow-up complete and assert it remains in the party history.
```

- [x] **Step 2: Run it to verify the journey fails before wiring is complete**

Run: `flutter test integration_test/core_journey_test.dart`
Expected: FAIL until all prior workflow routes and controls are available.

- [x] **Step 3: Add target setup and offline/privacy instructions to `README.md`**

Document Flutter installation, how to run each supported platform target, that no account or network is required, how local PDF/JSON exports work, and the first-release exclusions: encryption backup/recovery, app lock, calendar export, and notifications arrive in later plans.

- [x] **Step 4: Run the full local verification suite**

Run: `flutter analyze && flutter test && flutter test integration_test/core_journey_test.dart`
Expected: PASS on every locally available target.

*As built:* passes on macOS (locally and in CI) and on Linux in CI. Acceptance on Windows, Android and iOS is deferred to #7.

- [x] **Step 5: Commit**

```bash
git add integration_test README.md
git commit -m "test: cover core local CRM journey"
```

## Self-review

- **Spec coverage:** This plan covers the requested platform shell, offline SQLite source of truth, parties, interactions, chronological history, follow-ups, search, and local PDF/JSON history export. Device lock, encrypted backup/restore, static WASM recovery, notifications/calendar integration, attachments, and BYO cloud are separate release stages because they are independent security/platform subsystems.
- **Step scan:** Every task begins with a focused failing test, has a named implementation surface, and finishes with an explicit command and commit.
- **Type consistency:** `CrmService`, repository types, the `InteractionId` completion path, and `SearchResult` are consistently introduced before use.
- **Review focus:** Each identified user-risk case is assigned to its owning task's test step.
- **Proportion:** The plan fixes contracts, files, and verification without prescribing implementation bodies that tests and signatures determine.
