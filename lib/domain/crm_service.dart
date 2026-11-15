import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/clock.dart';
import 'ledger.dart';
import 'models.dart';
import 'models.dart' as models show ledgerNotEmptyMessage;
import 'repositories.dart';

class CrmService {
  CrmService({
    required this.parties,
    required this.interactions,
    required this.clock,
  });

  /// A service over linked in-memory repositories (tests and previews).
  factory CrmService.inMemory({Clock clock = const SystemClock()}) {
    final interactions = MemoryInteractionRepository();
    final parties = MemoryPartyRepository(interactions);
    interactions.parties = parties;
    return CrmService(
      parties: parties,
      interactions: interactions,
      clock: clock,
    );
  }

  final PartyRepository parties;
  final InteractionRepository interactions;
  final Clock clock;

  /// Increments after every successful change, so open screens and panes can
  /// refresh (for example both histories after a move, or after an undo).
  final ValueNotifier<int> revision = ValueNotifier(0);

  void _changed() => revision.value++;

  Future<Interaction> createInteraction(
    CreateInteractionCommand command,
  ) async {
    if (command.partyName.trim().isEmpty || command.summary.trim().isEmpty) {
      throw ArgumentError('Party name and summary are required');
    }
    final party = await parties.findOrCreate(command.partyName.trim());
    final now = clock.now();
    final saved = await interactions.save(
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
            : FollowUp(
                dueAt: command.followUpDueAt!,
                hasTime: command.followUpHasTime,
              ),
      ),
    );
    _changed();
    return saved;
  }

  Future<Interaction> updateInteraction(
    UpdateInteractionCommand command,
  ) async {
    if (command.summary.trim().isEmpty) {
      throw ArgumentError('A summary is required');
    }
    final target = command.targetPartyName?.trim();
    if (target != null && target.isEmpty) {
      throw ArgumentError('A party name is required');
    }
    final original = await interactions.get(command.interaction.id);
    if (original == null) throw StateError('Interaction no longer exists');
    final partyId = target == null
        ? original.partyId
        : (await parties.findOrCreate(target)).id;
    final draft = command.interaction;
    final saved = await interactions.save(
      Interaction(
        id: original.id,
        partyId: partyId,
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
    _changed();
    return saved;
  }

  /// Deletes an interaction and returns it so the caller can offer undo.
  Future<Interaction?> deleteInteraction(InteractionId id) async {
    final item = await interactions.get(id);
    if (item == null) return null;
    await interactions.delete(id);
    _changed();
    return item;
  }

  /// Puts back an interaction removed by [deleteInteraction], unchanged.
  Future<Interaction> restoreInteraction(Interaction item) async {
    if (await parties.get(item.partyId) == null) {
      throw StateError('Party no longer exists');
    }
    final saved = await interactions.save(item);
    _changed();
    return saved;
  }

  Future<Party> renameParty(PartyId id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A party name is required');
    final party = await parties.rename(id, trimmed);
    _changed();
    return party;
  }

  Future<void> mergeParties({
    required PartyId source,
    required PartyId target,
  }) async {
    if (source == target) {
      throw ArgumentError('Cannot merge a party into itself');
    }
    await parties.merge(source: source, target: target);
    _changed();
  }

  Future<void> deleteParty(PartyId id) async {
    await parties.delete(id);
    _changed();
  }

  Future<int> partyInteractionCount(PartyId id) =>
      interactions.countForParty(id);

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
    _changed();
  }

  Future<List<Interaction>> searchInteractions(String query) =>
      interactions.search(query);
  Future<List<Interaction>> partyHistory(PartyId partyId) =>
      interactions.forParty(partyId);
  Future<List<Interaction>> outstandingFollowUps() =>
      interactions.openFollowUps();
  Future<List<InteractionEntry>> recentInteractions({
    int limit = 50,
    RecentCursor? after,
  }) => interactions.recent(limit: limit, after: after);

  /// Number of open follow-ups that are past due at [clock] time.
  Future<int> overdueFollowUpCount() async {
    final now = clock.now();
    return (await outstandingFollowUps())
        .where((i) => i.followUp!.urgency(now) == FollowUpUrgency.overdue)
        .length;
  }

  Future<LedgerSnapshot> snapshot() async => LedgerSnapshot(
    generatedAt: clock.now(),
    parties: await parties.list(),
    interactions: await interactions.all(),
  );

  /// Loads a full-ledger export into an empty database, atomically. Refuses
  /// to merge into existing records.
  Future<void> importLedger(LedgerSnapshot ledger) async {
    final knownParties = {for (final p in ledger.parties) p.id};
    if (ledger.interactions.any((i) => !knownParties.contains(i.partyId))) {
      throw const FormatException('An interaction refers to a missing party');
    }
    await interactions.importAll(
      parties: ledger.parties,
      interactions: ledger.interactions,
    );
    _changed();
  }

  static const ledgerNotEmptyMessage = models.ledgerNotEmptyMessage;
}
