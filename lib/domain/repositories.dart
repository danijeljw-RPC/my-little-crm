import 'models.dart';

abstract interface class PartyRepository {
  Future<Party> findOrCreate(String name);
  Future<Party?> get(PartyId id);
  Future<List<Party>> list();

  /// Inserts a party with a known ID (used by ledger import).
  Future<Party> restore(Party party);

  /// Renames a party, keeping its ID. Throws [PartyNameConflict] when another
  /// party already uses the (Unicode-folded) name.
  Future<Party> rename(PartyId id, String name);

  /// Moves every interaction of [source] to [target] and removes [source],
  /// atomically.
  Future<void> merge({required PartyId source, required PartyId target});

  /// Removes a party and all of its interactions.
  Future<void> delete(PartyId id);
}

abstract interface class InteractionRepository {
  Future<Interaction> save(Interaction value);

  /// Saves every item atomically where the store supports transactions.
  Future<void> saveAll(List<Interaction> values);
  Future<Interaction?> get(InteractionId id);
  Future<List<Interaction>> search(String query);
  Future<List<Interaction>> forParty(PartyId partyId);
  Future<List<Interaction>> openFollowUps();

  /// Newest-first page of interactions joined with their party.
  Future<List<InteractionEntry>> recent({int limit = 50, RecentCursor? after});
  Future<int> countForParty(PartyId partyId);
  Future<int> count();

  /// Every interaction, oldest first (used by full-ledger export).
  Future<List<Interaction>> all();
  Future<void> delete(InteractionId id);
}

class MemoryPartyRepository implements PartyRepository {
  /// Link [interactions] so that [merge] and [delete] cascade like SQLite.
  MemoryPartyRepository([this._interactions]);
  final MemoryInteractionRepository? _interactions;
  final Map<PartyId, Party> _items = {};
  @override
  Future<Party> findOrCreate(String name) async {
    final found = _items.values.where((p) => p.name == name).firstOrNull;
    return found ?? (_items[name] = Party(id: name, name: name));
  }

  @override
  Future<Party?> get(PartyId id) async => _items[id];
  @override
  Future<List<Party>> list() async =>
      _items.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Party> restore(Party party) async => _items[party.id] = party;

  @override
  Future<Party> rename(PartyId id, String name) async {
    final current = _items[id] ?? (throw StateError('Party no longer exists'));
    final clash = _items.values
        .where((p) => p.id != id && p.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (clash != null) throw PartyNameConflict(clash);
    return _items[id] = Party(id: current.id, name: name);
  }

  @override
  Future<void> merge({required PartyId source, required PartyId target}) async {
    if (!_items.containsKey(target)) throw StateError('Party no longer exists');
    _interactions?._reassign(source, target);
    _items.remove(source);
  }

  @override
  Future<void> delete(PartyId id) async {
    _interactions?._removeParty(id);
    _items.remove(id);
  }
}

class MemoryInteractionRepository implements InteractionRepository {
  MemoryInteractionRepository([this.parties]);

  /// Optional party lookup so [recent] can return names.
  PartyRepository? parties;
  final Map<InteractionId, Interaction> _items = {};
  @override
  Future<Interaction?> get(InteractionId id) async => _items[id];
  @override
  Future<Interaction> save(Interaction value) async => _items[value.id] = value;
  @override
  Future<void> saveAll(List<Interaction> values) async {
    for (final value in values) {
      _items[value.id] = value;
    }
  }

  @override
  Future<List<Interaction>> search(String query) async => _items.values
      .where((i) => i.summary.toLowerCase().contains(query.toLowerCase()))
      .toList();
  @override
  Future<List<Interaction>> forParty(PartyId partyId) async =>
      _items.values.where((item) => item.partyId == partyId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  @override
  Future<List<Interaction>> openFollowUps() async =>
      _items.values
          .where((item) => item.followUp?.status == FollowUpStatus.open)
          .toList()
        ..sort((a, b) => a.followUp!.dueAt.compareTo(b.followUp!.dueAt));

  @override
  Future<List<InteractionEntry>> recent({
    int limit = 50,
    RecentCursor? after,
  }) async {
    final sorted = _items.values.toList()..sort(_newestFirst);
    final page = sorted
        .where(
          (i) =>
              after == null ||
              i.timestamp.isBefore(after.timestamp) ||
              (i.timestamp == after.timestamp && i.id.compareTo(after.id) < 0),
        )
        .take(limit);
    return [
      for (final item in page)
        InteractionEntry(
          party:
              await parties?.get(item.partyId) ??
              Party(id: item.partyId, name: item.partyId),
          interaction: item,
        ),
    ];
  }

  static int _newestFirst(Interaction a, Interaction b) {
    final byTime = b.timestamp.compareTo(a.timestamp);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  @override
  Future<int> countForParty(PartyId partyId) async =>
      _items.values.where((i) => i.partyId == partyId).length;
  @override
  Future<int> count() async => _items.length;
  @override
  Future<List<Interaction>> all() async =>
      _items.values.toList()..sort((a, b) => -_newestFirst(a, b));
  @override
  Future<void> delete(InteractionId id) async => _items.remove(id);

  void _reassign(PartyId source, PartyId target) {
    for (final item in _items.values.toList()) {
      if (item.partyId == source) {
        _items[item.id] = item.copyWith(partyId: target);
      }
    }
  }

  void _removeParty(PartyId id) =>
      _items.removeWhere((_, item) => item.partyId == id);
}
