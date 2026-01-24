// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncChange _$SyncChangeFromJson(Map<String, dynamic> json) => SyncChange(
      id: json['id'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      operation: json['operation'] as String,
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$SyncChangeToJson(SyncChange instance) =>
    <String, dynamic>{
      'id': instance.id,
      'entity_type': instance.entityType,
      'entity_id': instance.entityId,
      'operation': instance.operation,
      'data': instance.data,
      'timestamp': instance.timestamp.toIso8601String(),
      'retry_count': instance.retryCount,
    };

SyncResult _$SyncResultFromJson(Map<String, dynamic> json) => SyncResult(
      success: json['success'] as bool,
      itemsPushed: (json['items_pushed'] as num).toInt(),
      itemsPulled: (json['items_pulled'] as num).toInt(),
      conflicts: (json['conflicts'] as num).toInt(),
      errors:
          (json['errors'] as List<dynamic>).map((e) => e as String).toList(),
      syncTime: DateTime.parse(json['sync_time'] as String),
    );

Map<String, dynamic> _$SyncResultToJson(SyncResult instance) =>
    <String, dynamic>{
      'success': instance.success,
      'items_pushed': instance.itemsPushed,
      'items_pulled': instance.itemsPulled,
      'conflicts': instance.conflicts,
      'errors': instance.errors,
      'sync_time': instance.syncTime.toIso8601String(),
    };
