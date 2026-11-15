# Dependencies

Last reviewed for v1.1.1 (#8) on 16 November 2026 with Flutter 3.47.9 /
Dart 3.13. Refresh with `flutter pub outdated`, then `flutter pub upgrade`
for anything inside the current constraints, and rerun `flutter analyze`,
`flutter test` and the macOS integration test.

## Direct dependencies

| Package | Used for |
| --- | --- |
| `sqflite` | SQLite on Android, iOS and macOS (`lib/data/local/app_database.dart`) |
| `sqflite_common_ffi` | SQLite on Windows and Linux, and in tests |
| `path_provider` | The Application Support folder that holds the live database |
| `uuid` | Party and interaction IDs |
| `intl` | Localized dates (`lib/core/date_format.dart`) |
| `pdf` | Party-history and whole-ledger PDF reports |
| `file_picker` | Native save/open pickers for exports and imports |

Removed in v1.1.1, because none of them was used: `flutter_riverpod`
(its only use was an empty `ProviderScope`), `go_router` (never imported;
the app uses `Navigator`) and `cupertino_icons` (no `CupertinoIcons` usage).
Re-add one only together with code that uses it.

## Held back on purpose

These show as outdated, but they are pinned by a package or by the Flutter
SDK. Don't force them with `dependency_overrides`.

| Package (transitive) | Locked | Latest | Held back by |
| --- | --- | --- | --- |
| `cross_file` | 0.3.5+5 | 0.4.0 | `file_picker` 13.3.3 and its platform packages require `^0.3.5+4` |
| `qr` | 3.0.3 | 4.0.1 | `pdf` → `barcode` 2.2.9 requires `^3.0.0` |
| `material_color_utilities` | 0.13.0 | 0.13.1 | pinned by the Flutter SDK |
| `test_api` (dev) | 0.7.12 | 0.7.15 | pinned by `flutter_test` in the Flutter SDK |

They move when `file_picker`, `barcode` or Flutter itself releases a
compatible update; pick them up then with `flutter pub upgrade`.

`sqlite3` (the SQLite library behind `sqflite_common_ffi`) moved from
3.5.2 to 3.9.1 in this review. The search and migration tests, and the
50,000-interaction benchmark, cover it.
