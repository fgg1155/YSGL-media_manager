// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Collection _$CollectionFromJson(Map<String, dynamic> json) => Collection(
      id: json['id'] as String,
      mediaId: json['media_id'] as String,
      userTags: (json['user_tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      personalRating: (json['personal_rating'] as num?)?.toDouble(),
      watchStatus: $enumDecode(_$WatchStatusEnumMap, json['watch_status']),
      watchProgress: (json['watch_progress'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      addedAt: DateTime.parse(json['added_at'] as String),
      lastWatched: json['last_watched'] == null
          ? null
          : DateTime.parse(json['last_watched'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
    );

Map<String, dynamic> _$CollectionToJson(Collection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'media_id': instance.mediaId,
      'user_tags': instance.userTags,
      'personal_rating': instance.personalRating,
      'watch_status': _$WatchStatusEnumMap[instance.watchStatus]!,
      'watch_progress': instance.watchProgress,
      'notes': instance.notes,
      'is_favorite': instance.isFavorite,
      'added_at': instance.addedAt.toIso8601String(),
      'last_watched': instance.lastWatched?.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
    };

const _$WatchStatusEnumMap = {
  WatchStatus.wantToWatch: 'WantToWatch',
  WatchStatus.watching: 'Watching',
  WatchStatus.completed: 'Completed',
  WatchStatus.onHold: 'OnHold',
  WatchStatus.dropped: 'Dropped',
};
