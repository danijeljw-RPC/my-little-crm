import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schema version 1 exactly as shipped (lib/data/local/app_database.dart at
/// commit d3b370e). Kept verbatim so upgrade tests start from a real v1 file,
/// including its foreign keys, FTS triggers and indexes.
const _v1Schema = [
  'CREATE TABLE parties (id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, created_at TEXT NOT NULL)',
  '''CREATE TABLE interactions (
      id TEXT PRIMARY KEY, party_id TEXT NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
      summary TEXT NOT NULL, timestamp TEXT NOT NULL, created_at TEXT NOT NULL,
      method TEXT NOT NULL, contact_name TEXT, commitment TEXT,
      follow_up_due_at TEXT, follow_up_status TEXT)''',
  'CREATE VIRTUAL TABLE interaction_search USING fts5(id UNINDEXED, summary)',
  'CREATE TRIGGER interaction_search_insert AFTER INSERT ON interactions BEGIN INSERT INTO interaction_search(id, summary) VALUES(new.id, new.summary); END',
  'CREATE TRIGGER interaction_search_delete AFTER DELETE ON interactions BEGIN DELETE FROM interaction_search WHERE id = old.id; END',
  'CREATE TRIGGER interaction_search_update AFTER UPDATE ON interactions BEGIN DELETE FROM interaction_search WHERE id = old.id; INSERT INTO interaction_search(id, summary) VALUES(new.id, new.summary); END',
  'CREATE TABLE interaction_references (interaction_id TEXT NOT NULL REFERENCES interactions(id) ON DELETE CASCADE, value TEXT NOT NULL, PRIMARY KEY (interaction_id, value))',
  'CREATE INDEX interactions_party_timestamp ON interactions(party_id, timestamp DESC)',
  'CREATE INDEX interaction_references_value ON interaction_references(value)',
];

/// Creates a v1 database file populated the way v1 wrote rows: timestamps via
/// `toUtc().toIso8601String()`, which drops the trailing digits when the
/// microseconds are zero and so produces variable-width text.
Future<void> _writeV1Database(
  String path, {
  String earlierTimestamp = '2026-01-01T00:00:00.000Z',
}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('PRAGMA foreign_keys = ON');
  for (final statement in _v1Schema) {
    await db.execute(statement);
  }
  await db.setVersion(1);
  await db.insert('parties', {
    'id': 'acme',
    'name': 'Acme Insurance',
    'created_at': '2025-12-31T23:00:00.000Z',
  });
  await db.insert('parties', {
    'id': 'energie',
    'name': 'Énergie Locale',
    'created_at': '2025-12-31T23:30:00.000Z',
  });
  await db.insert('interactions', {
    'id': 'earlier',
    'party_id': 'acme',
    'summary': 'Premium disputed on renewal',
    'timestamp': earlierTimestamp,
    'created_at': '2026-01-01T00:00:00.000Z',
    'method': 'phone',
    'contact_name': 'ÓSCAR Díaz',
    'commitment': 'Send revised quote',
    'follow_up_due_at': '2026-01-08T09:00:00.000Z',
    'follow_up_status': 'open',
  });
  await db.insert('interactions', {
    'id': 'later',
    'party_id': 'acme',
    'summary': 'Quote accepted',
    // One microsecond later: as v1 text this sorts *before* "…00.000Z".
    'timestamp': '2026-01-01T00:00:00.000001Z',
    'created_at': '2026-01-01T00:00:00.000001Z',
    'method': 'email',
    'follow_up_due_at': '2026-01-02T00:00:00.000Z',
    'follow_up_status': 'completed',
  });
  await db.insert('interactions', {
    'id': 'energie-call',
    'party_id': 'energie',
    'summary': 'Meter reading query',
    'timestamp': '2026-02-01T12:00:00.000Z',
    'created_at': '2026-02-01T12:00:00.000Z',
    'method': 'sms',
  });
  for (final reference in ['CASE-42', 'RÉF-ÉTÉ']) {
    await db.insert('interaction_references', {
      'interaction_id': 'earlier',
      'value': reference,
    });
  }
  await db.close();
}

Future<String> _tempDatabasePath(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() => directory.delete(recursive: true));
  return '${directory.path}/crm.sqlite';
}

Future<Set<String>> _columns(Database db, String table) async => {
  for (final row in await db.rawQuery('PRAGMA table_info($table)'))
    row['name']! as String,
};

