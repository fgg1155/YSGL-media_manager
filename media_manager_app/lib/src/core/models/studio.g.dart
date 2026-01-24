// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Studio _$StudioFromJson(Map<String, dynamic> json) => Studio(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      mediaCount: (json['media_count'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$StudioToJson(Studio instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'logo_url': instance.logoUrl,
      'description': instance.description,
      'media_count': instance.mediaCount,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

Series _$SeriesFromJson(Map<String, dynamic> json) => Series(
      id: json['id'] as String,
      name: json['name'] as String,
      studioId: json['studio_id'] as String?,
      description: json['description'] as String?,
      coverUrl: json['cover_url'] as String?,
      mediaCount: (json['media_count'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$SeriesToJson(Series instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'studio_id': instance.studioId,
      'description': instance.description,
      'cover_url': instance.coverUrl,
      'media_count': instance.mediaCount,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

SeriesWithStudio _$SeriesWithStudioFromJson(Map<String, dynamic> json) =>
    SeriesWithStudio(
      id: json['id'] as String,
      name: json['name'] as String,
      studioId: json['studio_id'] as String?,
      description: json['description'] as String?,
      coverUrl: json['cover_url'] as String?,
      mediaCount: (json['media_count'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      studioName: json['studio_name'] as String?,
    );

Map<String, dynamic> _$SeriesWithStudioToJson(SeriesWithStudio instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'studio_id': instance.studioId,
      'description': instance.description,
      'cover_url': instance.coverUrl,
      'media_count': instance.mediaCount,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'studio_name': instance.studioName,
    };

StudioWithSeries _$StudioWithSeriesFromJson(Map<String, dynamic> json) =>
    StudioWithSeries(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      mediaCount: (json['media_count'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      seriesList: (json['series_list'] as List<dynamic>)
          .map((e) => Series.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$StudioWithSeriesToJson(StudioWithSeries instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'logo_url': instance.logoUrl,
      'description': instance.description,
      'media_count': instance.mediaCount,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'series_list': instance.seriesList,
    };

StudioListResponse _$StudioListResponseFromJson(Map<String, dynamic> json) =>
    StudioListResponse(
      studios: (json['studios'] as List<dynamic>)
          .map((e) => StudioWithSeries.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
    );

Map<String, dynamic> _$StudioListResponseToJson(StudioListResponse instance) =>
    <String, dynamic>{
      'studios': instance.studios,
      'total': instance.total,
    };

SeriesListResponse _$SeriesListResponseFromJson(Map<String, dynamic> json) =>
    SeriesListResponse(
      series: (json['series'] as List<dynamic>)
          .map((e) => SeriesWithStudio.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
    );

Map<String, dynamic> _$SeriesListResponseToJson(SeriesListResponse instance) =>
    <String, dynamic>{
      'series': instance.series,
      'total': instance.total,
    };
