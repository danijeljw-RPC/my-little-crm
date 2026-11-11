import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/models.dart';

class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;
  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE interactions (id TEXT PRIMARY KEY, party_id TEXT NOT NULL, summary TEXT NOT NULL, timestamp TEXT NOT NULL, created_at TEXT NOT NULL)');
    return AppDatabase._(db);
  }
  Future<Interaction> saveInteraction(Interaction item) async {
    await _db.insert('interactions', {'id':item.id,'party_id':item.partyId,'summary':item.summary,'timestamp':item.timestamp.toIso8601String(),'created_at':item.createdAt.toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
    return item;
  }
  Future<Interaction?> getInteraction(String id) async {
    final rows=await _db.query('interactions',where:'id = ?',whereArgs:[id]); if(rows.isEmpty)return null; final row=rows.single;
    return Interaction(id:row['id'] as String,partyId:row['party_id'] as String,summary:row['summary'] as String,timestamp:DateTime.parse(row['timestamp'] as String),createdAt:DateTime.parse(row['created_at'] as String));
  }
  Future<void> close()=>_db.close();
}
