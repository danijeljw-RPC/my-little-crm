import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/core/clock.dart';

void main() {
  test('ranks exact references before newer incidental text matches', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final party = await LocalPartyRepository(db).findOrCreate('Party');
    for (final id in ['exact-old', 'exact-new', 'incidental']) {
      final time = DateTime.utc(
        2026,
        1,
        id == 'exact-old'
            ? 1
            : id == 'exact-new'
            ? 2
            : 3,
      );
      await db.saveInteraction(
        Interaction(
          id: id,
          partyId: party.id,
          summary: id == 'incidental'
              ? 'Discussed CASE-42 briefly'
              : 'Support call',
          referenceNumbers: id == 'incidental' ? [] : ['CASE-42'],
          timestamp: time,
          createdAt: time,
        ),
      );
    }
    expect((await db.searchInteractions('CASE-42')).map((i) => i.id), [
      'exact-new',
      'exact-old',
      'incidental',
    ]);
  });

  test(
    'migrates schema 2 timestamps and retains search after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp('crm-v2-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.sqlite';
      var db = await AppDatabase.open(path: path, useFfi: true);
      final party = await LocalPartyRepository(db).findOrCreate('Party');
      for (final offset in [0, 1]) {
        final time = DateTime.utc(2026).add(Duration(microseconds: offset));
        await db.saveInteraction(
          Interaction(
            id: '$offset',
            partyId: party.id,
            summary: 'Premium disputed: CASE-42.',
            timestamp: time,
            createdAt: time,
            followUp: FollowUp(dueAt: time),
          ),
        );
      }
      await db.close();
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.update(
        'interactions',
        {
          'timestamp': '2026-01-01T00:00:00.000Z',
          'created_at': '2026-01-01T00:00:00.000Z',
          'follow_up_due_at': '2026-01-01T00:00:00.000Z',
        },
        where: 'id = ?',
        whereArgs: ['0'],
      );
      await legacy.setVersion(2);
      await legacy.close();
      db = await AppDatabase.open(path: path, useFfi: true);
      addTearDown(db.close);
      expect((await db.interactionsForParty(party.id)).map((i) => i.id), [
        '1',
        '0',
      ]);
      expect((await db.openFollowUps()).map((i) => i.id), ['0', '1']);
      expect(await db.searchInteractions('prem disp'), hasLength(2));
      expect(await db.searchInteractions('CASE-42.'), hasLength(2));
      expect(await db.searchInteractions('%'), isEmpty);
      final item = (await db.getInteraction('0'))!;
      await db.saveInteraction(item.copyWith(summary: 'Resolved'));
      expect((await db.searchInteractions('prem disp')).single.id, '1');
      expect((await db.searchInteractions('resolved')).single.id, '0');
    },
  );

  test(
    'migration preserves histories when Unicode party names fold together',
    () async {
      final directory = await Directory.systemTemp.createTemp('crm-collision-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.sqlite';
      sqfliteFfiInit();
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute(
        'CREATE TABLE parties(id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, created_at TEXT)',
      );
      await legacy.execute(
        'CREATE TABLE interactions(id TEXT PRIMARY KEY, party_id TEXT, summary TEXT, timestamp TEXT, created_at TEXT, method TEXT, contact_name TEXT, commitment TEXT, follow_up_due_at TEXT, follow_up_status TEXT)',
      );
      await legacy.execute(
        'CREATE TABLE interaction_references(interaction_id TEXT, value TEXT)',
      );
      await legacy.execute(
        'CREATE VIRTUAL TABLE interaction_search USING fts5(id UNINDEXED, summary)',
      );
      for (final entry in {'a': 'Énergie', 'b': 'énergie'}.entries) {
        await legacy.insert('parties', {
          'id': entry.key,
          'name': entry.value,
          'created_at': '2026-11-11T00:00:00Z',
        });
        await legacy.insert('interactions', {
          'id': 'record-${entry.key}',
          'party_id': entry.key,
          'summary': 'Call ${entry.key}',
          'timestamp': '2026-11-11T00:00:00Z',
          'created_at': '2026-11-11T00:00:00Z',
          'method': 'phone',
        });
      }
      await legacy.setVersion(1);
      await legacy.close();
      final db = await AppDatabase.open(path: path, useFfi: true);
      addTearDown(db.close);
      final parties = LocalPartyRepository(db);
      expect((await parties.findOrCreate('Énergie')).id, 'a');
      expect((await parties.findOrCreate('énergie')).id, 'b');
      expect((await parties.findOrCreate('éNERGIE')).id, 'a');
      final service = CrmService(
        parties: parties,
        interactions: LocalInteractionRepository(db),
        clock: FixedClock(DateTime.utc(2026, 11, 11)),
      );
      final added = await service.createInteraction(
        const CreateInteractionCommand(
          partyName: 'énergie',
          summary: 'New call',
        ),
      );
      expect(added.partyId, 'b');
      final edited = (await db.getInteraction('record-a'))!
          .copyWith(summary: 'Edited call');
      await db.saveInteraction(edited);
      expect(
        (await db.interactionsForParty('a')).single.summary,
        'Edited call',
      );
      expect((await db.interactionsForParty('b')).length, 2);
      expect((await parties.list()).map((p) => p.id), ['a', 'b']);
    },
  );
  test(
    'search folds Unicode party, contact and references in migrated v1 records',
    () async {
      final directory = await Directory.systemTemp.createTemp('crm-unicode-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.sqlite';
      sqfliteFfiInit();
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute(
        'CREATE TABLE parties(id TEXT PRIMARY KEY, name TEXT, created_at TEXT)',
      );
      await legacy.execute(
        'CREATE TABLE interactions(id TEXT PRIMARY KEY, party_id TEXT, summary TEXT, timestamp TEXT, created_at TEXT, method TEXT, contact_name TEXT, commitment TEXT, follow_up_due_at TEXT, follow_up_status TEXT)',
      );
      await legacy.execute(
        'CREATE TABLE interaction_references(interaction_id TEXT, value TEXT)',
      );
      await legacy.execute(
        'CREATE VIRTUAL TABLE interaction_search USING fts5(id UNINDEXED, summary)',
      );
      await legacy.insert('parties', {
        'id': 'party',
        'name': 'Énergie',
        'created_at': '2026-11-11T00:00:00Z',
      });
      await legacy.insert('interactions', {
        'id': 'legacy',
        'party_id': 'party',
        'summary': 'Billing call',
        'timestamp': '2026-11-11T00:00:00Z',
        'created_at': '2026-11-11T00:00:00Z',
        'method': 'phone',
        'contact_name': 'ÓSCAR',
      });
      await legacy.insert('interaction_references', {
        'interaction_id': 'legacy',
        'value': 'RÉF-ÉTÉ',
      });
      await legacy.setVersion(1);
      await legacy.close();
      var db = await AppDatabase.open(path: path, useFfi: true);
      for (final query in [
        'Énergie',
        'éNERGIE',
        'ÓSCAR',
        'óscar',
        'RÉF-ÉTÉ',
        'réf-éTé',
      ]) {
        expect(
          (await db.searchInteractions(query)).single.id,
          'legacy',
          reason: query,
        );
      }
      final party = await LocalPartyRepository(db).findOrCreate('éNERGIE');
      expect(party.id, 'party');
      await db.saveInteraction(
        Interaction(
          id: 'new',
          partyId: party.id,
          summary: 'Service call',
          timestamp: DateTime.utc(2026),
          createdAt: DateTime.utc(2026),
          contactName: 'ÀLEX',
          referenceNumbers: const ['ÉX-42'],
        ),
      );
      await db.close();
      db = await AppDatabase.open(path: path, useFfi: true);
      addTearDown(db.close);
      expect((await db.searchInteractions('àLeX')).single.id, 'new');
      expect((await db.searchInteractions('éX-42')).single.id, 'new');
      expect((await db.searchInteractions('énergie')).length, 2);
    },
  );
  test('disk restart retains all fields, search edits remove old index and IDs are unique', () async {
    final directory = await Directory.systemTemp.createTemp('crm-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/test.sqlite';
    var db = await AppDatabase.open(path: path, useFfi: true);
    final parties = LocalPartyRepository(db);
    final party = await parties.findOrCreate('BrightSure');
    var repository = LocalInteractionRepository(db);
    final now = DateTime.utc(2026, 11, 11);
    await repository.save(
      Interaction(
        id: 'one',
        partyId: party.id,
        summary: 'Premium disputed: BS-841902.',
        timestamp: now,
        createdAt: now,
        method: CommunicationMethod.email,
        contactName: 'Alex',
        referenceNumbers: const ['BS-841902'],
        commitment: 'Refund',
        followUp: FollowUp(dueAt: now),
      ),
    );
    expect((await repository.search('8419')).single.id, 'one');
    expect(await repository.search('%'), isEmpty);
    expect(await repository.search(' '), isEmpty);
    await db.close();
    db = await AppDatabase.open(path: path, useFfi: true);
    addTearDown(db.close);
    repository = LocalInteractionRepository(db);
    final item = (await repository.get('one'))!;
    expect(item.contactName, 'Alex');
    expect(item.referenceNumbers, ['BS-841902']);
    expect(item.commitment, 'Refund');
    expect(item.method, CommunicationMethod.email);
    expect(item.followUp!.dueAt, now);
    await repository.save(
      item.copyWith(summary: 'Settled', createdAt: DateTime.utc(2030)),
    );
    expect((await repository.get('one'))!.createdAt, now);
    expect(await repository.search('premium'), isEmpty);
    expect((await repository.search('settled')).single.id, 'one');
    final service = CrmService(
      parties: LocalPartyRepository(db),
      interactions: repository,
      clock: FixedClock(now),
    );
    final a = await service.createInteraction(
      const CreateInteractionCommand(partyName: 'BrightSure', summary: 'First'),
    );
    final b = await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Second',
      ),
    );
    expect(a.id, isNot(b.id));
  });
}
