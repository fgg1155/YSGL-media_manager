import 'package:uuid/uuid.dart';
import '../models/media_item.dart';
import '../services/backend_mode.dart';
import '../services/api_service.dart';
import '../database/local_database.dart';

/// 媒体仓库 - 根据模式自动选择数据源
class MediaRepository {
  final LocalDatabase _localDb;
  final ApiService _apiService;
  final BackendModeManager _modeManager;
  final _uuid = const Uuid();

  MediaRepository({
    required LocalDatabase localDb,
    required ApiService apiService,
    required BackendModeManager modeManager,
  })  : _localDb = localDb,
        _apiService = apiService,
        _modeManager = modeManager;

  /// 判断是否为独立模式
  bool get _isStandalone {
    final mode = _modeManager.currentMode;
    print('🔍 MediaRepository._isStandalone 检查:');
    print('  - currentMode: $mode');
    print('  - 结果: ${mode == BackendMode.standalone}');
    return mode == BackendMode.standalone;
  }

  // ==================== Media Operations ====================

  /// 添加媒体
  Future<MediaItem> addMedia(MediaItem media) async {
    print('📝 MediaRepository.addMedia 被调用');
    print('  - 媒体标题: ${media.title}');
    print('  - 媒体ID: ${media.id}');
    
    if (_isStandalone) {
      // 独立模式：保存到本地数据库
      print('  → 使用独立模式，保存到本地数据库');
      final id = media.id.isEmpty ? _uuid.v4() : media.id;
      final now = DateTime.now();
      final mediaWithId = MediaItem(
        id: id,
        code: media.code,
        title: media.title,
        originalTitle: media.originalTitle,
        year: media.year,
        mediaType: media.mediaType,
        genres: media.genres,
        rating: media.rating,
        voteCount: media.voteCount,
        posterUrl: media.posterUrl,
        backdropUrl: media.backdropUrl,
        overview: media.overview,
        runtime: media.runtime,
        releaseDate: media.releaseDate,
        cast: media.cast,
        crew: media.crew,
        language: media.language,
        country: media.country,
        budget: media.budget,
        revenue: media.revenue,
        status: media.status,
        externalIds: media.externalIds,
        playLinks: media.playLinks,
        downloadLinks: media.downloadLinks,
        previewUrls: media.previewUrls,
        previewVideoUrls: media.previewVideoUrls,
        studio: media.studio,
        series: media.series,
        createdAt: media.createdAt.year == 1970 ? now : media.createdAt,
        updatedAt: now,
        isSynced: false,  // 明确标记为未同步
      );
      await _localDb.insertMedia(mediaWithId);
      print('  ✓ 本地数据库保存成功');
      print('  - 最终ID: ${mediaWithId.id}');
      print('  - isSynced: ${mediaWithId.isSynced}');
      return mediaWithId;
    } else {
      // PC 模式：调用后端 API
      print('  → 使用 PC 模式，调用后端 API');
      try {
        final request = CreateMediaRequest(
          title: media.title,
          originalTitle: media.originalTitle,
          code: media.code,
          mediaType: media.mediaType,
          year: media.year,
          releaseDate: media.releaseDate,
          overview: media.overview,
          genres: media.genres,
          rating: media.rating,
          runtime: media.runtime,
          posterUrl: media.posterUrl,
          backdropUrl: media.backdropUrl,
          studio: media.studio,
          series: media.series,
          playLinks: media.playLinks,
          downloadLinks: media.downloadLinks,
          cast: media.cast,
          crew: media.crew,
        );
        print('  - 创建请求对象完成');
        print('  - mediaType: ${request.mediaType}');
        
        final result = await _apiService.createMedia(request);
        print('  ✓ PC 后端创建成功');
        print('  - 返回ID: ${result.id}');
        return result;
      } catch (e, stackTrace) {
        print('  ✗ PC 后端创建失败');
        print('  - 错误: $e');
        print('  - 堆栈: $stackTrace');
        rethrow;
      }
    }
  }

  /// 获取媒体详情
  Future<MediaItem?> getMedia(String id) async {
    if (_isStandalone) {
      return await _localDb.getMedia(id);
    } else {
      try {
        return await _apiService.getMediaDetail(id);
      } catch (e) {
        print('Failed to get media from PC backend: $e');
        return null;
      }
    }
  }

