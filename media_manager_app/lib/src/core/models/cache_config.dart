/// 缓存配置数据模型
class CacheConfig {
  /// 全局缓存开关
  final bool globalCacheEnabled;
  
  /// 各刮削器的缓存配置
  final Map<String, ScraperCacheConfig> scrapers;

  const CacheConfig({
    required this.globalCacheEnabled,
    required this.scrapers,
  });

  factory CacheConfig.fromJson(Map<String, dynamic> json) {
    final scrapersMap = <String, ScraperCacheConfig>{};
    if (json['scrapers'] != null) {
      (json['scrapers'] as Map<String, dynamic>).forEach((key, value) {
        scrapersMap[key] = ScraperCacheConfig.fromJson(value);
      });
    }
    
    return CacheConfig(
      globalCacheEnabled: json['global_cache_enabled'] ?? false,
      scrapers: scrapersMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'global_cache_enabled': globalCacheEnabled,
      'scrapers': scrapers.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  CacheConfig copyWith({
    bool? globalCacheEnabled,
    Map<String, ScraperCacheConfig>? scrapers,
  }) {
    return CacheConfig(
      globalCacheEnabled: globalCacheEnabled ?? this.globalCacheEnabled,
      scrapers: scrapers ?? this.scrapers,
    );
  }
}

/// 单个刮削器的缓存配置
class ScraperCacheConfig {
  /// 是否开启缓存
  final bool cacheEnabled;
  
  /// 是否为自动开启
  final bool autoEnabled;
  
  /// 自动开启的时间
  final DateTime? autoEnabledAt;
  
  /// 需要缓存的字段
  final List<CacheField> cacheFields;

  const ScraperCacheConfig({
    required this.cacheEnabled,
    required this.autoEnabled,
    this.autoEnabledAt,
    required this.cacheFields,
  });

  factory ScraperCacheConfig.fromJson(Map<String, dynamic> json) {
    final fields = (json['cache_fields'] as List<dynamic>?)
        ?.map((e) => CacheField.fromString(e as String))
        .toList() ?? [];
    
    return ScraperCacheConfig(
      cacheEnabled: json['cache_enabled'] ?? false,
      autoEnabled: json['auto_enabled'] ?? false,
      autoEnabledAt: json['auto_enabled_at'] != null 
          ? DateTime.parse(json['auto_enabled_at'])
          : null,
      cacheFields: fields,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cache_enabled': cacheEnabled,
      'auto_enabled': autoEnabled,
      if (autoEnabledAt != null) 'auto_enabled_at': autoEnabledAt!.toIso8601String(),
      'cache_fields': cacheFields.map((e) => e.toApiString()).toList(),
    };
  }

  ScraperCacheConfig copyWith({
    bool? cacheEnabled,
    bool? autoEnabled,
    DateTime? autoEnabledAt,
    List<CacheField>? cacheFields,
  }) {
    return ScraperCacheConfig(
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      autoEnabled: autoEnabled ?? this.autoEnabled,
      autoEnabledAt: autoEnabledAt ?? this.autoEnabledAt,
      cacheFields: cacheFields ?? this.cacheFields,
    );
  }
}

/// 可缓存的字段类型
enum CacheField {
  poster,
  backdrop,
  preview,
  previewVideo,
  coverVideo;

  String toApiString() {
    switch (this) {
      case CacheField.poster:
        return 'poster';
      case CacheField.backdrop:
        return 'backdrop';
      case CacheField.preview:
        return 'preview';
      case CacheField.previewVideo:
        return 'preview_video';
      case CacheField.coverVideo:
        return 'cover_video';
    }
  }

  String get displayName {
    switch (this) {
      case CacheField.poster:
        return '封面图';
      case CacheField.backdrop:
        return '背景图';
      case CacheField.preview:
        return '预览图';
      case CacheField.previewVideo:
        return '预览视频';
      case CacheField.coverVideo:
        return '封面视频';
    }
  }

  static CacheField fromString(String value) {
    switch (value) {
      case 'poster':
        return CacheField.poster;
      case 'backdrop':
        return CacheField.backdrop;
      case 'preview':
        return CacheField.preview;
      case 'preview_video':
        return CacheField.previewVideo;
      case 'cover_video':
        return CacheField.coverVideo;
      default:
        throw ArgumentError('Unknown cache field: $value');
    }
  }
}

/// 缓存统计信息
class CacheStats {
  /// 总缓存大小（字节）
  final int totalSize;
  
  /// 总文件数
  final int totalFiles;
  
  /// 按刮削器统计
  final Map<String, ScraperCacheStats> byScraperStats;

  const CacheStats({
    required this.totalSize,
    required this.totalFiles,
    required this.byScraperStats,
  });

  factory CacheStats.fromJson(Map<String, dynamic> json) {
    final byScraperMap = <String, ScraperCacheStats>{};
    if (json['by_scraper'] != null) {
      (json['by_scraper'] as Map<String, dynamic>).forEach((key, value) {
        byScraperMap[key] = ScraperCacheStats.fromJson(value);
      });
    }
    
    return CacheStats(
      totalSize: json['total_size'] ?? 0,
      totalFiles: json['total_files'] ?? 0,
      byScraperStats: byScraperMap,
    );
  }

  /// 格式化文件大小显示
  String get formattedTotalSize => _formatBytes(totalSize);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 单个刮削器的缓存统计
class ScraperCacheStats {
  /// 缓存大小（字节）
  final int size;
  
  /// 文件数
  final int files;

  const ScraperCacheStats({
    required this.size,
    required this.files,
  });

  factory ScraperCacheStats.fromJson(Map<String, dynamic> json) {
    return ScraperCacheStats(
      size: json['size'] ?? 0,
      files: json['files'] ?? 0,
    );
  }

  /// 格式化文件大小显示
  String get formattedSize => CacheStats._formatBytes(size);
}
