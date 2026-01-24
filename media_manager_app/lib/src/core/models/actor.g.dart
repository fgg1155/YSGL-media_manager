// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'actor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Actor _$ActorFromJson(Map<String, dynamic> json) => Actor(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      photoUrls: _photoUrlsFromJson(json['photo_urls']),
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      biography: json['biography'] as String?,
      birthDate: json['birth_date'] as String?,
      nationality: json['nationality'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      workCount: (json['work_count'] as num?)?.toInt(),
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
      isSynced: json['is_synced'] as bool? ?? false,
      syncVersion: json['sync_version'] as String?,
    );

Map<String, dynamic> _$ActorToJson(Actor instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'avatar_url': instance.avatarUrl,
      'photo_urls': _photoUrlsToJson(instance.photoUrls),
      'poster_url': instance.posterUrl,
      'backdrop_url': instance.backdropUrl,
      'biography': instance.biography,
      'birth_date': instance.birthDate,
      'nationality': instance.nationality,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'work_count': instance.workCount,
      'last_synced_at': instance.lastSyncedAt?.toIso8601String(),
      'is_synced': instance.isSynced,
      'sync_version': instance.syncVersion,
    };

ActorMedia _$ActorMediaFromJson(Map<String, dynamic> json) => ActorMedia(
      id: json['id'] as String,
      actorId: json['actor_id'] as String,
      mediaId: json['media_id'] as String,
      characterName: json['character_name'] as String?,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$ActorMediaToJson(ActorMedia instance) =>
    <String, dynamic>{
      'id': instance.id,
      'actor_id': instance.actorId,
      'media_id': instance.mediaId,
      'character_name': instance.characterName,
      'role': instance.role,
      'created_at': instance.createdAt.toIso8601String(),
    };

ActorFilmography _$ActorFilmographyFromJson(Map<String, dynamic> json) =>
    ActorFilmography(
      mediaId: json['media_id'] as String,
      title: json['title'] as String,
      year: (json['year'] as num?)?.toInt(),
      posterUrl: json['poster_url'] as String?,
      characterName: json['character_name'] as String?,
      role: json['role'] as String,
    );

Map<String, dynamic> _$ActorFilmographyToJson(ActorFilmography instance) =>
    <String, dynamic>{
      'media_id': instance.mediaId,
      'title': instance.title,
      'year': instance.year,
      'poster_url': instance.posterUrl,
      'character_name': instance.characterName,
      'role': instance.role,
    };

ActorDetailResponse _$ActorDetailResponseFromJson(Map<String, dynamic> json) =>
    ActorDetailResponse(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      photoUrl: json['photo_url'] as String?,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      biography: json['biography'] as String?,
      birthDate: json['birth_date'] as String?,
      nationality: json['nationality'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      filmography: (json['filmography'] as List<dynamic>)
          .map((e) => ActorFilmography.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ActorDetailResponseToJson(
        ActorDetailResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'avatar_url': instance.avatarUrl,
      'photo_url': instance.photoUrl,
      'poster_url': instance.posterUrl,
      'backdrop_url': instance.backdropUrl,
      'biography': instance.biography,
      'birth_date': instance.birthDate,
      'nationality': instance.nationality,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'filmography': instance.filmography,
    };

MediaActor _$MediaActorFromJson(Map<String, dynamic> json) => MediaActor(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      photoUrl: json['photo_url'] as String?,
      characterName: json['character_name'] as String?,
      role: json['role'] as String,
    );

Map<String, dynamic> _$MediaActorToJson(MediaActor instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'avatar_url': instance.avatarUrl,
      'photo_url': instance.photoUrl,
      'character_name': instance.characterName,
      'role': instance.role,
    };

ActorListResponse _$ActorListResponseFromJson(Map<String, dynamic> json) =>
    ActorListResponse(
      actors: (json['actors'] as List<dynamic>)
          .map((e) => Actor.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
    );

Map<String, dynamic> _$ActorListResponseToJson(ActorListResponse instance) =>
    <String, dynamic>{
      'actors': instance.actors,
      'total': instance.total,
      'limit': instance.limit,
      'offset': instance.offset,
    };

BatchScrapeActorResponse _$BatchScrapeActorResponseFromJson(
        Map<String, dynamic> json) =>
    BatchScrapeActorResponse(
      successCount: (json['success_count'] as num).toInt(),
      failedCount: (json['failed_count'] as num).toInt(),
      failedActors: (json['failed_actors'] as List<dynamic>)
          .map((e) => FailedActor.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$BatchScrapeActorResponseToJson(
        BatchScrapeActorResponse instance) =>
    <String, dynamic>{
      'success_count': instance.successCount,
      'failed_count': instance.failedCount,
      'failed_actors': instance.failedActors,
    };

FailedActor _$FailedActorFromJson(Map<String, dynamic> json) => FailedActor(
      id: json['id'] as String,
      name: json['name'] as String,
      error: json['error'] as String,
    );

Map<String, dynamic> _$FailedActorToJson(FailedActor instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'error': instance.error,
    };
