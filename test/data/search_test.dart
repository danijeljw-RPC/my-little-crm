import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/core/clock.dart';

void main() {
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
