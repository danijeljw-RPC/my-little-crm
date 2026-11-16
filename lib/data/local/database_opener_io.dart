// Native (dart:io) database opening. The web counterpart is
// database_opener_web.dart; app_database.dart picks one by conditional import
// so the web build never sees dart:io, dart:ffi or the sqflite plugin (#30).
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where the live database lives: the app's private, persistent Application
/// Support directory, resolved by path_provider at run time (#54):
///
/// - macOS (sandboxed): `~/Library/Containers/<bundle id>/Data/Library/`
///   `Application Support/<bundle id>/`
/// - iOS: `<app container>/Library/Application Support/`
/// - Android: `/data/data/<applicationId>/files/`
/// - Windows: `%APPDATA%\<CompanyName>\<ProductName>\`
/// - Linux: `$XDG_DATA_HOME` (`~/.local/share`)`/<APPLICATION_ID>/`
///
/// Never inside the app bundle, so it survives updates and reinstalls of
/// new release builds. User-chosen locations are only for exports.
Future<String> defaultDatabasePath(
  String fileName, {
  Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory,
}) async => '${(await supportDirectory()).path}/$fileName';

/// Opens (creating if needed) the database file at [path], or at
/// [defaultDatabasePath] when it is null.
Future<Database> openFileDatabase(
  String? path, {
  required String fileName,
  required bool useFfi,
  required OpenDatabaseOptions options,
}) async {
  final factory =
      !useFfi && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
      ? native.databaseFactory
      : databaseFactoryFfi;
  if (useFfi || Platform.isWindows || Platform.isLinux) sqfliteFfiInit();
  final location = path ?? await defaultDatabasePath(fileName);
  await Directory(File(location).parent.path).create(recursive: true);
  return factory.openDatabase(location, options: options);
}

/// A private in-memory database: nothing is written to disk.
Future<Database> openMemoryDatabase() {
  sqfliteFfiInit();
  // Each call gets its own private in-memory database.
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
}
