import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';

void main() {
  test('creates an interaction with an open follow-up and completes it', () async {
    final fixedNow = DateTime.utc(2026, 11, 11, 10, 42);
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(fixedNow),
    );

    final created = await service.createInteraction(CreateInteractionCommand(
      partyName: 'BrightSure Insurance',
      summary: 'Revised quote promised',
      followUpDueAt: fixedNow.add(const Duration(days: 3)),
    ));

    expect(created.timestamp, fixedNow);
    expect(created.followUp!.status, FollowUpStatus.open);
    await service.completeFollowUp(created.id);
    expect((await service.getInteraction(created.id))!.followUp!.status,
        FollowUpStatus.completed);
  });
}
