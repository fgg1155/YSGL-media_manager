import 'package:json_annotation/json_annotation.dart';

part 'sync_models.g.dart';

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
}

/// Sync change for offline queue
@JsonSerializable(fieldRename: FieldRename.snake)
class SyncChange {
  final String id;
  final String entityType; // 'media' or 'actor'
  final String entityId;
  final String operation; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount;

  const SyncChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
  });

  factory SyncChange.fromJson(Map<String, dynamic> json) =>
      _$SyncChangeFromJson(json);

  Map<String, dynamic> toJson() => _$SyncChangeToJson(this);

  SyncChange copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    int? retryCount,
  }) {
    return SyncChange(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

/// Sync result
@JsonSerializable(fieldRename: FieldRename.snake)
class SyncResult {
  final bool success;
  final int itemsPushed;
  final int itemsPulled;
  final int conflicts;
  final List<String> errors;
  final DateTime syncTime;

  const SyncResult({
    required this.success,
    required this.itemsPushed,
    required this.itemsPulled,
    required this.conflicts,
    required this.errors,
    required this.syncTime,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) =>
      _$SyncResultFromJson(json);

  Map<String, dynamic> toJson() => _$SyncResultToJson(this);

  factory SyncResult.empty() {
    return SyncResult(
      success: true,
      itemsPushed: 0,
      itemsPulled: 0,
      conflicts: 0,
      errors: const [],
      syncTime: DateTime.now(),
    );
  }

  factory SyncResult.error(String error) {
    return SyncResult(
      success: false,
      itemsPushed: 0,
      itemsPulled: 0,
      conflicts: 0,
      errors: [error],
      syncTime: DateTime.now(),
    );
  }
}
