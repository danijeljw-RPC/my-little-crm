import '../../domain/models.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

class LocalInteractionRepository implements InteractionRepository {
  LocalInteractionRepository(this._database);
  final AppDatabase _database;
  @override
  Future<Interaction?> get(InteractionId id) => _database.getInteraction(id);
  @override
  Future<Interaction> save(Interaction value) =>
      _database.saveInteraction(value);
  @override
  Future<void> saveAll(List<Interaction> values) =>
      _database.saveInteractions(values);
  @override
  Future<List<Interaction>> search(String query) => query.trim().isEmpty
      ? Future.value(const [])
      : _database.searchInteractions(query.trim());
  @override
  Future<List<Interaction>> forParty(PartyId partyId) =>
      _database.interactionsForParty(partyId);
  @override
  Future<List<Interaction>> openFollowUps() => _database.openFollowUps();
  @override
  Future<List<InteractionEntry>> recent({
    int limit = 50,
    RecentCursor? after,
  }) => _database.recentInteractions(limit: limit, after: after);
  @override
  Future<int> countForParty(PartyId partyId) =>
      _database.countInteractions(partyId: partyId);
  @override
  Future<int> count() => _database.countInteractions();
  @override
  Future<List<Interaction>> all() => _database.allInteractions();
  @override
  Future<void> delete(InteractionId id) => _database.deleteInteraction(id);
  @override
  Future<void> importAll({
    required List<Party> parties,
    required List<Interaction> interactions,
  }) => _database.importLedger(parties: parties, interactions: interactions);
}
