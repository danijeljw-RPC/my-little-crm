import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

class LocalPartyRepository implements PartyRepository {
  LocalPartyRepository(this._database);
  final AppDatabase _database;
  @override
  Future<Party> findOrCreate(String name) async {
    final normalized = name.trim();
    return _database.findOrCreateParty(
      Party(id: const Uuid().v4(), name: normalized),
    );
  }

  @override
  Future<Party?> get(PartyId id) => _database.partyById(id);
  @override
  Future<List<Party>> list() => _database.allParties();
  @override
  Future<Party> restore(Party party) => _database.restoreParty(party);
  @override
  Future<Party> rename(PartyId id, String name) =>
      _database.renameParty(id, name.trim());
  @override
  Future<void> merge({required PartyId source, required PartyId target}) =>
      _database.mergeParties(source: source, target: target);
  @override
  Future<void> delete(PartyId id) => _database.deleteParty(id);
}
