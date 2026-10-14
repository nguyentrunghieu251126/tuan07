import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

class FavoriteDb {
  FavoriteDb._();
  static final FavoriteDb instance = FavoriteDb._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), 'favorite_routes.db'),
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE favorites(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          start_label TEXT,
          end_label TEXT,
          start_lat REAL, start_lng REAL,
          end_lat REAL, end_lng REAL,
          mode TEXT,
          distance_m INTEGER,
          duration_s INTEGER,
          polyline TEXT,
          created_at TEXT
        )
      '''),
    );
    return _db!;
  }

  Future<int> insert(FavoriteRoute r) async {
    final db = await database;
    final map = r.toMap()..remove('id');
    return db.insert('favorites', map);
  }

  Future<List<FavoriteRoute>> getAll() async {
    final db = await database;
    final rows = await db.query('favorites', orderBy: 'id DESC');
    return rows.map(FavoriteRoute.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete('favorites', where: 'id = ?', whereArgs: [id]);
  }
}
