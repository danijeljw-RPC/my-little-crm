import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';

void main() {
  test('creates all record details through the service', () async {
    final now = DateTime.utc(2026, 11, 12);
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(now),
    );
    final item = await service.createInteraction(
      CreateInteractionCommand(
        partyName: ' BrightSure ',
        summary: ' Call recorded ',
        timestamp: DateTime.utc(2025),
        method: CommunicationMethod.email,
        contactName: ' Sam ',
        referenceNumbers: [' CASE-1 ', 'CASE-1', ' '],
        commitment: ' Refund ',
        followUpDueAt: DateTime.utc(2027),
      ),
    );
    expect(item.timestamp, DateTime.utc(2025));
    expect(item.createdAt, now);
    expect(item.method, CommunicationMethod.email);
    expect(item.contactName, 'Sam');
    expect(item.referenceNumbers, ['CASE-1']);
    expect(item.commitment, 'Refund');
    expect(item.summary, 'Call recorded');
  });

  test(
    'updates details and clears optionals while preserving identity',
    () async {
      final now = DateTime.utc(2026, 11, 12);
      final service = CrmService(
        parties: MemoryPartyRepository(),
        interactions: MemoryInteractionRepository(),
        clock: FixedClock(now),
      );
      final original = await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure',
          summary: 'Original',
          followUpDueAt: now,
        ),
      );
      final draft = Interaction(
        id: original.id,
        partyId: 'wrong-party',
        summary: ' Updated ',
        timestamp: DateTime.utc(2025),
        createdAt: DateTime.utc(2099),
        method: CommunicationMethod.letter,
      );
      final saved = await service.updateInteraction(
        UpdateInteractionCommand(interaction: draft, summary: draft.summary),
      );
      expect(saved.id, original.id);
      expect(saved.partyId, original.partyId);
      expect(saved.createdAt, now);
      expect(saved.summary, 'Updated');
      expect(saved.timestamp, DateTime.utc(2025));
      expect(saved.method, CommunicationMethod.letter);
      expect(saved.followUp, isNull);
      await expectLater(
        service.updateInteraction(
          UpdateInteractionCommand(interaction: saved, summary: '  '),
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.updateInteraction(
          UpdateInteractionCommand(
            interaction: Interaction(
              id: 'missing',
              partyId: saved.partyId,
              summary: 'Missing',
              timestamp: now,
              createdAt: now,
            ),
            summary: 'Missing',
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'creates an interaction with an open follow-up and completes it',
    () async {
      final fixedNow = DateTime.utc(2026, 11, 11, 10, 42);
      final service = CrmService(
        parties: MemoryPartyRepository(),
        interactions: MemoryInteractionRepository(),
        clock: FixedClock(fixedNow),
      );

      final created = await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure Insurance',
          summary: 'Revised quote promised',
          followUpDueAt: fixedNow.add(const Duration(days: 3)),
        ),
      );

      expect(created.timestamp, fixedNow);
      expect(created.followUp!.status, FollowUpStatus.open);
      await service.completeFollowUp(created.id);
      expect(
        (await service.getInteraction(created.id))!.followUp!.status,
        FollowUpStatus.completed,
      );
    },
  );
}
