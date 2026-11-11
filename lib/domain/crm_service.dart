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
        timestamp: command.timestamp ?? now,
        method: command.method,
        contactName: _optional(command.contactName),
        referenceNumbers: _references(command.referenceNumbers),
        commitment: _optional(command.commitment),
        createdAt: now,
        followUp: command.followUpDueAt == null
            ? null
            : FollowUp(dueAt: command.followUpDueAt!),
      ),
    );
  }

  Future<Interaction> updateInteraction(
    UpdateInteractionCommand command,
  ) async {
    if (command.summary.trim().isEmpty) {
      throw ArgumentError('A summary is required');
    }
    final original = await interactions.get(command.interaction.id);
    if (original == null) throw StateError('Interaction no longer exists');
    final draft = command.interaction;
    return interactions.save(
      Interaction(
        id: original.id,
        partyId: original.partyId,
        createdAt: original.createdAt,
        timestamp: draft.timestamp,
        summary: command.summary.trim(),
        method: draft.method,
        contactName: _optional(draft.contactName),
        referenceNumbers: _references(draft.referenceNumbers),
        commitment: _optional(draft.commitment),
        followUp: draft.followUp,
      ),
    );
  }

  static String? _optional(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static List<String> _references(List<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);

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
