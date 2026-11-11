import '../core/clock.dart';
import 'models.dart';
import 'repositories.dart';

import 'package:uuid/uuid.dart';

class CrmService {
  const CrmService({
    required this.parties,
    required this.interactions,
    required this.clock,
  });
  final PartyRepository parties;
  final InteractionRepository interactions;
  final Clock clock;
  Future<Interaction> createInteraction(
    CreateInteractionCommand command,
  ) async {
    if (command.partyName.trim().isEmpty || command.summary.trim().isEmpty) {
      throw ArgumentError('Party name and summary are required');
    }
    final party = await parties.findOrCreate(command.partyName.trim());
    final now = clock.now();
    return interactions.save(
      Interaction(
        id: const Uuid().v4(),
        partyId: party.id,
        summary: command.summary.trim(),
        timestamp: now,
        createdAt: now,
        followUp: command.followUpDueAt == null
            ? null
            : FollowUp(dueAt: command.followUpDueAt!),
      ),
    );
  }

  Future<Interaction?> getInteraction(InteractionId id) => interactions.get(id);
  Future<void> completeFollowUp(InteractionId id) async {
    final item = await interactions.get(id);
    if (item?.followUp == null) return;
    await interactions.save(
      item!.copyWith(followUp: item.followUp!.complete()),
    );
  }

  Future<List<Interaction>> searchInteractions(String query) =>
      interactions.search(query);
  Future<List<Interaction>> partyHistory(PartyId partyId) =>
      interactions.forParty(partyId);
  Future<List<Interaction>> outstandingFollowUps() =>
      interactions.openFollowUps();
}
