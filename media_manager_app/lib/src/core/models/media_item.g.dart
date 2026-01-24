// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaItem _$MediaItemFromJson(Map<String, dynamic> json) => MediaItem(
      id: json['id'] as String,
      code: json['code'] as String?,
      title: json['title'] as String,
      originalTitle: json['original_title'] as String?,
      year: (json['year'] as num?)?.toInt(),
      mediaType: $enumDecode(_$MediaTypeEnumMap, json['media_type']),
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      rating: (json['rating'] as num?)?.toDouble(),
      voteCount: (json['vote_count'] as num?)?.toInt(),
      posterUrl: json['poster_url'] as String?,
      backdropUrl: (json['backdrop_url'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      overview: json['overview'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      releaseDate: json['release_date'] as String?,
      cast: (json['cast'] as List<dynamic>?)
              ?.map((e) => Person.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      crew: (json['crew'] as List<dynamic>?)
              ?.map((e) => Person.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      language: json['language'] as String?,
      country: json['country'] as String?,
      budget: (json['budget'] as num?)?.toInt(),
      revenue: (json['revenue'] as num?)?.toInt(),
      status: json['status'] as String?,
      externalIds:
          ExternalIds.fromJson(json['external_ids'] as Map<String, dynamic>),
      playLinks: (json['play_links'] as List<dynamic>?)
              ?.map((e) => PlayLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      downloadLinks: (json['download_links'] as List<dynamic>?)
              ?.map((e) => DownloadLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      previewUrls: (json['preview_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      previewVideoUrls:
          json['preview_video_urls'] as List<dynamic>? ?? const [],
      coverVideoUrl: json['cover_video_url'] as String?,
      studio: json['studio'] as String?,
      series: json['series'] as String?,
      localFilePath: json['local_file_path'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
      isSynced: json['is_synced'] as bool? ?? false,
      syncVersion: json['sync_version'] as String?,
    );

Map<String, dynamic> _$MediaItemToJson(MediaItem instance) => <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'title': instance.title,
      'original_title': instance.originalTitle,
      'year': instance.year,
      'media_type': _$MediaTypeEnumMap[instance.mediaType]!,
      'genres': instance.genres,
      'rating': instance.rating,
      'vote_count': instance.voteCount,
      'poster_url': instance.posterUrl,
      'backdrop_url': instance.backdropUrl,
      'overview': instance.overview,
      'runtime': instance.runtime,
      'release_date': instance.releaseDate,
      'cast': instance.cast,
      'crew': instance.crew,
      'language': instance.language,
      'country': instance.country,
      'budget': instance.budget,
      'revenue': instance.revenue,
      'status': instance.status,
      'external_ids': instance.externalIds,
      'play_links': instance.playLinks,
      'download_links': instance.downloadLinks,
      'preview_urls': instance.previewUrls,
      'preview_video_urls': instance.previewVideoUrls,
      'cover_video_url': instance.coverVideoUrl,
      'studio': instance.studio,
      'series': instance.series,
      'local_file_path': instance.localFilePath,
      'file_size': instance.fileSize,
      'files': instance.files,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'last_synced_at': instance.lastSyncedAt?.toIso8601String(),
      'is_synced': instance.isSynced,
      'sync_version': instance.syncVersion,
    };

const _$MediaTypeEnumMap = {
  MediaType.movie: 'Movie',
  MediaType.scene: 'Scene',
  MediaType.documentary: 'Documentary',
  MediaType.anime: 'Anime',
  MediaType.censored: 'Censored',
  MediaType.uncensored: 'Uncensored',
};

Person _$PersonFromJson(Map<String, dynamic> json) => Person(
      name: json['name'] as String,
      role: json['role'] as String,
      character: json['character'] as String?,
    );

Map<String, dynamic> _$PersonToJson(Person instance) => <String, dynamic>{
      'name': instance.name,
      'role': instance.role,
      'character': instance.character,
    };

ExternalIds _$ExternalIdsFromJson(Map<String, dynamic> json) => ExternalIds(
      tmdbId: (json['tmdb_id'] as num?)?.toInt(),
      imdbId: json['imdb_id'] as String?,
      omdbId: json['omdb_id'] as String?,
    );

Map<String, dynamic> _$ExternalIdsToJson(ExternalIds instance) =>
    <String, dynamic>{
      'tmdb_id': instance.tmdbId,
      'imdb_id': instance.imdbId,
      'omdb_id': instance.omdbId,
    };

PlayLink _$PlayLinkFromJson(Map<String, dynamic> json) => PlayLink(
      name: json['name'] as String,
      url: json['url'] as String,
      quality: json['quality'] as String?,
    );

Map<String, dynamic> _$PlayLinkToJson(PlayLink instance) => <String, dynamic>{
      'name': instance.name,
      'url': instance.url,
      'quality': instance.quality,
    };

DownloadLink _$DownloadLinkFromJson(Map<String, dynamic> json) => DownloadLink(
      name: json['name'] as String,
      url: json['url'] as String,
      linkType: $enumDecode(_$DownloadLinkTypeEnumMap, json['link_type']),
      size: json['size'] as String?,
      password: json['password'] as String?,
    );

Map<String, dynamic> _$DownloadLinkToJson(DownloadLink instance) =>
    <String, dynamic>{
      'name': instance.name,
      'url': instance.url,
      'link_type': _$DownloadLinkTypeEnumMap[instance.linkType]!,
      'size': instance.size,
      'password': instance.password,
    };

const _$DownloadLinkTypeEnumMap = {
  DownloadLinkType.magnet: 'magnet',
  DownloadLinkType.ed2k: 'ed2k',
  DownloadLinkType.http: 'http',
  DownloadLinkType.ftp: 'ftp',
  DownloadLinkType.torrent: 'torrent',
  DownloadLinkType.pan: 'pan',
  DownloadLinkType.other: 'other',
};
