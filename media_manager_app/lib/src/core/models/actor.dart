import 'package:json_annotation/json_annotation.dart';

part 'actor.g.dart';

// 辅助函数：从 JSON 解析 photo_urls（支持逗号分隔的字符串或数组）
List<String>? _photoUrlsFromJson(dynamic json) {
  if (json == null) return null;
  if (json is List) {
    return json.map((e) => e.toString()).toList();
  }
  if (json is String) {
    return json.split(',').map((url) => url.trim()).where((url) => url.isNotEmpty).toList();
  }
  return null;
}

// 辅助函数：将 photo_urls 转换为 JSON（转换为逗号分隔的字符串）
String? _photoUrlsToJson(List<String>? photoUrls) {
  if (photoUrls == null || photoUrls.isEmpty) return null;
  return photoUrls.join(',');
}

/// 演员实体
@JsonSerializable(fieldRename: FieldRename.snake)
class Actor {
  final String id;
  final String name;
  final String? avatarUrl;    // 演员头像（圆形小头像，用于媒体详情页演员列表）
  @JsonKey(fromJson: _photoUrlsFromJson, toJson: _photoUrlsToJson)
  final List<String>? photoUrls;     // 演员写真/照片（多图，用于演员详情页相册展示）
  final String? posterUrl;    // 演员封面（竖版海报图，用于演员列表/卡片显示）
  final String? backdropUrl;  // 背景图（横版大图，用于演员详情页背景）
  final String? biography;
  final String? birthDate;
  final String? nationality;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? workCount; // 可选，列表响应中包含
  
  // Sync fields
  final DateTime? lastSyncedAt;
  final bool isSynced;
  final String? syncVersion;

  const Actor({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.photoUrls,
    this.posterUrl,
    this.backdropUrl,
    this.biography,
    this.birthDate,
    this.nationality,
    required this.createdAt,
    required this.updatedAt,
    this.workCount,
    this.lastSyncedAt,
    this.isSynced = false,
    this.syncVersion,
  });

  factory Actor.fromJson(Map<String, dynamic> json) {
    // 处理后端返回的 photo_url 字段（逗号分隔的字符串）
    if (json['photo_url'] is String && json['photo_url'] != null) {
      final photoUrlString = json['photo_url'] as String;
      json['photo_urls'] = photoUrlString.split(',').map((url) => url.trim()).where((url) => url.isNotEmpty).toList();
    }
    return _$ActorFromJson(json);
  }
  Map<String, dynamic> toJson() => _$ActorToJson(this);

  Actor copyWith({
    String? id,
    String? name,
    Object? avatarUrl = const _Undefined(),
    Object? photoUrls = const _Undefined(),
    Object? posterUrl = const _Undefined(),
    Object? backdropUrl = const _Undefined(),
    Object? biography = const _Undefined(),
    Object? birthDate = const _Undefined(),
    Object? nationality = const _Undefined(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? workCount = const _Undefined(),
    DateTime? lastSyncedAt,
    bool? isSynced,
    String? syncVersion,
  }) {
    return Actor(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl is _Undefined ? this.avatarUrl : avatarUrl as String?,
      photoUrls: photoUrls is _Undefined ? this.photoUrls : photoUrls as List<String>?,
      posterUrl: posterUrl is _Undefined ? this.posterUrl : posterUrl as String?,
      backdropUrl: backdropUrl is _Undefined ? this.backdropUrl : backdropUrl as String?,
      biography: biography is _Undefined ? this.biography : biography as String?,
      birthDate: birthDate is _Undefined ? this.birthDate : birthDate as String?,
      nationality: nationality is _Undefined ? this.nationality : nationality as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      workCount: workCount is _Undefined ? this.workCount : workCount as int?,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isSynced: isSynced ?? this.isSynced,
      syncVersion: syncVersion ?? this.syncVersion,
    );
  }
}

// 用于区分"未传值"和"传入 null"的辅助类
class _Undefined {
  const _Undefined();
}

/// 演员-媒体关联
@JsonSerializable(fieldRename: FieldRename.snake)
class ActorMedia {
  final String id;
  final String actorId;
  final String mediaId;
  final String? characterName;
  final String role;
  final DateTime createdAt;

  const ActorMedia({
    required this.id,
    required this.actorId,
    required this.mediaId,
    this.characterName,
    required this.role,
    required this.createdAt,
  });

  factory ActorMedia.fromJson(Map<String, dynamic> json) =>
      _$ActorMediaFromJson(json);
  Map<String, dynamic> toJson() => _$ActorMediaToJson(this);
}

/// 演员作品信息（用于演员详情页的作品列表）
@JsonSerializable(fieldRename: FieldRename.snake)
class ActorFilmography {
  final String mediaId;
  final String title;
  final int? year;
  final String? posterUrl;
  final String? characterName;
  final String role;

  const ActorFilmography({
    required this.mediaId,
    required this.title,
    this.year,
    this.posterUrl,
    this.characterName,
    required this.role,
  });

  factory ActorFilmography.fromJson(Map<String, dynamic> json) =>
      _$ActorFilmographyFromJson(json);
  Map<String, dynamic> toJson() => _$ActorFilmographyToJson(this);
}

/// 演员详情响应（包含作品列表）
@JsonSerializable(fieldRename: FieldRename.snake)
class ActorDetailResponse {
  final String id;
  final String name;
  final String? avatarUrl;    // 演员头像
  final String? photoUrl;     // 演员写真（逗号分隔的字符串）
  final String? posterUrl;    // 演员封面
  final String? backdropUrl;
  final String? biography;
  final String? birthDate;
  final String? nationality;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ActorFilmography> filmography;

