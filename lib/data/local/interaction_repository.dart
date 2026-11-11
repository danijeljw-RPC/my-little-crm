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
  Future<List<Interaction>> search(String query) => query.trim().isEmpty
      ? Future.value(const [])
      : _database.searchInteractions(query.trim());
  @override
  Future<List<Interaction>> forParty(PartyId partyId) =>
      _database.interactionsForParty(partyId);
  @override
  Future<List<Interaction>> openFollowUps() => _database.openFollowUps();
}
