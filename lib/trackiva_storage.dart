import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'trackiva_platform_interface.dart';

/// Offline storage for location data
class TrackivaStorage {
  static Database? _database;
  static const String _tableName = 'pending_locations';
  static const int _dbVersion = 1;

  /// Initialize the database
  Future<void> initialize() async {
    if (_database != null) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'trackiva.db');

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy REAL NOT NULL,
            altitude REAL NOT NULL,
            speed REAL NOT NULL,
            bearing REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            is_background INTEGER NOT NULL,
            provider TEXT,
            metadata TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  /// Save location to database
  Future<int> saveLocation(LocationData location, Map<String, dynamic> metadata) async {
    if (_database == null) {
      await initialize();
    }

    return await _database!.insert(_tableName, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'accuracy': location.accuracy,
      'altitude': location.altitude,
      'speed': location.speed,
      'bearing': location.bearing,
      'timestamp': location.timestamp.millisecondsSinceEpoch,
      'is_background': location.isBackground ? 1 : 0,
      'provider': location.provider,
      'metadata': jsonEncode(metadata),
      'synced': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Get all pending (unsynced) locations
  Future<List<Map<String, dynamic>>> getPendingLocations() async {
    if (_database == null) {
      await initialize();
    }

    final results = await _database!.query(_tableName, where: 'synced = ?', whereArgs: [0], orderBy: 'created_at ASC');

    return results.map((row) {
      final location = LocationData(
        latitude: row['latitude'] as double,
        longitude: row['longitude'] as double,
        accuracy: row['accuracy'] as double,
        altitude: row['altitude'] as double,
        speed: row['speed'] as double,
        bearing: row['bearing'] as double,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        isBackground: (row['is_background'] as int) == 1,
        provider: row['provider'] as String?,
      );

      final metadata = jsonDecode(row['metadata'] as String) as Map<String, dynamic>;

      return {'id': row['id'] as int, 'location': location, 'metadata': metadata};
    }).toList();
  }

  /// Mark location as synced
  Future<void> markLocationAsSynced(int id) async {
    if (_database == null) {
      await initialize();
    }

    await _database!.update(_tableName, {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Get count of pending locations
  Future<int> getPendingCount() async {
    if (_database == null) {
      await initialize();
    }

    final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM $_tableName WHERE synced = 0');

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all locations
  Future<void> clearAll() async {
    if (_database == null) {
      await initialize();
    }

    await _database!.delete(_tableName);
  }

  /// Delete synced locations older than specified days
  Future<void> deleteOldSyncedLocations(int daysOld) async {
    if (_database == null) {
      await initialize();
    }

    final cutoffTime = DateTime.now().subtract(Duration(days: daysOld)).millisecondsSinceEpoch;

    await _database!.delete(_tableName, where: 'synced = ? AND created_at < ?', whereArgs: [1, cutoffTime]);
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
