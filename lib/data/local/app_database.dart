import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:io';

import 'package:sqflite/sqflite.dart' as native;
import 'package:path_provider/path_provider.dart';

import '../../domain/models.dart';

/// Versioned SQLite store with Dart-normalized Unicode search values.
class AppDatabase {
  AppDatabase._(this._database);

  static const schemaVersion = 4;
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
          if (oldVersion < 3) await _normalizeTimestamps(db);
          if (oldVersion < 4) await _addFollowUpTimeAndIndexes(db);
        },
      ),
    );
    return AppDatabase._(database);
  }

  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    // Each call gets its own private in-memory database.
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
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
    await _addFollowUpTimeAndIndexes(database);
  }

  /// Schema 4: optional follow-up due time (#34) and indexes for the paged
  /// home list and the follow-up list (#39).
  static Future<void> _addFollowUpTimeAndIndexes(Database database) async {
    final columns = await database.rawQuery('PRAGMA table_info(interactions)');
    if (!columns.any((c) => c['name'] == 'follow_up_has_time')) {
      await database.execute(
        'ALTER TABLE interactions ADD COLUMN follow_up_has_time INTEGER NOT NULL DEFAULT 0',
      );
    }
    // Chosen from tool/benchmark/ledger_benchmark_test.dart; see
    // docs/delivery/STAGE-1-REVIEW.md for before/after timings.
    await database.execute(
      'CREATE INDEX IF NOT EXISTS interactions_timestamp_id ON interactions(timestamp DESC, id DESC)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS interactions_follow_up ON interactions(follow_up_status, follow_up_due_at)',
    );
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

  static Future<void> _normalizeTimestamps(Database database) async {
    for (final entry in {
      'parties': ['created_at'],
      'interactions': ['timestamp', 'created_at', 'follow_up_due_at'],
    }.entries) {
      for (final row in await database.query(entry.key)) {
        await database.update(
          entry.key,
          {
            for (final column in entry.value)
              if (row[column] != null)
                column: _utc(DateTime.parse(row[column] as String)),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  Future<Party> findOrCreateParty(Party candidate) => _database.transaction(
    (transaction) async =>
        await _partyByName(candidate.name, transaction) ??
        await _insertParty(candidate, transaction),
  );

  Future<Party?> _partyByName(String name, DatabaseExecutor executor) async {
    // Version 1's ASCII-only uniqueness allowed distinct Unicode spellings
    // that now fold together. Preserve their IDs and prefer an exact spelling;
    // otherwise select the smallest immutable ID for a stable fallback.
    final rows = await executor.rawQuery(
      '''SELECT * FROM parties
      WHERE name_search = ?
      ORDER BY CASE WHEN name COLLATE BINARY = ? THEN 0 ELSE 1 END, id COLLATE BINARY
      LIMIT 1''',
      [name.toLowerCase(), name],
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

  Future<Party> restoreParty(Party party) async {
    await _insertParty(party, _database);
    return party;
  }

  Future<Party> renameParty(PartyId id, String name) => _database.transaction((
    transaction,
  ) async {
    final current = await transaction.query(
      'parties',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (current.isEmpty) throw StateError('Party no longer exists');
    final clash = await transaction.query(
      'parties',
      where: 'name_search = ? AND id != ?',
      whereArgs: [name.toLowerCase(), id],
      limit: 1,
    );
    if (clash.isNotEmpty) throw PartyNameConflict(await _party(clash.single));
    await transaction.update(
      'parties',
      {'name': name, 'name_search': name.toLowerCase()},
      where: 'id = ?',
      whereArgs: [id],
    );
    return Party(id: id, name: name);
  });

  Future<void> mergeParties({
    required PartyId source,
    required PartyId target,
  }) => _database.transaction((transaction) async {
    final found = await transaction.query(
      'parties',
      columns: ['id'],
      where: 'id IN (?, ?)',
      whereArgs: [source, target],
    );
    if (found.length != 2) throw StateError('Party no longer exists');
    await transaction.update(
      'interactions',
      {'party_id': target},
      where: 'party_id = ?',
      whereArgs: [source],
    );
    await transaction.delete('parties', where: 'id = ?', whereArgs: [source]);
  });

  Future<void> deleteParty(PartyId id) =>
      _database.transaction((transaction) async {
        // Delete interactions explicitly (rather than relying only on the
        // cascade) so the FTS delete trigger runs for each row.
        await transaction.delete(
          'interactions',
          where: 'party_id = ?',
          whereArgs: [id],
        );
        await transaction.delete('parties', where: 'id = ?', whereArgs: [id]);
      });

  Future<Party> _insertParty(Party party, DatabaseExecutor executor) async {
    await executor.insert('parties', {
      'id': party.id,
      'name': party.name,
      'name_search': party.name.toLowerCase(),
      'created_at': _utc(DateTime.now()),
    });
    return party;
  }

  Future<Interaction> saveInteraction(Interaction input) =>
      _database.transaction((transaction) => _write(transaction, input));

  /// Saves many interactions in one transaction: all or nothing.
  Future<void> saveInteractions(List<Interaction> items) =>
      _database.transaction((transaction) async {
        for (final item in items) {
          await _write(transaction, item);
        }
      });

  Future<Interaction> _write(Transaction transaction, Interaction input) async {
    {
      final existing = await transaction.query(
        'interactions',
        columns: ['created_at'],
        where: 'id = ?',
        whereArgs: [input.id],
      );
      final item = existing.isEmpty
          ? input
          : input.copyWith(
              createdAt: DateTime.parse(
                existing.single['created_at'] as String,
              ),
            );
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
        'follow_up_has_time': item.followUp?.hasTime ?? false ? 1 : 0,
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
      return item;
    }
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

  Future<void> deleteInteraction(InteractionId id) =>
      _database.delete('interactions', where: 'id = ?', whereArgs: [id]);

  Future<int> countInteractions({PartyId? partyId}) async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS n FROM interactions'
      '${partyId == null ? '' : ' WHERE party_id = ?'}',
      [?partyId],
    );
    return rows.single['n']! as int;
  }

  Future<List<Interaction>> allInteractions() async => _load(
    await _database.query('interactions', orderBy: 'timestamp ASC, id ASC'),
  );

  /// Newest-first page joined with the party name, ordered and limited in
  /// SQLite (#39). Pages continue strictly after [after].
  Future<List<InteractionEntry>> recentInteractions({
    int limit = 50,
    RecentCursor? after,
  }) async {
    final rows = await _database.rawQuery(
      '''SELECT i.*, p.name AS party_name FROM interactions i
      JOIN parties p ON p.id = i.party_id
      ${after == null ? '' : 'WHERE i.timestamp < ? OR (i.timestamp = ? AND i.id < ?)'}
      ORDER BY i.timestamp DESC, i.id DESC
      LIMIT ?''',
      [
        if (after != null) ...[
          _utc(after.timestamp),
          _utc(after.timestamp),
          after.id,
        ],
        limit,
      ],
    );
    final items = await _load(rows);
    return [
      for (var index = 0; index < rows.length; index++)
        InteractionEntry(
          party: Party(
            id: items[index].partyId,
            name: rows[index]['party_name']! as String,
          ),
          interaction: items[index],
        ),
    ];
  }

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
      ORDER BY CASE
        WHEN EXISTS (SELECT 1 FROM interaction_references exact_ref
          WHERE exact_ref.interaction_id = i.id AND exact_ref.value_search = ?) THEN 0
        WHEN p.name_search = ? OR i.contact_name_search = ? OR i.summary_search = ? THEN 1
        ELSE 2 END, i.timestamp DESC, i.id''',
        [
          tokens.isEmpty ? '""' : tokens,
          like,
          like,
          like,
          like,
          query.trim().toLowerCase(),
          query.trim().toLowerCase(),
          query.trim().toLowerCase(),
          query.trim().toLowerCase(),
        ],
      ),
    );
  }

  /// Builds interactions from rows, loading all their references in batched
  /// queries instead of one query per row.
  Future<List<Interaction>> _load(List<Map<String, Object?>> rows) async {
    final ids = [for (final row in rows) row['id']! as String];
    final references = <String, List<String>>{};
    const chunk = 500;
    for (var start = 0; start < ids.length; start += chunk) {
      final slice = ids.sublist(start, (start + chunk).clamp(0, ids.length));
      for (final row in await _database.query(
        'interaction_references',
        columns: ['interaction_id', 'value'],
        where:
            'interaction_id IN (${List.filled(slice.length, '?').join(', ')})',
        whereArgs: slice,
        orderBy: 'interaction_id, value',
      )) {
        (references[row['interaction_id']! as String] ??= []).add(
          row['value']! as String,
        );
      }
    }
    return [
      for (final row in rows)
        _fromRow(row, references[row['id']! as String] ?? const []),
    ];
  }

  Future<Party> _party(Map<String, Object?> row) async =>
      Party(id: row['id']! as String, name: row['name']! as String);
  Future<Interaction> _interaction(Map<String, Object?> row) async =>
      (await _load([row])).single;

  Interaction _fromRow(Map<String, Object?> row, List<String> references) {
    final id = row['id']! as String;
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
      referenceNumbers: List.unmodifiable(references),
      commitment: row['commitment'] as String?,
      followUp: dueAt == null
          ? null
          : FollowUp(
              dueAt: DateTime.parse(dueAt).toUtc(),
              status: FollowUpStatus.values.byName(status!),
              hasTime: (row['follow_up_has_time'] as int? ?? 0) != 0,
            ),
    );
  }

  static String _utc(DateTime value) {
    final utc = value.toUtc();
    final iso = utc.toIso8601String();
    // Dart omits the final three fractional digits when microseconds are zero.
    // Fixed-width values preserve chronological order in SQLite TEXT indexes.
    return utc.microsecond == 0
        ? '${iso.substring(0, iso.length - 1)}000Z'
        : iso;
  }

  @visibleForTesting
  Future<int> debugCount(String table) async =>
      (await _database.rawQuery('SELECT COUNT(*) AS n FROM $table'))
              .single['n']!
          as int;

  @visibleForTesting
  Future<bool> debugIndexExists(String name) async => (await _database.query(
    'sqlite_master',
    where: "type = 'index' AND name = ?",
    whereArgs: [name],
  )).isNotEmpty;

  Future<void> close() => _database.close();
}
