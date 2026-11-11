import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/domain/models.dart';

void main() {
  test('concurrent first lookups share one party', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = LocalPartyRepository(db);
    final parties = await Future.wait([
      repository.findOrCreate('Énergie'),
      repository.findOrCreate('éNERGIE'),
    ]);
    expect(parties[0].id, parties[1].id);
    expect(await repository.list(), hasLength(1));
  });

  test(
    'concurrent initial saves preserve the first creation timestamp',
    () async {
      final db = await AppDatabase.inMemory();
      addTearDown(db.close);
      final party = await LocalPartyRepository(db).findOrCreate('Party');
      final first = Interaction(
        id: 'same',
        partyId: party.id,
        summary: 'First',
        timestamp: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
      );
      final second = first.copyWith(
        summary: 'Second',
        createdAt: DateTime.utc(2030),
      );
      await Future.wait([
        db.saveInteraction(first),
        db.saveInteraction(second),
      ]);
      expect((await db.getInteraction('same'))!.createdAt, first.createdAt);
    },
  );

  test('sorts UTC timestamps accurately within a millisecond', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final party = await LocalPartyRepository(db).findOrCreate('Party');
    final time = DateTime.utc(2026);
    for (final offset in [0, 1, 100]) {
      final timestamp = time.add(Duration(microseconds: offset));
      await db.saveInteraction(
        Interaction(
          id: '$offset',
          partyId: party.id,
          summary: 'Note',
          timestamp: timestamp,
          createdAt: time,
          followUp: FollowUp(dueAt: timestamp),
        ),
      );
    }
    expect((await db.interactionsForParty(party.id)).map((i) => i.id), [
      '100',
      '1',
      '0',
    ]);
    expect((await db.openFollowUps()).map((i) => i.id), ['0', '1', '100']);
  });

  test(
    'persists optional values and preserves immutable fields on edit',
    () async {
      final database = await AppDatabase.inMemory();
      addTearDown(database.close);
      final parties = LocalPartyRepository(database);
      final interactions = LocalInteractionRepository(database);
      final party = await parties.findOrCreate('BrightSure Insurance');
      final saved = await interactions.save(
        Interaction(
          id: 'interaction-1',
          partyId: party.id,
          summary: 'Called support',
          timestamp: DateTime.utc(2026, 11, 11),
          createdAt: DateTime.utc(2026, 11, 11),
        ),
      );

      expect(saved.contactName, isNull);
      expect(saved.referenceNumbers, isEmpty);

      final edited = await interactions.save(
        saved.copyWith(summary: 'Updated note'),
      );
      final reloaded = await interactions.get(saved.id);

      expect(edited.id, saved.id);
      expect(edited.createdAt, saved.createdAt);
      expect(reloaded!.summary, 'Updated note');
      expect(reloaded.partyId, party.id);
    },
  );
}
