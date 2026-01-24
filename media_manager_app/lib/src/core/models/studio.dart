import 'package:json_annotation/json_annotation.dart';

part 'studio.g.dart';

/// 制作商实体
@JsonSerializable(fieldRename: FieldRename.snake)
class Studio {
  final String id;
  final String name;
  final String? logoUrl;
  final String? description;
  final int mediaCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Studio({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
    required this.mediaCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Studio.fromJson(Map<String, dynamic> json) => _$StudioFromJson(json);
  Map<String, dynamic> toJson() => _$StudioToJson(this);

  Studio copyWith({
    String? id,
    String? name,
    String? logoUrl,
    String? description,
    int? mediaCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Studio(
      id: id ?? this.id,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      description: description ?? this.description,
      mediaCount: mediaCount ?? this.mediaCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 系列实体
@JsonSerializable(fieldRename: FieldRename.snake)
class Series {
  final String id;
  final String name;
  final String? studioId;
  final String? description;
  final String? coverUrl;
  final int mediaCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Series({
    required this.id,
    required this.name,
    this.studioId,
    this.description,
    this.coverUrl,
    required this.mediaCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Series.fromJson(Map<String, dynamic> json) => _$SeriesFromJson(json);
  Map<String, dynamic> toJson() => _$SeriesToJson(this);

  Series copyWith({
    String? id,
    String? name,
    String? studioId,
    String? description,
    String? coverUrl,
    int? mediaCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Series(
      id: id ?? this.id,
      name: name ?? this.name,
      studioId: studioId ?? this.studioId,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      mediaCount: mediaCount ?? this.mediaCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 带制作商信息的系列
@JsonSerializable(fieldRename: FieldRename.snake)
class SeriesWithStudio {
  final String id;
  final String name;
  final String? studioId;
  final String? description;
  final String? coverUrl;
  final int mediaCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? studioName;

  const SeriesWithStudio({
    required this.id,
    required this.name,
    this.studioId,
    this.description,
    this.coverUrl,
    required this.mediaCount,
    required this.createdAt,
    required this.updatedAt,
    this.studioName,
  });

  factory SeriesWithStudio.fromJson(Map<String, dynamic> json) =>
      _$SeriesWithStudioFromJson(json);
  Map<String, dynamic> toJson() => _$SeriesWithStudioToJson(this);

  Series toSeries() => Series(
        id: id,
        name: name,
        studioId: studioId,
        description: description,
        coverUrl: coverUrl,
        mediaCount: mediaCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// 带系列列表的制作商
@JsonSerializable(fieldRename: FieldRename.snake)
class StudioWithSeries {
  final String id;
  final String name;
  final String? logoUrl;
  final String? description;
  final int mediaCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Series> seriesList;

  const StudioWithSeries({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
    required this.mediaCount,
    required this.createdAt,
    required this.updatedAt,
    required this.seriesList,
  });

  factory StudioWithSeries.fromJson(Map<String, dynamic> json) =>
      _$StudioWithSeriesFromJson(json);
  Map<String, dynamic> toJson() => _$StudioWithSeriesToJson(this);

  Studio toStudio() => Studio(
        id: id,
        name: name,
        logoUrl: logoUrl,
        description: description,
        mediaCount: mediaCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// 制作商列表响应
@JsonSerializable(fieldRename: FieldRename.snake)
class StudioListResponse {
  final List<StudioWithSeries> studios;
  final int total;

  const StudioListResponse({
    required this.studios,
    required this.total,
  });

  factory StudioListResponse.fromJson(Map<String, dynamic> json) =>
      _$StudioListResponseFromJson(json);
  Map<String, dynamic> toJson() => _$StudioListResponseToJson(this);
}

/// 系列列表响应
@JsonSerializable(fieldRename: FieldRename.snake)
class SeriesListResponse {
  final List<SeriesWithStudio> series;
  final int total;

  const SeriesListResponse({
    required this.series,
    required this.total,
  });

  factory SeriesListResponse.fromJson(Map<String, dynamic> json) =>
      _$SeriesListResponseFromJson(json);
  Map<String, dynamic> toJson() => _$SeriesListResponseToJson(this);
}

// ============ Request DTOs ============

/// 创建制作商请求
class CreateStudioRequest {
  final String name;
  final String? logoUrl;
  final String? description;

  const CreateStudioRequest({
    required this.name,
    this.logoUrl,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (logoUrl != null) 'logo_url': logoUrl,
        if (description != null) 'description': description,
      };
}

/// 更新制作商请求
class UpdateStudioRequest {
  final String? name;
  final String? logoUrl;
  final String? description;

  const UpdateStudioRequest({
    this.name,
    this.logoUrl,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (logoUrl != null) 'logo_url': logoUrl,
        if (description != null) 'description': description,
      };
}

/// 创建系列请求
class CreateSeriesRequest {
  final String name;
  final String? studioId;
  final String? studioName;
  final String? description;
  final String? coverUrl;

  const CreateSeriesRequest({
    required this.name,
    this.studioId,
    this.studioName,
    this.description,
    this.coverUrl,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (studioId != null) 'studio_id': studioId,
        if (studioName != null) 'studio_name': studioName,
        if (description != null) 'description': description,
        if (coverUrl != null) 'cover_url': coverUrl,
      };
}

/// 更新系列请求
class UpdateSeriesRequest {
  final String? name;
  final String? studioId;
  final String? description;
  final String? coverUrl;

  const UpdateSeriesRequest({
    this.name,
    this.studioId,
    this.description,
    this.coverUrl,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (studioId != null) 'studio_id': studioId,
        if (description != null) 'description': description,
        if (coverUrl != null) 'cover_url': coverUrl,
      };
}
