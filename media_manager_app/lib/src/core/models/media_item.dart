import 'package:json_annotation/json_annotation.dart';
import 'media_file.dart';

part 'media_item.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class MediaItem {
  final String id;
  final String? code;  // 识别码
  final String title;
  final String? originalTitle;
  final int? year;
  final MediaType mediaType;
  final List<String> genres;
  final double? rating;
  final int? voteCount;
  final String? posterUrl;
  final List<String> backdropUrl;  // 支持多个背景图
  final String? overview;
  final int? runtime;
  final String? releaseDate;
  final List<Person> cast;
  final List<Person> crew;
  final String? language;
  final String? country;
  final int? budget;
  final int? revenue;
  final String? status;
  final ExternalIds externalIds;
  final List<PlayLink> playLinks;
  final List<DownloadLink> downloadLinks;
  final List<String> previewUrls;
  final List<dynamic> previewVideoUrls;  // 支持结构化数据：[{"quality": "4K", "url": "..."}, ...]
  final String? coverVideoUrl;  // 封面视频URL（短小的视频缩略图，用于悬停播放）
  final String? studio;  // 制作商
  final String? series;  // 系列
  final String? localFilePath;  // 本地文件路径（向后兼容）
  final int? fileSize;  // 文件大小（向后兼容）
  final List<MediaFile> files;  // 多分段文件列表
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Sync fields
  final DateTime? lastSyncedAt;
  final bool isSynced;
  final String? syncVersion;

  const MediaItem({
    required this.id,
    this.code,
    required this.title,
    this.originalTitle,
    this.year,
    required this.mediaType,
    this.genres = const [],
    this.rating,
    this.voteCount,
    this.posterUrl,
    this.backdropUrl = const [],  // 默认为空列表
    this.overview,
    this.runtime,
    this.releaseDate,
    this.cast = const [],
    this.crew = const [],
    this.language,
    this.country,
    this.budget,
    this.revenue,
    this.status,
    required this.externalIds,
    this.playLinks = const [],
    this.downloadLinks = const [],
    this.previewUrls = const [],
    this.previewVideoUrls = const [],  // List<dynamic> 支持字典或字符串
    this.coverVideoUrl,
    this.studio,
    this.series,
    this.localFilePath,
    this.fileSize,
    this.files = const [],
    required this.createdAt,
    required this.updatedAt,
    this.lastSyncedAt,
    this.isSynced = false,
    this.syncVersion,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) =>
      _$MediaItemFromJson(json);

  Map<String, dynamic> toJson() => _$MediaItemToJson(this);

  String get displayTitle => originalTitle ?? title;
  
  String get yearString => year?.toString() ?? 'Unknown';
  
  String get ratingString => rating != null ? '${rating!.toStringAsFixed(1)}/10' : 'No rating';
  
  String get runtimeString {
    if (runtime == null) return 'Unknown';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// 提取预览视频的 URL 列表（兼容字符串和字典格式）
  List<String> get previewVideoUrlList {
    return previewVideoUrls.map((item) {
      if (item is String) {
        return item;
      } else if (item is Map<String, dynamic>) {
        return item['url'] as String? ?? '';
      }
      return '';
    }).where((url) => url.isNotEmpty).toList();
  }

  /// 获取预览视频的清晰度标签（如果有）
  String? getPreviewVideoQuality(int index) {
    if (index >= previewVideoUrls.length) return null;
    final item = previewVideoUrls[index];
    if (item is Map<String, dynamic>) {
      return item['quality'] as String?;
    }
    return null;
  }

  MediaItem copyWith({
    String? id,
    Object? code = const _Undefined(),
    String? title,
    Object? originalTitle = const _Undefined(),
    Object? year = const _Undefined(),
    MediaType? mediaType,
    List<String>? genres,
    Object? rating = const _Undefined(),
    Object? voteCount = const _Undefined(),
    Object? posterUrl = const _Undefined(),
    Object? backdropUrl = const _Undefined(),
    Object? overview = const _Undefined(),
    Object? runtime = const _Undefined(),
    Object? releaseDate = const _Undefined(),
    List<Person>? cast,
    List<Person>? crew,
    Object? language = const _Undefined(),
    Object? country = const _Undefined(),
    Object? budget = const _Undefined(),
    Object? revenue = const _Undefined(),
    Object? status = const _Undefined(),
    ExternalIds? externalIds,
    List<PlayLink>? playLinks,
    List<DownloadLink>? downloadLinks,
    List<String>? previewUrls,
    List<dynamic>? previewVideoUrls,  // List<dynamic> 支持字典或字符串
    Object? coverVideoUrl = const _Undefined(),
    Object? studio = const _Undefined(),
    Object? series = const _Undefined(),
    Object? localFilePath = const _Undefined(),
    Object? fileSize = const _Undefined(),
    List<MediaFile>? files,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
    bool? isSynced,
    String? syncVersion,
  }) {
    return MediaItem(
      id: id ?? this.id,
      code: code is _Undefined ? this.code : code as String?,
      title: title ?? this.title,
      originalTitle: originalTitle is _Undefined ? this.originalTitle : originalTitle as String?,
      year: year is _Undefined ? this.year : year as int?,
      mediaType: mediaType ?? this.mediaType,
      genres: genres ?? this.genres,
      rating: rating is _Undefined ? this.rating : rating as double?,
      voteCount: voteCount is _Undefined ? this.voteCount : voteCount as int?,
      posterUrl: posterUrl is _Undefined ? this.posterUrl : posterUrl as String?,
      backdropUrl: backdropUrl is _Undefined ? this.backdropUrl : backdropUrl as List<String>,
      overview: overview is _Undefined ? this.overview : overview as String?,
      runtime: runtime is _Undefined ? this.runtime : runtime as int?,
      releaseDate: releaseDate is _Undefined ? this.releaseDate : releaseDate as String?,
      cast: cast ?? this.cast,
      crew: crew ?? this.crew,
      language: language is _Undefined ? this.language : language as String?,
      country: country is _Undefined ? this.country : country as String?,
      budget: budget is _Undefined ? this.budget : budget as int?,
      revenue: revenue is _Undefined ? this.revenue : revenue as int?,
      status: status is _Undefined ? this.status : status as String?,
      externalIds: externalIds ?? this.externalIds,
      playLinks: playLinks ?? this.playLinks,
      downloadLinks: downloadLinks ?? this.downloadLinks,
      previewUrls: previewUrls ?? this.previewUrls,
      previewVideoUrls: previewVideoUrls ?? this.previewVideoUrls,
      coverVideoUrl: coverVideoUrl is _Undefined ? this.coverVideoUrl : coverVideoUrl as String?,
      studio: studio is _Undefined ? this.studio : studio as String?,
      series: series is _Undefined ? this.series : series as String?,
      localFilePath: localFilePath is _Undefined ? this.localFilePath : localFilePath as String?,
      fileSize: fileSize is _Undefined ? this.fileSize : fileSize as int?,
      files: files ?? this.files,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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

@JsonEnum()
enum MediaType {
  @JsonValue('Movie')
  movie,
  @JsonValue('Scene')
  scene,
  @JsonValue('Documentary')
  documentary,
  @JsonValue('Anime')
  anime,
  @JsonValue('Censored')
  censored,
  @JsonValue('Uncensored')
  uncensored,
}

@JsonSerializable()
class Person {
  final String name;
  final String role;
  final String? character;

  const Person({
    required this.name,
    required this.role,
    this.character,
  });

  factory Person.fromJson(Map<String, dynamic> json) => _$PersonFromJson(json);
  Map<String, dynamic> toJson() => _$PersonToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class ExternalIds {
  final int? tmdbId;
  final String? imdbId;
  final String? omdbId;

  const ExternalIds({
    this.tmdbId,
    this.imdbId,
    this.omdbId,
  });

  factory ExternalIds.fromJson(Map<String, dynamic> json) =>
      _$ExternalIdsFromJson(json);
  Map<String, dynamic> toJson() => _$ExternalIdsToJson(this);
}

/// 播放链接
@JsonSerializable(fieldRename: FieldRename.snake)
class PlayLink {
  final String name;      // 链接名称，如 "腾讯视频", "爱奇艺", "Netflix"
  final String url;       // 播放地址
  final String? quality;  // 画质，如 "4K", "1080P", "720P"

  const PlayLink({
    required this.name,
    required this.url,
    this.quality,
  });

  factory PlayLink.fromJson(Map<String, dynamic> json) => _$PlayLinkFromJson(json);
  Map<String, dynamic> toJson() => _$PlayLinkToJson(this);
}

/// 下载链接类型
@JsonEnum()
enum DownloadLinkType {
  @JsonValue('magnet')
  magnet,      // 磁力链接
  @JsonValue('ed2k')
  ed2k,        // 电驴链接
  @JsonValue('http')
  http,        // HTTP直链
  @JsonValue('ftp')
  ftp,         // FTP链接
  @JsonValue('torrent')
  torrent,     // 种子文件
  @JsonValue('pan')
  pan,         // 网盘链接（百度网盘、阿里云盘等）
  @JsonValue('other')
  other,       // 其他类型
}

/// 下载链接
@JsonSerializable(fieldRename: FieldRename.snake)
class DownloadLink {
  final String name;              // 链接名称，如 "1080P蓝光", "4K HDR"
  final String url;               // 下载地址
  final DownloadLinkType linkType;  // 链接类型
  final String? size;             // 文件大小，如 "4.5GB"
  final String? password;         // 提取码（网盘用）

  const DownloadLink({
    required this.name,
    required this.url,
    required this.linkType,
    this.size,
    this.password,
  });

  factory DownloadLink.fromJson(Map<String, dynamic> json) => _$DownloadLinkFromJson(json);
  Map<String, dynamic> toJson() => _$DownloadLinkToJson(this);
  
  /// 获取链接类型的显示名称
  String get linkTypeDisplay {
    switch (linkType) {
      case DownloadLinkType.magnet:
        return '磁力';
      case DownloadLinkType.ed2k:
        return '电驴';
      case DownloadLinkType.http:
        return 'HTTP';
      case DownloadLinkType.ftp:
        return 'FTP';
      case DownloadLinkType.torrent:
        return '种子';
      case DownloadLinkType.pan:
        return '网盘';
      case DownloadLinkType.other:
        return '其他';
    }
  }
}