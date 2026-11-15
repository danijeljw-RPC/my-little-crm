import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/ledger.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<(AppDatabase, CrmService)> _open() async {
  final db = await AppDatabase.inMemory();
  addTearDown(db.close);
  return (
    db,
    CrmService(
      parties: LocalPartyRepository(db),
      interactions: LocalInteractionRepository(db),
      clock: FixedClock(DateTime.utc(2026, 11, 15, 12)),
    ),
  );
}

Future<Interaction> _record(
  CrmService service,
  String party,
  String summary, {
  List<String> references = const [],
  DateTime? at,
}) => service.createInteraction(
  CreateInteractionCommand(
    partyName: party,
    summary: summary,
    referenceNumbers: references,
    contactName: 'Sam $summary',
    timestamp: at,
  ),
);

void main() {
  group('delete (#36)', () {
    test('removes the row, its references and every search entry', () async {
      final (db, service) = await _open();
      final item = await _record(
        service,
        'BrightSure',
        'Refund promised',
        references: ['CASE-9'],
      );
      final keep = await _record(service, 'BrightSure', 'Other call');
      expect(await service.searchInteractions('refund'), hasLength(1));

      final deleted = await service.deleteInteraction(item.id);
      expect(deleted!.id, item.id);
      expect(await service.getInteraction(item.id), isNull);
      for (final query in ['refund', 'CASE-9', 'Sam Refund']) {
        expect(await service.searchInteractions(query), isEmpty, reason: query);
      }
      expect(await db.debugCount('interaction_references'), 0);
      expect(await db.debugCount('interaction_search'), 1);
      expect((await service.partyHistory(item.partyId)).single.id, keep.id);
    });

    test('undo restores the identical record and its search entries', () async {
      final (_, service) = await _open();
      final item = await _record(
        service,
        'BrightSure',
        'Refund promised',
        references: ['CASE-9'],
      );
      await service.deleteInteraction(item.id);
      await service.restoreInteraction(item);
      final back = (await service.getInteraction(item.id))!;
      expect(back.createdAt, item.createdAt);
      expect(back.referenceNumbers, ['CASE-9']);
      expect((await service.searchInteractions('CASE-9')).single.id, item.id);
    });

    test('deleting a party cascades and leaves no stale search hits', () async {
      final (db, service) = await _open();
      final a = await _record(
        service,
        'BrightSure',
        'First',
        references: ['R1'],
      );
      await _record(service, 'BrightSure', 'Second');
      final other = await _record(service, 'Acme', 'Unrelated');
      expect(await service.partyInteractionCount(a.partyId), 2);

      await service.deleteParty(a.partyId);
      expect(await service.parties.get(a.partyId), isNull);
      expect(await service.partyHistory(a.partyId), isEmpty);
      expect(await service.searchInteractions('BrightSure'), isEmpty);
      expect(await service.searchInteractions('First'), isEmpty);
      expect(await service.searchInteractions('R1'), isEmpty);
      expect(await db.debugCount('interaction_search'), 1);
      expect(await db.debugCount('interaction_references'), 0);
      expect(
        (await service.searchInteractions('Unrelated')).single.id,
        other.id,
      );
    });
  });

  group('party editor (#32)', () {
    test('rename keeps the ID and updates search columns', () async {
      final (_, service) = await _open();
      final item = await _record(service, 'BrightSure', 'Call');
      final renamed = await service.renameParty(
        item.partyId,
        ' Brightsure Ins. ',
      );
      expect(renamed.id, item.partyId);
      expect(renamed.name, 'Brightsure Ins.');
      expect(
        (await service.parties.get(item.partyId))!.name,
        'Brightsure Ins.',
      );
      expect((await service.searchInteractions('ins.')).single.id, item.id);
      expect(await service.searchInteractions('brightsure i'), hasLength(1));
      // Only a change of case on the same party is not a conflict.
      await service.renameParty(item.partyId, 'BRIGHTSURE INS.');
    });

    test('rename to another party\'s Unicode-folded name conflicts', () async {
      final (_, service) = await _open();
      final energie = await _record(service, 'Énergie', 'One');
      final other = await _record(service, 'Other', 'Two');
      await expectLater(
        service.renameParty(other.partyId, 'éNERGIE'),
        throwsA(
          isA<PartyNameConflict>().having(
            (e) => e.existing.id,
            'existing',
            energie.partyId,
          ),
        ),
      );
      expect((await service.parties.get(other.partyId))!.name, 'Other');
    });

    test('merge moves every interaction and removes the source', () async {
      final (_, service) = await _open();
      final typo = await _record(service, 'BrightSure', 'Typo call');
      final real = await _record(service, 'Brightsure Ins.', 'Real call');
      await service.mergeParties(source: typo.partyId, target: real.partyId);
      expect(await service.parties.get(typo.partyId), isNull);
      final history = await service.partyHistory(real.partyId);
      expect(history.map((i) => i.id), containsAll([typo.id, real.id]));
      final moved = history.firstWhere((i) => i.id == typo.id);
      expect(moved.createdAt, typo.createdAt);
      expect(
        (await service.searchInteractions('Typo call')).single.partyId,
        real.partyId,
      );
      await expectLater(
        service.mergeParties(source: real.partyId, target: real.partyId),
        throwsArgumentError,
      );
    });

    test('merge into a missing party changes nothing', () async {
      final (_, service) = await _open();
      final item = await _record(service, 'BrightSure', 'Call');
      await expectLater(
        service.mergeParties(source: item.partyId, target: 'missing'),
        throwsStateError,
      );
      expect((await service.partyHistory(item.partyId)).single.id, item.id);
    });
  });

  group('move interaction (#33)', () {
    test('keeps ID and createdAt, and search shows the new party', () async {
      final (_, service) = await _open();
      final item = await _record(service, 'Wrong Co', 'Misfiled call');
      final target = await _record(service, 'Right Co', 'Existing');
      final moved = await service.updateInteraction(
        UpdateInteractionCommand(
          interaction: item,
          summary: item.summary,
          targetPartyName: 'Right Co',
        ),
      );
      expect(moved.id, item.id);
      expect(moved.createdAt, item.createdAt);
      expect(moved.partyId, target.partyId);
      expect(await service.partyHistory(item.partyId), isEmpty);
      expect(await service.partyHistory(target.partyId), hasLength(2));
      expect(
        (await service.searchInteractions('Misfiled')).single.partyId,
        target.partyId,
      );
    });

    test('moving to a new name creates that party', () async {
      final (_, service) = await _open();
      final item = await _record(service, 'Wrong Co', 'Call');
      final moved = await service.updateInteraction(
        UpdateInteractionCommand(
          interaction: item,
          summary: 'Call',
          targetPartyName: 'Brand New',
        ),
      );
      expect((await service.parties.get(moved.partyId))!.name, 'Brand New');
    });
  });

  group('paged home list (#39)', () {
    test('pages newest first without gaps or repeats, ties by ID', () async {
      final (_, service) = await _open();
      final same = DateTime.utc(2026, 5);
      for (var i = 0; i < 23; i++) {
        await _record(
          service,
          'Party ${i % 4}',
          'Note $i',
          at: i < 6 ? same : DateTime.utc(2026, 1, 1 + i),
        );
      }
      final seen = <String>[];
      RecentCursor? cursor;
      while (true) {
        final page = await service.recentInteractions(limit: 5, after: cursor);
        if (page.isEmpty) break;
        seen.addAll(page.map((e) => e.interaction.id));
        expect(page.every((e) => e.party.name.startsWith('Party ')), isTrue);
        cursor = RecentCursor.after(page.last.interaction);
      }
      expect(seen, hasLength(23));
      expect(seen.toSet(), hasLength(23));
      final all = await service.interactions.all();
      final expected = all.toList()
        ..sort((a, b) {
          final t = b.timestamp.compareTo(a.timestamp);
          return t != 0 ? t : b.id.compareTo(a.id);
        });
      expect(seen, expected.map((i) => i.id).toList());
    });
  });

  group('follow-up time (#34)', () {
    test('persists hasTime and migrates schema 3 as day-only', () async {
      final directory = await Directory.systemTemp.createTemp('crm-v3-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/v3.sqlite';
      var db = await AppDatabase.open(path: path, useFfi: true);
      final party = await LocalPartyRepository(db).findOrCreate('Party');
      for (final timed in [false, true]) {
        await db.saveInteraction(
          Interaction(
            id: '$timed',
            partyId: party.id,
            summary: 'Due',
            timestamp: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
            followUp: FollowUp(dueAt: DateTime.utc(2026, 2), hasTime: timed),
          ),
        );
      }
      expect((await db.getInteraction('true'))!.followUp!.hasTime, isTrue);
      expect((await db.getInteraction('false'))!.followUp!.hasTime, isFalse);
      await db.close();

      // Rebuild as a genuine schema 3 table without the new column.
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute('DROP INDEX interactions_timestamp_id');
      await legacy.execute('DROP INDEX interactions_follow_up');
      await legacy.execute(
        'ALTER TABLE interactions DROP COLUMN follow_up_has_time',
      );
      await legacy.setVersion(3);
      await legacy.close();

      db = await AppDatabase.open(path: path, useFfi: true);
      addTearDown(db.close);
      expect((await db.getInteraction('true'))!.followUp!.hasTime, isFalse);
      expect(await db.debugIndexExists('interactions_timestamp_id'), isTrue);
      expect(await db.debugIndexExists('interactions_follow_up'), isTrue);
    });
  });

  group('export everything (#37)', () {
    test('includes every party and interaction and round-trips', () async {
      final (_, source) = await _open();
      final a = await _record(
        source,
        'Énergie',
        'Ünïcode ✓',
        references: ['R1'],
      );
      await source.updateInteraction(
        UpdateInteractionCommand(
          interaction: a.copyWith(
            followUp: FollowUp(
              dueAt: DateTime.utc(2027, 1, 2, 3),
              hasTime: true,
            ),
          ),
          summary: a.summary,
        ),
      );
      await _record(source, 'Acme', 'Second');
      await source.parties.findOrCreate('No interactions yet');
      final json = (await source.snapshot()).toJson();
      expect(json, contains('"encrypted": false'));

      final decoded = LedgerSnapshot.fromJson(json);
      expect(decoded.parties, hasLength(3));
      expect(decoded.interactions, hasLength(2));

      final (_, target) = await _open();
      await target.importLedger(decoded);
      final reExported = (await target.snapshot()).toJson();
      String strip(String s) =>
          s.replaceAll(RegExp(r'"generatedAt": "[^"]+"'), '');
      expect(strip(reExported), strip(json));
      final back = (await target.getInteraction(a.id))!;
      expect(back.followUp!.hasTime, isTrue);
      expect(back.createdAt, a.createdAt);
      expect((await target.searchInteractions('R1')).single.id, a.id);
    });

    test('import refuses a ledger that already has records', () async {
      final (_, service) = await _open();
      await _record(service, 'Existing', 'Call');
      final snapshot = await service.snapshot();
      await expectLater(
        service.importLedger(snapshot),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            CrmService.ledgerNotEmptyMessage,
          ),
        ),
      );
    });

    test(
      'a failure part-way through import keeps nothing (one transaction)',
      () async {
        final (db, service) = await _open();
        final good = Interaction(
          id: 'ok',
          partyId: 'p',
          summary: 'Imported',
          timestamp: DateTime.utc(2026),
          createdAt: DateTime.utc(2026),
        );
        // Bypass service validation: the second row violates the foreign key
        // after the parties and first interaction were already written.
        await expectLater(
          db.importLedger(
            parties: const [
              Party(id: 'p', name: 'P'),
              Party(id: 'q', name: 'Q'),
            ],
            interactions: [
              good,
              Interaction(
                id: 'orphan',
                partyId: 'missing',
                summary: 'Broken',
                timestamp: DateTime.utc(2026),
                createdAt: DateTime.utc(2026),
              ),
            ],
          ),
          throwsA(anything),
        );
        expect(await service.parties.list(), isEmpty);
        expect(await service.interactions.count(), 0);
        expect(await db.debugCount('interaction_search'), 0);
        // The ledger is still empty, so a corrected import is accepted.
        await db.importLedger(
          parties: const [Party(id: 'p', name: 'P')],
          interactions: [good],
        );
        expect((await service.searchInteractions('Imported')).single.id, 'ok');
      },
    );

    test('rejects other JSON and rolls back a broken import', () async {
      expect(
        () => LedgerSnapshot.fromJson('{"schemaVersion": 1}'),
        throwsFormatException,
      );
      expect(() => LedgerSnapshot.fromJson('not json'), throwsFormatException);
      final (_, service) = await _open();
      final broken = LedgerSnapshot(
        generatedAt: DateTime.utc(2026),
        parties: const [Party(id: 'p', name: 'P')],
        interactions: [
          Interaction(
            id: 'x',
            partyId: 'missing',
            summary: 's',
            timestamp: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
          ),
        ],
      );
      await expectLater(service.importLedger(broken), throwsFormatException);
      expect(await service.parties.list(), isEmpty);
    });
  });
}