  const ActorDetailResponse({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.photoUrl,
    this.posterUrl,
    this.backdropUrl,
    this.biography,
    this.birthDate,
    this.nationality,
    required this.createdAt,
    required this.updatedAt,
    required this.filmography,
  });

  factory ActorDetailResponse.fromJson(Map<String, dynamic> json) =>
      _$ActorDetailResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ActorDetailResponseToJson(this);

  Actor toActor() {
    // 解析 photoUrl（逗号分隔的字符串）为列表
    List<String>? photoUrls;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      photoUrls = photoUrl!.split(',').map((url) => url.trim()).where((url) => url.isNotEmpty).toList();
    }
    
    return Actor(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      photoUrls: photoUrls,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      biography: biography,
      birthDate: birthDate,
      nationality: nationality,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// 媒体中的演员信息（用于媒体详情页）
@JsonSerializable(fieldRename: FieldRename.snake)
class MediaActor {
  final String id;
  final String name;
  final String? avatarUrl;      // 演员头像（圆形小头像，用于媒体详情页演员列表）
  final String? photoUrl;       // 演员写真/照片（备用）
  final String? characterName;
  final String role;

  const MediaActor({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.photoUrl,
    this.characterName,
    required this.role,
  });

  factory MediaActor.fromJson(Map<String, dynamic> json) =>
      _$MediaActorFromJson(json);
  Map<String, dynamic> toJson() => _$MediaActorToJson(this);
}

/// 演员列表响应
@JsonSerializable(fieldRename: FieldRename.snake)
class ActorListResponse {
  final List<Actor> actors;
  final int total;
  final int limit;
  final int offset;

  const ActorListResponse({
    required this.actors,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory ActorListResponse.fromJson(Map<String, dynamic> json) =>
      _$ActorListResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ActorListResponseToJson(this);
}

/// 创建演员请求
class CreateActorRequest {
  final String? id;  // 客户端提供的 UUID（可选）
  final String name;
  final String? avatarUrl;    // 演员头像
  final String? photoUrl;     // 演员写真（多个URL用逗号分隔）
  final String? posterUrl;    // 演员封面
  final String? backdropUrl;  // 背景图
  final String? biography;
  final String? birthDate;
  final String? nationality;

  const CreateActorRequest({
    this.id,
    required this.name,
    this.avatarUrl,
    this.photoUrl,
    this.posterUrl,
    this.backdropUrl,
    this.biography,
    this.birthDate,
    this.nationality,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (posterUrl != null) 'poster_url': posterUrl,
        if (backdropUrl != null) 'backdrop_url': backdropUrl,
        if (biography != null) 'biography': biography,
        if (birthDate != null) 'birth_date': birthDate,
        if (nationality != null) 'nationality': nationality,
      };
}

/// 更新演员请求
class UpdateActorRequest {
  final String? name;
  final String? avatarUrl;    // 演员头像
  final String? photoUrl;     // 演员写真（多个URL用逗号分隔）
  final String? posterUrl;    // 演员封面
  final String? backdropUrl;  // 背景图
  final String? biography;
  final String? birthDate;
  final String? nationality;

  const UpdateActorRequest({
    this.name,
    this.avatarUrl,
    this.photoUrl,
    this.posterUrl,
    this.backdropUrl,
    this.biography,
    this.birthDate,
    this.nationality,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (posterUrl != null) 'poster_url': posterUrl,
        if (backdropUrl != null) 'backdrop_url': backdropUrl,
        if (biography != null) 'biography': biography,
        if (birthDate != null) 'birth_date': birthDate,
        if (nationality != null) 'nationality': nationality,
      };
}

/// 添加演员到媒体请求
class AddActorToMediaRequest {
  final String actorId;
  final String? characterName;
  final String? role;

  const AddActorToMediaRequest({
    required this.actorId,
    this.characterName,
    this.role,
  });

  Map<String, dynamic> toJson() => {
        'actor_id': actorId,
        if (characterName != null) 'character_name': characterName,
        if (role != null) 'role': role,
      };
}

/// 批量刮削演员响应
@JsonSerializable(fieldRename: FieldRename.snake)
class BatchScrapeActorResponse {
  final int successCount;
  final int failedCount;
  final List<FailedActor> failedActors;

  const BatchScrapeActorResponse({
    required this.successCount,
    required this.failedCount,
    required this.failedActors,
  });

  factory BatchScrapeActorResponse.fromJson(Map<String, dynamic> json) =>
      _$BatchScrapeActorResponseFromJson(json);
  Map<String, dynamic> toJson() => _$BatchScrapeActorResponseToJson(this);
}

/// 失败的演员信息
@JsonSerializable(fieldRename: FieldRename.snake)
class FailedActor {
  final String id;
  final String name;
  final String error;

  const FailedActor({
    required this.id,
    required this.name,
    required this.error,
  });

  factory FailedActor.fromJson(Map<String, dynamic> json) =>
      _$FailedActorFromJson(json);
  Map<String, dynamic> toJson() => _$FailedActorToJson(this);
}

