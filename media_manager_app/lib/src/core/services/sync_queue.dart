import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/sync_models.dart';
import '../database/local_database.dart';

/// Manages offline changes for later synchronization
class SyncQueue {
  final LocalDatabase _localDb;
  final _uuid = const Uuid();

  SyncQueue({required LocalDatabase localDb}) : _localDb = localDb;

  /// Enqueue a sync change
  Future<void> enqueue(SyncChange change) async {
    final db = await _localDb.database;
    
    // Create sync_queue table if it doesn't exist
    await _ensureTableExists(db);
    
    await db.insert(
      'sync_queue',
      {
        'id': change.id,
        'entity_type': change.entityType,
        'entity_id': change.entityId,
        'operation': change.operation,
        'data': _encodeData(change.data),
        'timestamp': change.timestamp.toIso8601String(),
        'retry_count': change.retryCount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all pending changes
  Future<List<SyncChange>> getAll() async {
    final db = await _localDb.database;
    
    // Create sync_queue table if it doesn't exist
    await _ensureTableExists(db);
    
    final results = await db.query(
      'sync_queue',
      orderBy: 'timestamp ASC',
    );
    
    return results.map((map) => SyncChange(
      id: map['id'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      operation: map['operation'] as String,
      data: _decodeData(map['data'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
      retryCount: map['retry_count'] as int,
    )).toList();
  }

  /// Remove a change from the queue
  Future<void> remove(String changeId) async {
    final db = await _localDb.database;
    await db.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [changeId],
    );
  }

  /// Clear all pending changes
  Future<void> clear() async {
    final db = await _localDb.database;
    await db.delete('sync_queue');
  }

  /// Get count of pending changes
  Future<int> count() async {
    final db = await _localDb.database;
    
    // Create sync_queue table if it doesn't exist
    await _ensureTableExists(db);
    
    final result = await db.query(
      'sync_queue',
      columns: ['COUNT(*) as count'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Create a new sync change
  SyncChange createChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> data,
  }) {
    return SyncChange(
      id: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      data: data,
      timestamp: DateTime.now(),
      retryCount: 0,
    );
  }

  /// Ensure sync_queue table exists
  Future<void> _ensureTableExists(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0
      )
    ''');
    
    // Create index if it doesn't exist
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_timestamp 
      ON sync_queue(timestamp)
    ''');
  }

  /// Encode data to JSON string
  String _encodeData(Map<String, dynamic> data) {
    // Simple JSON encoding - in production, use json.encode
    final buffer = StringBuffer('{');
    var first = true;
    data.forEach((key, value) {
      if (!first) buffer.write(',');
      buffer.write('"$key":');
      if (value is String) {
        buffer.write('"${value.replaceAll('"', '\\"')}"');
      } else if (value is num || value is bool) {
        buffer.write(value);
      } else if (value == null) {
        buffer.write('null');
      } else {
        buffer.write('"$value"');
      }
      first = false;
    });
    buffer.write('}');
    return buffer.toString();
  }

  /// Decode JSON string to data
  Map<String, dynamic> _decodeData(String jsonStr) {
    // Simple JSON decoding - in production, use json.decode
    final data = <String, dynamic>{};
    if (jsonStr.isEmpty || jsonStr == '{}') return data;
    
    // Remove braces
    final content = jsonStr.substring(1, jsonStr.length - 1);
    if (content.isEmpty) return data;
    
    // Split by comma (simple parsing, doesn't handle nested objects)
    final pairs = content.split(',');
    for (final pair in pairs) {
      final colonIndex = pair.indexOf(':');
      if (colonIndex == -1) continue;
      
      var key = pair.substring(0, colonIndex).trim();
      var value = pair.substring(colonIndex + 1).trim();
      
      // Remove quotes from key
      if (key.startsWith('"') && key.endsWith('"')) {
        key = key.substring(1, key.length - 1);
      }
      
      // Parse value
      if (value == 'null') {
        data[key] = null;
      } else if (value == 'true') {
        data[key] = true;
      } else if (value == 'false') {
        data[key] = false;
      } else if (value.startsWith('"') && value.endsWith('"')) {
        data[key] = value.substring(1, value.length - 1).replaceAll('\\"', '"');
      } else {
        // Try to parse as number
        final numValue = num.tryParse(value);
        data[key] = numValue ?? value;
      }
    }
    
    return data;
  }
}