  /// 搜索媒体（本地数据）
  Future<List<MediaItem>> searchMedia(String query) async {
    if (_isStandalone) {
      return await _localDb.queryMedia(searchQuery: query);
    } else {
      try {
        // PC 模式：搜索本地已有的媒体数据，不调用插件
        final result = await getMediaList(
          keyword: query,
          page: 1,
          pageSize: 100, // 返回更多结果
        );
        return result.items;
      } catch (e) {
        print('Failed to search media from PC backend: $e');
        return [];
      }
    }
  }
  
  /// 搜索外部数据源（插件）
  Future<List<MediaItem>> searchExternalMedia(String query) async {
    try {
      final response = await _apiService.searchMedia(query: query);
      return response.results;
    } catch (e) {
      print('Failed to search external media: $e');
      return [];
    }
  }

  /// 获取媒体列表
  Future<MediaListResult> getMediaList({
    String? mediaType,
    String? studio,
    String? series,
    String? keyword,
    String? sortBy,
    String? sortOrder,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (_isStandalone) {
      // 独立模式：从本地数据库查询
      final offset = (page - 1) * pageSize;
      final items = await _localDb.queryMedia(
        mediaType: mediaType,
        searchQuery: keyword,
        studio: studio,
        series: series,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: pageSize,
        offset: offset,
      );
      final total = await _localDb.getMediaCount(mediaType: mediaType);
      
      return MediaListResult(
        items: items,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
        hasNext: page * pageSize < total,
        hasPrev: page > 1,
      );
    } else {
      // PC 模式：调用后端 API
      try {
        final response = await _apiService.getMediaList(
          page: page,
          limit: pageSize,
          mediaType: mediaType,
          studio: studio,
          series: series,
          keyword: keyword,
          sortBy: sortBy,
          sortOrder: sortOrder,
        );
        return MediaListResult(
          items: response.items,
          total: response.total,
          page: response.page,
          pageSize: response.pageSize,
          totalPages: response.totalPages,
          hasNext: response.hasNext,
          hasPrev: response.hasPrev,
        );
      } catch (e) {
        print('Failed to get media list from PC backend: $e');
        return MediaListResult.empty();
      }
    }
  }

  /// 获取所有媒体（用于文件匹配）
  Future<List<MediaItem>> getAllMedia() async {
    if (_isStandalone) {
      // 独立模式：从本地数据库获取所有媒体
      return await _localDb.queryMedia(limit: 999999);
    } else {
      // PC 模式：分页获取所有媒体
      try {
        final allMedia = <MediaItem>[];
        int page = 1;
        const pageSize = 100;
        
        while (true) {
          final response = await _apiService.getMediaList(
            page: page,
            limit: pageSize,
          );
          
          allMedia.addAll(response.items);
          
          if (!response.hasNext) {
            break;
          }
          
          page++;
        }
        
        return allMedia;
      } catch (e) {
        print('Failed to get all media from PC backend: $e');
        return [];
      }
    }
  }

  /// 更新媒体
  Future<void> updateMedia(MediaItem media) async {
    if (_isStandalone) {
      final updatedMedia = media.copyWith(
        updatedAt: DateTime.now(),
        isSynced: false,  // 本地修改后标记为未同步
      );
      await _localDb.updateMedia(updatedMedia);
      print('📝 媒体已更新（独立模式）: ${media.title}');
      print('  - isSynced 设置为 false');
    } else {
      // 将 MediaType 枚举转换为后端期望的字符串格式
      String mediaTypeToString(MediaType type) {
        switch (type) {
          case MediaType.movie:
            return 'Movie';
          case MediaType.scene:
            return 'Scene';
          case MediaType.documentary:
            return 'Documentary';
          case MediaType.anime:
            return 'Anime';
          case MediaType.censored:
            return 'Censored';
          case MediaType.uncensored:
            return 'Uncensored';
        }
      }
      
      final request = UpdateMediaRequest(
        title: media.title,
        originalTitle: media.originalTitle,
        code: media.code,
        mediaType: mediaTypeToString(media.mediaType),
        year: media.year,
        releaseDate: media.releaseDate,
        overview: media.overview,
        genres: media.genres,
        rating: media.rating,
        runtime: media.runtime,
        posterUrl: media.posterUrl,
        backdropUrl: media.backdropUrl,
        coverVideoUrl: media.coverVideoUrl,  // 封面视频 URL
        studio: media.studio,
        series: media.series,
        playLinks: media.playLinks,
        downloadLinks: media.downloadLinks,
        previewUrls: media.previewUrls,
        previewVideoUrls: media.previewVideoUrlList,  // 提取 URL 列表
        cast: media.cast,
        crew: media.crew,
      );
      await _apiService.updateMedia(media.id, request);
    }
  }

  /// 删除媒体
  Future<void> deleteMedia(String id) async {
    if (_isStandalone) {
      await _localDb.deleteMedia(id);
    } else {
      await _apiService.deleteMedia(id);
    }
  }

  /// 批量删除媒体
  Future<void> batchDeleteMedia(List<String> ids) async {
    if (_isStandalone) {
      await _localDb.transaction((txn) async {
        for (final id in ids) {
          // 删除媒体
          await txn.delete('media', where: 'id = ?', whereArgs: [id]);
          // 删除相关的收藏记录
          await txn.delete('collections', where: 'media_id = ?', whereArgs: [id]);
          // 删除相关的演员-媒体关系
          await txn.delete('media_actors', where: 'media_id = ?', whereArgs: [id]);
        }
      });
    } else {
      await _apiService.batchDeleteMedia(ids);
    }
  }

  /// 获取媒体统计
  Future<MediaStats> getStats() async {
    if (_isStandalone) {
      final total = await _localDb.getMediaCount();
      final movies = await _localDb.getMediaCount(mediaType: 'movie');
      final tvShows = await _localDb.getMediaCount(mediaType: 'tv');
      
      return MediaStats(
        total: total,
        movies: movies,
        tvShows: tvShows,
      );
    } else {
      try {
        final stats = await _apiService.getStats();
        return MediaStats(
          total: stats['total_media'] ?? 0,
          movies: stats['total_movies'] ?? 0,
          tvShows: stats['total_tv_shows'] ?? 0,
        );
      } catch (e) {
        print('Failed to get stats from PC backend: $e');
        return MediaStats.empty();
      }
    }
  }

  /// 获取筛选选项
  Future<FilterOptions> getFilterOptions() async {
    if (_isStandalone) {
      // 独立模式：从本地数据库获取
      final mediaTypes = await _localDb.getDistinctMediaTypes();
      final studios = await _localDb.getDistinctStudios();
      final series = await _localDb.getDistinctSeries();
      final years = await _localDb.getDistinctYears();
      final genres = await _localDb.getDistinctGenres();
      
      return FilterOptions(
        mediaTypes: mediaTypes,
        studios: studios,
        series: series,
        years: years,
        genres: genres,
      );
    } else {
      // PC 模式：调用后端 API
      try {
        return await _apiService.getFilterOptions();
      } catch (e) {
        print('Failed to get filter options from PC backend: $e');
        // 如果后端失败，尝试从本地数据库获取
        final mediaTypes = await _localDb.getDistinctMediaTypes();
        final studios = await _localDb.getDistinctStudios();
        final series = await _localDb.getDistinctSeries();
        final years = await _localDb.getDistinctYears();
        final genres = await _localDb.getDistinctGenres();
        
        return FilterOptions(
          mediaTypes: mediaTypes,
          studios: studios,
          series: series,
          years: years,
          genres: genres,
        );
      }
    }
  }
}

/// 媒体列表结果
class MediaListResult {
  final List<MediaItem> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  const MediaListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory MediaListResult.empty() {
    return const MediaListResult(
      items: [],
      total: 0,
      page: 1,
      pageSize: 20,
      totalPages: 0,
      hasNext: false,
      hasPrev: false,
    );
  }
}

/// 媒体统计
class MediaStats {
  final int total;
  final int movies;
  final int tvShows;

  const MediaStats({
    required this.total,
    required this.movies,
    required this.tvShows,
  });

  factory MediaStats.empty() {
    return const MediaStats(
      total: 0,
      movies: 0,
      tvShows: 0,
    );
  }
}
