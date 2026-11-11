# Dependency freshness review — 12 November 2026

`flutter pub upgrade` refreshed every version compatible with the current
Flutter/Dart constraints. `cupertino_icons` and `go_router` were removed
because no production or test source imports them. `sqflite_common_ffi` now
uses its latest compatible patch release, 2.4.7.

`flutter pub outdated` still reports four newer transitive releases. They are
intentionally not forced because their constraints are owned upstream:

- `cross_file` 0.3.5+5 is required by `file_picker` and its platform packages.
- `material_color_utilities` 0.13.0 is supplied by the Flutter SDK.
- `qr` 3.0.3 is required by `barcode`, which is used by `pdf`.
- `test_api` 0.7.12 is supplied by `flutter_test`.

Reassess these holds when upgrading Flutter or the respective direct package;
do not override them independently in the lockfile.
