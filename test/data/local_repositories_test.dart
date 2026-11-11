import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/domain/models.dart';

void main() {
  test('persists optional values and preserves immutable fields on edit', () async {
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    final parties = LocalPartyRepository(database);
    final interactions = LocalInteractionRepository(database);
    final party = await parties.findOrCreate('BrightSure Insurance');
    final saved = await interactions.save(Interaction(
      id: 'interaction-1', partyId: party.id, summary: 'Called support',
      timestamp: DateTime.utc(2026, 11, 11), createdAt: DateTime.utc(2026, 11, 11),
    ));

    expect(saved.contactName, isNull);
    expect(saved.referenceNumbers, isEmpty);

    final edited = await interactions.save(saved.copyWith(summary: 'Updated note'));
    final reloaded = await interactions.get(saved.id);

    expect(edited.id, saved.id);
    expect(edited.createdAt, saved.createdAt);
    expect(reloaded!.summary, 'Updated note');
    expect(reloaded.partyId, party.id);
  });
}
