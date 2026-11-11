import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/domain/models.dart';

void main() {
  test('stores and reloads an interaction with optional fields absent', () async {
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    final saved = await database.saveInteraction(Interaction(
      id: 'interaction-1', partyId: 'party-1', summary: 'Called support',
      timestamp: DateTime.utc(2026, 11, 11), createdAt: DateTime.utc(2026, 11, 11),
    ));
    expect(saved.contactName, isNull);
    expect((await database.getInteraction(saved.id))!.summary, 'Called support');
  });
}
