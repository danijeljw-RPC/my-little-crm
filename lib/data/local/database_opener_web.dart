// Browser database opening (#30). SQLite runs as WebAssembly in the page
// (web/sqlite3.wasm, fetched by `dart run sqflite_common_ffi_web:setup`).
//
// Only in-memory databases are offered: nothing is written to IndexedDB, OPFS
// or localStorage, so refreshing or closing the tab discards every change.
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// No web worker: the database lives and dies with this page, and is never
/// shared with (or kept alive by) another tab.
final DatabaseFactory _memoryFactory = createDatabaseFactoryFfiWeb(
  options: SqfliteFfiWebOptions(inMemory: true),
  noWebWorker: true,
  tag: 'demo',
);

Future<String> defaultDatabasePath(String fileName) =>
    throw UnsupportedError(_noFiles);

Future<Database> openFileDatabase(
  String? path, {
  required String fileName,
  required bool useFfi,
  required OpenDatabaseOptions options,
}) => throw UnsupportedError(_noFiles);

Future<Database> openMemoryDatabase() =>
    _memoryFactory.openDatabase(inMemoryDatabasePath);

const _noFiles =
    'The web build has no persistent storage; use AppDatabase.inMemory().';