void main() {
  test(
    'upgrades a real v1 database to the current schema without data loss',
    () async {
      final path = await _tempDatabasePath('crm-v1-upgrade-');
      await _writeV1Database(path);

      var db = await AppDatabase.open(path: path, useFfi: true);

      // Every party survives with its ID and exact spelling.
      final parties = LocalPartyRepository(db);
      expect(
        {for (final p in await parties.list()) p.id: p.name},
        {'acme': 'Acme Insurance', 'energie': 'Énergie Locale'},
      );

      // Every field of every interaction survives.
      final earlier = (await db.getInteraction('earlier'))!;
      expect(earlier.partyId, 'acme');
      expect(earlier.summary, 'Premium disputed on renewal');
      expect(earlier.timestamp, DateTime.utc(2026));
      expect(earlier.createdAt, DateTime.utc(2026));
      expect(earlier.method, CommunicationMethod.phone);
      expect(earlier.contactName, 'ÓSCAR Díaz');
      expect(earlier.commitment, 'Send revised quote');
      expect(earlier.referenceNumbers, unorderedEquals(['CASE-42', 'RÉF-ÉTÉ']));
      expect(earlier.followUp!.dueAt, DateTime.utc(2026, 1, 8, 9));
      expect(earlier.followUp!.status, FollowUpStatus.open);

      final later = (await db.getInteraction('later'))!;
      expect(later.timestamp, DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 1));
      expect(later.method, CommunicationMethod.email);
      expect(later.contactName, isNull);
      expect(later.referenceNumbers, isEmpty);
      expect(later.followUp!.status, FollowUpStatus.completed);

      final sms = (await db.getInteraction('energie-call'))!;
      expect(sms.partyId, 'energie');
      expect(sms.method, CommunicationMethod.sms);
      expect(sms.followUp, isNull);

      // Timestamp normalization fixes v1's text ordering bug.
      expect((await db.interactionsForParty('acme')).map((i) => i.id), [
        'later',
        'earlier',
      ]);
      expect((await db.openFollowUps()).map((i) => i.id), ['earlier']);

      // Search works across summary FTS, Unicode-folded contact, references and
      // party names that were written before the search columns existed.
      for (final query in [
        'prem disp',
        'óscar',
        'case-42',
        'réf-été',
        'acme insurance',
      ]) {
        expect(
          (await db.searchInteractions(query)).map((i) => i.id),
          contains('earlier'),
          reason: query,
        );
      }
      expect(
        (await db.searchInteractions('ÉNERGIE')).single.id,
        'energie-call',
      );

      // The v1 FTS triggers still fire for edits made after the upgrade.
      await db.saveInteraction(earlier.copyWith(summary: 'Dispute resolved'));
      expect(await db.searchInteractions('prem disp'), isEmpty);
      expect((await db.searchInteractions('resolved')).single.id, 'earlier');
      await db.close();

      // The file is now at the current version with the new columns, and every
      // stored timestamp has the fixed-width form.
      final raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.getVersion(), AppDatabase.schemaVersion);
      expect(await _columns(raw, 'parties'), contains('name_search'));
      expect(
        await _columns(raw, 'interactions'),
        containsAll(['summary_search', 'contact_name_search']),
      );
      expect(
        await _columns(raw, 'interaction_references'),
        contains('value_search'),
      );
      for (final row in await raw.query('interactions')) {
        for (final column in ['timestamp', 'created_at', 'follow_up_due_at']) {
          final value = row[column] as String?;
          if (value == null) continue;
          expect(
            value,
            matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$')),
            reason: '${row['id']}.$column',
          );
        }
      }
      await raw.close();

      // Reopening does not re-run the migration (a second ALTER TABLE would
      // throw) and the edit made after the upgrade persists.
      db = await AppDatabase.open(path: path, useFfi: true);
      addTearDown(db.close);
      expect((await db.getInteraction('earlier'))!.summary, 'Dispute resolved');
      expect((await db.interactionsForParty('acme')).length, 2);
    },
  );

  test('a failed upgrade rolls back and leaves the v1 data intact', () async {
    final path = await _tempDatabasePath('crm-v1-rollback-');
    await _writeV1Database(path, earlierTimestamp: 'not-a-timestamp');

    // The v2 step succeeds; the v3 step cannot parse the corrupt timestamp.
    await expectLater(
      AppDatabase.open(path: path, useFfi: true),
      throwsA(isA<FormatException>()),
    );

    final raw = await databaseFactoryFfi.openDatabase(path);
    addTearDown(raw.close);
    expect(await raw.getVersion(), 1);
    // The v2 step's ALTER TABLE was rolled back along with everything else.
    expect(await _columns(raw, 'parties'), isNot(contains('name_search')));
    expect(
      await _columns(raw, 'interactions'),
      isNot(contains('summary_search')),
    );
    expect(
      (await raw.query('interactions', orderBy: 'id')).map((r) => r['id']),
      ['earlier', 'energie-call', 'later'],
    );
    expect(
      (await raw.query(
        'interactions',
        where: 'id = ?',
        whereArgs: ['later'],
      )).single['timestamp'],
      '2026-01-01T00:00:00.000001Z',
    );
    expect(await raw.query('interaction_references'), hasLength(2));
  });
}
