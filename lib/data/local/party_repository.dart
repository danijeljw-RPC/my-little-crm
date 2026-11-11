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
}
