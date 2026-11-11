import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:io';

import 'package:sqflite/sqflite.dart' as native;
import 'package:path_provider/path_provider.dart';

import '../../domain/models.dart';

/// Versioned SQLite store with Dart-normalized Unicode search values.
class AppDatabase {
  AppDatabase._(this._database);

  static const schemaVersion = 2;
  final Database _database;

  static Future<AppDatabase> open({String? path, bool useFfi = false}) async {
    final factory =
        !useFfi && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
        ? native.databaseFactory
        : databaseFactoryFfi;
    if (useFfi || Platform.isWindows || Platform.isLinux) sqfliteFfiInit();
    final location =
        path ?? '${(await getApplicationSupportDirectory()).path}/crm.sqlite';
    await Directory(File(location).parent.path).create(recursive: true);
    final database = await factory.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA recursive_triggers = ON');
        },
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _addUnicodeSearchColumns(db);
        },
      ),
    );
    return AppDatabase._(database);
  }

  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await _createSchema(database);
    await database.execute('PRAGMA foreign_keys = ON');
    await database.execute('PRAGMA recursive_triggers = ON');
    return AppDatabase._(database);
  }

  static Future<void> _createSchema(Database database) async {
    await database.execute(
      'CREATE TABLE parties (id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, created_at TEXT NOT NULL)',
    );
    await database.execute('''CREATE TABLE interactions (
      id TEXT PRIMARY KEY, party_id TEXT NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
      summary TEXT NOT NULL, timestamp TEXT NOT NULL, created_at TEXT NOT NULL,
      method TEXT NOT NULL, contact_name TEXT, commitment TEXT,
      follow_up_due_at TEXT, follow_up_status TEXT)''');
    try {
      await database.execute(
        'CREATE VIRTUAL TABLE interaction_search USING fts5(id UNINDEXED, summary)',
      );
    } on DatabaseException {
      await database.execute(
        'CREATE VIRTUAL TABLE interaction_search USING fts4(id, summary)',
      );
    }
    await database.execute(
      'CREATE TRIGGER interaction_search_insert AFTER INSERT ON interactions BEGIN INSERT INTO interaction_search(id, summary) VALUES(new.id, new.summary); END',
    );
    await database.execute(
      'CREATE TRIGGER interaction_search_delete AFTER DELETE ON interactions BEGIN DELETE FROM interaction_search WHERE id = old.id; END',
    );
    await database.execute(
      'CREATE TRIGGER interaction_search_update AFTER UPDATE ON interactions BEGIN DELETE FROM interaction_search WHERE id = old.id; INSERT INTO interaction_search(id, summary) VALUES(new.id, new.summary); END',
    );
    await database.execute(
      'CREATE TABLE interaction_references (interaction_id TEXT NOT NULL REFERENCES interactions(id) ON DELETE CASCADE, value TEXT NOT NULL, PRIMARY KEY (interaction_id, value))',
    );
    await database.execute(
      'CREATE INDEX interactions_party_timestamp ON interactions(party_id, timestamp DESC)',
    );
    await database.execute(
      'CREATE INDEX interaction_references_value ON interaction_references(value)',
    );
    await _addUnicodeSearchColumns(database);
  }

  static Future<void> _addUnicodeSearchColumns(Database database) async {
    // The same Dart lowercase mapping is applied once on migration and on every
    // write/query; SQLite lower() only maps ASCII on these native builds.
    for (final entry in {
      'parties': ['name'],
      'interactions': ['summary', 'contact_name'],
      'interaction_references': ['value'],
    }.entries) {
      for (final column in entry.value) {
        await database.execute(
          'ALTER TABLE ${entry.key} ADD COLUMN ${column}_search TEXT',
        );
      }
      for (final row in await database.rawQuery(
        'SELECT rowid AS migration_rowid, * FROM ${entry.key}',
      )) {
        await database.update(
          entry.key,
          {
            for (final column in entry.value)
              '${column}_search': (row[column] as String?)?.toLowerCase(),
          },
          where: 'rowid = ?',
          whereArgs: [row['migration_rowid']],
        );
      }
    }
    await database.execute(
      'CREATE INDEX parties_name_search ON parties(name_search)',
    );
    await database.execute(
      'CREATE INDEX interactions_contact_search ON interactions(contact_name_search)',
    );
    await database.execute(
      'CREATE INDEX references_value_search ON interaction_references(value_search)',
    );
  }

  Future<Party?> partyByName(String name) async {
    final rows = await _database.query(
      'parties',
      where: 'name_search = ?',
      whereArgs: [name.toLowerCase()],
    );
    return rows.isEmpty ? null : _party(rows.single);
  }

  Future<Party?> partyById(PartyId id) async {
    final rows = await _database.query(
      'parties',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _party(rows.single);
  }

  Future<List<Party>> allParties() async => Future.wait(
    (await _database.query(
      'parties',
      orderBy: 'name COLLATE NOCASE',
    )).map(_party),
  );

  Future<Party> insertParty(Party party) async {
    await _database.insert('parties', {
      'id': party.id,
      'name': party.name,
      'name_search': party.name.toLowerCase(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return party;
  }

  Future<Interaction> saveInteraction(Interaction input) async {
    final existing = await getInteraction(input.id);
    final item = existing == null
        ? input
        : input.copyWith(createdAt: existing.createdAt);
    await _database.transaction((transaction) async {
      await transaction.insert('interactions', {
        'id': item.id,
        'party_id': item.partyId,
        'summary': item.summary,
        'summary_search': item.summary.toLowerCase(),
        'timestamp': _utc(item.timestamp),
        'created_at': _utc(item.createdAt),
        'method': item.method.name,
        'contact_name': item.contactName,
        'contact_name_search': item.contactName?.toLowerCase(),
        'commitment': item.commitment,
        'follow_up_due_at': item.followUp == null
            ? null
            : _utc(item.followUp!.dueAt),
        'follow_up_status': item.followUp?.status.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.delete(
        'interaction_references',
        where: 'interaction_id = ?',
        whereArgs: [item.id],
      );
      for (final reference in item.referenceNumbers) {
        await transaction.insert('interaction_references', {
          'interaction_id': item.id,
          'value': reference,
          'value_search': reference.toLowerCase(),
        });
      }
    });
    return item;
  }

  Future<Interaction?> getInteraction(InteractionId id) async {
    final rows = await _database.query(
      'interactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _interaction(rows.single);
  }

  Future<List<Interaction>> interactionsForParty(PartyId partyId) async =>
      _load(
        await _database.query(
          'interactions',
          where: 'party_id = ?',
          whereArgs: [partyId],
          orderBy: 'timestamp DESC',
        ),
      );

  Future<List<Interaction>> openFollowUps() async => _load(
    await _database.query(
      'interactions',
      where: 'follow_up_status = ?',
      whereArgs: [FollowUpStatus.open.name],
      orderBy: 'follow_up_due_at ASC',
    ),
  );

  Future<List<Interaction>> searchInteractions(String query) async {
    if (query.trim().isEmpty) return [];
    final escaped = query
        .trim()
        .toLowerCase()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final like = '%$escaped%';
    // Inspect the persisted virtual table: reopening must keep its query dialect
    // even if this device also supports another FTS module.
    final schema = await _database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = 'interaction_search'",
    );
    final usesFts4 = RegExp(
      r'USING\s+fts4\b',
      caseSensitive: false,
    ).hasMatch(schema.single['sql'] as String);
    final tokens = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(query)
        .map((m) => usesFts4 ? '"${m.group(0)}*"' : '"${m.group(0)}"*')
        .join(' AND ');
    return _load(
      await _database.rawQuery(
        '''SELECT DISTINCT i.* FROM interactions i
      JOIN parties p ON p.id = i.party_id LEFT JOIN interaction_references r ON r.interaction_id = i.id
      WHERE i.id IN (SELECT id FROM interaction_search WHERE summary MATCH ?)
      OR i.summary_search LIKE ? ESCAPE '\\' OR p.name_search LIKE ? ESCAPE '\\' OR i.contact_name_search LIKE ? ESCAPE '\\' OR r.value_search LIKE ? ESCAPE '\\'
      ORDER BY i.timestamp DESC''',
        [tokens.isEmpty ? '""' : tokens, like, like, like, like],
      ),
    );
  }

  Future<List<Interaction>> _load(List<Map<String, Object?>> rows) =>
      Future.wait(rows.map(_interaction));
  Future<Party> _party(Map<String, Object?> row) async =>
      Party(id: row['id']! as String, name: row['name']! as String);
  Future<Interaction> _interaction(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final references = await _database.query(
      'interaction_references',
      columns: ['value'],
      where: 'interaction_id = ?',
      whereArgs: [id],
    );
    final dueAt = row['follow_up_due_at'] as String?;
    final status = row['follow_up_status'] as String?;
    return Interaction(
      id: id,
      partyId: row['party_id']! as String,
      summary: row['summary']! as String,
      timestamp: DateTime.parse(row['timestamp']! as String).toUtc(),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      method: CommunicationMethod.values.byName(row['method']! as String),
      contactName: row['contact_name'] as String?,
      referenceNumbers: references
          .map((reference) => reference['value']! as String)
          .toList(growable: false),
      commitment: row['commitment'] as String?,
      followUp: dueAt == null
          ? null
          : FollowUp(
              dueAt: DateTime.parse(dueAt).toUtc(),
              status: FollowUpStatus.values.byName(status!),
            ),
    );
  }

  static String _utc(DateTime value) => value.toUtc().toIso8601String();
  Future<void> close() => _database.close();
}
