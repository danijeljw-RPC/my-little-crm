import '../../domain/models.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

class LocalPartyRepository implements PartyRepository {
  LocalPartyRepository(this._database);
  final AppDatabase _database;
  @override
  Future<Party> findOrCreate(String name) async {
    final normalized = name.trim();
    final existing = await _database.partyByName(normalized);
    return existing ?? _database.insertParty(Party(id: '${normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().microsecondsSinceEpoch}', name: normalized));
  }
  @override
  Future<Party?> get(PartyId id) => _database.partyById(id);
  @override
  Future<List<Party>> list() => _database.allParties();
}
