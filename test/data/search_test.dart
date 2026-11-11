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
