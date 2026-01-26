import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'dart:io' show Platform;

import '../models/media_item.dart';
import '../models/media_file.dart';
import '../models/collection.dart';
import '../models/actor.dart';
import '../models/studio.dart';
import '../models/plugin_info.dart';
import '../config/app_config.dart';

/// Security interceptor for API requests
class SecurityInterceptor extends Interceptor {
  final bool requireHttps;
  final String? authToken;

  SecurityInterceptor({
    this.requireHttps = false,
    this.authToken,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Validate HTTPS in production
    if (requireHttps && !options.uri.toString().startsWith('https://')) {
      if (!options.uri.toString().contains('localhost')) {
        handler.reject(
          DioException(
            requestOptions: options,
            error: 'HTTPS is required for non-localhost requests',
          ),
        );
        return;
      }
    }

    // Add auth token if available
    if (authToken != null) {
      options.headers['Authorization'] = 'Bearer $authToken';
    }

    // Add security headers
    options.headers['X-Content-Type-Options'] = 'nosniff';
    options.headers['X-Frame-Options'] = 'DENY';

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Validate response headers for security
    handler.next(response);
  }
}

/// Retry interceptor for failed requests
class RetryInterceptor extends Interceptor {
  final int maxRetries;
  final Duration retryDelay;
  final Dio dio;

  RetryInterceptor({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    required this.dio,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    // Only retry on network errors or 5xx server errors
    if (retryCount < maxRetries && _shouldRetry(err)) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      
      await Future.delayed(retryDelay * (retryCount + 1));
      
      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        // Continue to error handler
      }
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
           err.type == DioExceptionType.receiveTimeout ||
           err.type == DioExceptionType.sendTimeout ||
           (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}

class ApiService {
  final Dio _dio;
  
  ApiService({String? baseUrl, String? authToken, bool requireHttps = false}) : _dio = Dio() {
    // 使用传入�?baseUrl，如果没有则使用默认�?
    final effectiveBaseUrl = baseUrl ?? 'http://localhost:3000';
    _dio.options.baseUrl = effectiveBaseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    
    if (kDebugMode) {
      debugPrint('🌐 ApiService initialized with baseUrl: $effectiveBaseUrl');
    }
    
    // Add security interceptor
    _dio.interceptors.add(SecurityInterceptor(
      requireHttps: requireHttps,
      authToken: authToken,
    ));
    
    // Add retry interceptor
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
    
    // Add interceptors for logging and error handling (debug mode only)
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
      
      _dio.interceptors.add(InterceptorsWrapper(
        onError: (error, handler) {
          debugPrint('API Error: ${error.message}');
          handler.next(error);
        },
      ));
    }
  }

  /// 辅助方法：从响应中提取数据，处理 ApiResponse 包装格式
  Map<String, dynamic> _extractData(dynamic responseData) {
    if (responseData is Map<String, dynamic>) {
      // 如果�?'data' 字段，说明是 ApiResponse 包装格式
      if (responseData.containsKey('data')) {
        final data = responseData['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      // 否则直接返回原数�?
      return responseData;
    }
    return {};
  }

  // Media endpoints
  Future<PaginatedResponse<MediaItem>> getMediaList({
    int page = 1,
    int limit = 20,
    String? mediaType,
    String? studio,
    String? series,
    String? keyword,
    int? year,
    String? genre,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final response = await _dio.get('/media', queryParameters: {
        'page': page,
        'limit': limit,
        if (mediaType != null) 'media_type': mediaType,
        if (studio != null) 'studio': studio,
        if (series != null) 'series': series,
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      });
      
      return PaginatedResponse<MediaItem>.fromJson(
        response.data,
        (json) => MediaItem.fromJson(json as Map<String, dynamic>),
      );
    } catch (e) {
      throw ApiException('Failed to fetch media list: $e');
    }
  }

  /// 获取筛选选项
  Future<FilterOptions> getFilterOptions() async {
    try {
      final response = await _dio.get('/media/filters');
      return FilterOptions.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch filter options: $e');
    }
  }

  Future<MediaItem> getMediaDetail(String id) async {
    try {
      final response = await _dio.get('/media/$id');
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return MediaItem.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to fetch media detail: $e');
    }
  }

  Future<MediaItem> createMedia(CreateMediaRequest request) async {
    try {
      final response = await _dio.post('/media', data: request.toJson());
      final data = response.data['data'] ?? response.data;
      return MediaItem.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to create media: $e');
    }
  }

  Future<MediaItem> updateMedia(String id, UpdateMediaRequest request) async {
    try {
      final response = await _dio.put('/media/$id', data: request.toJson());
      final data = response.data['data'] ?? response.data;
      return MediaItem.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to update media: $e');
    }
  }

  Future<void> deleteMedia(String id) async {
    try {
      await _dio.delete('/media/$id');
    } catch (e) {
      throw ApiException('Failed to delete media: $e');
    }
  }

  // Collection endpoints
  Future<List<Collection>> getCollections() async {
    try {
      final response = await _dio.get('/collections');
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return (data as List)
          .map((json) => Collection.fromJson(json))
          .toList();
    } catch (e) {
      throw ApiException('Failed to fetch collections: $e');
    }
  }

  Future<Collection> addToCollection(AddToCollectionRequest request) async {
    try {
      final response = await _dio.post('/collections', data: request.toJson());
      final data = response.data['data'] ?? response.data;
      return Collection.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to add to collection: $e');
    }
  }

  Future<void> removeFromCollection(String mediaId) async {
    try {
      await _dio.delete('/collections/$mediaId');
    } catch (e) {
      throw ApiException('Failed to remove from collection: $e');
    }
  }

  Future<Collection> updateCollectionStatus(
    String mediaId,
    UpdateCollectionRequest request,
  ) async {
    try {
      final response = await _dio.put('/collections/$mediaId/status', data: request.toJson());
      return Collection.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to update collection status: $e');
    }
  }

  // Search endpoints
  Future<SearchResponse> searchMedia({
    required String query,
    String? mediaType,
    int page = 1,
    String source = 'all',
    int limit = 20,
    String? actorId,
    String? studio,
    String? series,
  }) async {
    try {
      final response = await _dio.get('/search', queryParameters: {
        'q': query,
        if (mediaType != null) 'media_type': mediaType,
        'page': page,
        'source': source,
        'limit': limit,
        if (actorId != null) 'actor_id': actorId,
        if (studio != null) 'studio': studio,
        if (series != null) 'series': series,
      });
      
      return SearchResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to search media: $e');
    }
  }

  Future<SearchResponse> advancedSearch(AdvancedSearchRequest request) async {
    try {
      final response = await _dio.post('/search/advanced', data: request.toJson());
      return SearchResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to perform advanced search: $e');
    }
  }

  Future<List<SearchSuggestion>> getSearchSuggestions(String query) async {
    try {
      final response = await _dio.get('/search/suggestions', queryParameters: {
        'q': query,
      });
      
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      final suggestions = data['suggestions'] ?? data;
      
      return (suggestions as List)
          .map((json) => SearchSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      throw ApiException('Failed to get search suggestions: $e');
    }
  }

  Future<List<String>> getTrendingSearches() async {
    try {
      final response = await _dio.get('/search/trending');
      return List<String>.from(response.data);
    } catch (e) {
      throw ApiException('Failed to get trending searches: $e');
    }
  }

  // TMDB endpoints
  Future<MediaItem> getTmdbDetails({
    required int tmdbId,
    required String mediaType,
  }) async {
    try {
      final response = await _dio.get('/tmdb/details', queryParameters: {
        'tmdb_id': tmdbId,
        'media_type': mediaType,
      });
      
      final data = response.data['data'] ?? response.data;
      return MediaItem.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to get TMDB details: $e');
    }
  }

  Future<List<MediaItem>> getPopularContent({
    String mediaType = 'movie',
    int page = 1,
  }) async {
    try {
      final response = await _dio.get('/tmdb/popular', queryParameters: {
        'media_type': mediaType,
        'page': page,
      });
      
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      final results = data['results'] ?? data;
      
      return (results as List)
          .map((json) => MediaItem.fromJson(json))
          .toList();
    } catch (e) {
      throw ApiException('Failed to get popular content: $e');
    }
  }

  Future<MediaItem> saveTmdbMedia(MediaItem mediaItem) async {
    try {
      final response = await _dio.post('/tmdb/save', data: mediaItem.toJson());
      final data = response.data['data'] ?? response.data;
      return MediaItem.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to save TMDB media: $e');
    }
  }

  // Actor endpoints
  Future<ActorListResponse> getActors({
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get('/actors', queryParameters: {
        if (query != null && query.isNotEmpty) 'query': query,
        'limit': limit,
        'offset': offset,
      });
      return ActorListResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch actors: $e');
    }
  }

  /// 搜索演员（返回演员列表）
  Future<List<Actor>> searchActors(String query, {int limit = 20}) async {
    try {
      final response = await getActors(query: query, limit: limit);
      return response.actors;
    } catch (e) {
      throw ApiException('Failed to search actors: $e');
    }
  }

  Future<ActorDetailResponse> getActor(String id) async {
    try {
      final response = await _dio.get('/actors/$id');
      return ActorDetailResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch actor detail: $e');
    }
  }

  Future<Actor> createActor(CreateActorRequest request) async {
    try {
      final response = await _dio.post('/actors', data: request.toJson());
      return Actor.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to create actor: $e');
    }
  }

  Future<Actor> updateActor(String id, UpdateActorRequest request) async {
    try {
      final response = await _dio.put('/actors/$id', data: request.toJson());
      return Actor.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to update actor: $e');
    }
  }

  Future<void> deleteActor(String id) async {
    try {
      await _dio.delete('/actors/$id');
    } catch (e) {
      throw ApiException('Failed to delete actor: $e');
    }
  }

  // Actor-Media relationship endpoints
  Future<List<MediaActor>> getActorsForMedia(String mediaId) async {
    try {
      final response = await _dio.get('/media/$mediaId/actors');
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return (data as List)
          .map((json) => MediaActor.fromJson(json))
          .toList();
    } catch (e) {
      throw ApiException('Failed to fetch actors for media: $e');
    }
  }

  Future<void> addActorToMedia(String mediaId, AddActorToMediaRequest request) async {
    try {
      await _dio.post('/media/$mediaId/actors', data: request.toJson());
    } catch (e) {
      throw ApiException('Failed to add actor to media: $e');
    }
  }

  Future<void> removeActorFromMedia(String mediaId, String actorId) async {
    try {
      await _dio.delete('/media/$mediaId/actors/$actorId');
    } catch (e) {
      throw ApiException('Failed to remove actor from media: $e');
    }
  }

  // ==================== Actor Scraping Operations ====================
  // 注意：所有刮削功能已迁移到插件UI系统
  // 通过 Media_Scraper 插件�?UI manifest 调用后端API
  // 这些方法已废弃，保留仅为向后兼容

  // Studio endpoints
  Future<StudioListResponse> getStudios({
    int? limit,
    int? offset,
  }) async {
    try {
      final response = await _dio.get('/studios', queryParameters: {
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      });
      return StudioListResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch studios: $e');
    }
  }

  Future<StudioWithSeries> getStudio(String id) async {
    try {
      final response = await _dio.get('/studios/$id');
      return StudioWithSeries.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch studio detail: $e');
    }
  }

  Future<Studio> createStudio(CreateStudioRequest request) async {
    try {
      final response = await _dio.post('/studios', data: request.toJson());
      return Studio.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to create studio: $e');
    }
  }

  Future<Studio> updateStudio(String id, UpdateStudioRequest request) async {
    try {
      final response = await _dio.put('/studios/$id', data: request.toJson());
      return Studio.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to update studio: $e');
    }
  }

  Future<void> deleteStudio(String id) async {
    try {
      await _dio.delete('/studios/$id');
    } catch (e) {
      throw ApiException('Failed to delete studio: $e');
    }
  }

  // Series endpoints
  Future<SeriesListResponse> getSeries({
    String? studioId,
    int? limit,
    int? offset,
  }) async {
    try {
      final response = await _dio.get('/series', queryParameters: {
        if (studioId != null) 'studio_id': studioId,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      });
      return SeriesListResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch series: $e');
    }
  }

  Future<SeriesWithStudio> getSeriesDetail(String id) async {
    try {
      final response = await _dio.get('/series/$id');
      return SeriesWithStudio.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to fetch series detail: $e');
    }
  }

  Future<Series> createSeries(CreateSeriesRequest request) async {
    try {
      final response = await _dio.post('/series', data: request.toJson());
      return Series.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to create series: $e');
    }
  }

  Future<Series> updateSeries(String id, UpdateSeriesRequest request) async {
    try {
      final response = await _dio.put('/series/$id', data: request.toJson());
      return Series.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to update series: $e');
    }
  }

  Future<void> deleteSeries(String id) async {
    try {
      await _dio.delete('/series/$id');
    } catch (e) {
      throw ApiException('Failed to delete series: $e');
    }
  }

  /// 同步制作商和系列的媒体计�?
  Future<void> syncStudioSeriesCounts() async {
    try {
      await _dio.post('/studios-series/sync-counts');
    } catch (e) {
      throw ApiException('Failed to sync counts: $e');
    }
  }

  /// 搜索制作商（模糊匹配�?
  Future<List<Studio>> searchStudios(String query, {int? limit}) async {
    try {
      final response = await _dio.get('/studios/search', queryParameters: {
        'q': query,
        if (limit != null) 'limit': limit,
      });
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return (data as List)
          .map((json) => Studio.fromJson(json))
          .toList();
    } catch (e) {
      throw ApiException('Failed to search studios: $e');
    }
  }

  /// 搜索系列（模糊匹配）
  Future<List<SeriesWithStudio>> searchSeries(
    String query, {
    String? studioId,
    int? limit,
  }) async {
    try {
      final response = await _dio.get('/series/search', queryParameters: {
        'q': query,
        if (studioId != null) 'studio_id': studioId,
        if (limit != null) 'limit': limit,
      });
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return (data as List)
          .map((json) => SeriesWithStudio.fromJson(json))
          .toList();
    } catch (e) {
      throw ApiException('Failed to search series: $e');
    }
  }

  // Health check
  Future<Map<String, dynamic>> getHealthStatus() async {
    try {
      final response = await _dio.get('/health');
      return _extractData(response.data);
    } catch (e) {
      throw ApiException('Failed to get health status: $e');
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await _dio.get('/stats');
      return _extractData(response.data);
    } catch (e) {
      throw ApiException('Failed to get stats: $e');
    }
  }

  // Scrape endpoints
  /// 获取可用的刮削插件列�?
  Future<List<PluginInfo>> getPlugins() async {
    try {
      final response = await _dio.get('/scrape/plugins');
      if (response.data['success'] == true) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((json) => PluginInfo.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      // 失败时返回空列表，视为无可用插件
      return [];
    }
  }

  // Batch operations
  Future<BatchImportResponse> batchImportMedia(List<BatchImportItem> items) async {
    try {
      final response = await _dio.post('/batch/import', data: {
        'items': items.map((e) => e.toJson()).toList(),
      });
      return BatchImportResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to batch import media: $e');
    }
  }

  Future<BatchCollectionResponse> batchCollectionOperation(
    List<String> mediaIds,
    BatchCollectionAction action, {
    WatchStatus? watchStatus,
    List<String>? tags,
  }) async {
    try {
      final response = await _dio.post('/batch/collection', data: {
        'media_ids': mediaIds,
        'action': action.name,
        if (watchStatus != null) 'watch_status': watchStatus.name,
        if (tags != null) 'tags': tags,
      });
      return BatchCollectionResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to batch collection operation: $e');
    }
  }

  /// 批量删除媒体
  Future<BatchDeleteResponse> batchDeleteMedia(List<String> ids) async {
    try {
      final response = await _dio.post('/batch/delete', data: {
        'ids': ids,
      });
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return BatchDeleteResponse.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to batch delete media: $e');
    }
  }

  /// 批量编辑媒体
  Future<BatchEditResponse> batchEditMedia(
    List<String> ids,
    BatchEditUpdates updates,
  ) async {
    try {
      final response = await _dio.post('/batch/edit', data: {
        'ids': ids,
        'updates': updates.toJson(),
      });
      // 处理统一�?ApiResponse 包装格式
      final data = response.data['data'] ?? response.data;
      return BatchEditResponse.fromJson(data);
    } catch (e) {
      throw ApiException('Failed to batch edit media: $e');
    }
  }

  // Export/Import endpoints
  Future<ExportDataResponse> exportAllData() async {
    try {
      final response = await _dio.get('/data/export');
      return ExportDataResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to export data: $e');
    }
  }

  Future<ImportDataResponse> importData(ImportDataRequest request) async {
    try {
      final response = await _dio.post('/data/import', data: request.toJson());
      return ImportDataResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to import data: $e');
    }
  }

  // Sync endpoints
  /// 触发同步请求（PC Web 版调用）
  Future<Map<String, dynamic>> triggerSync() async {
    try {
      final response = await _dio.post('/sync/trigger');
      return _extractData(response.data);
    } catch (e) {
      throw ApiException('Failed to trigger sync: $e');
    }
  }

  /// 检查同步请求（移动端调用）
  Future<Map<String, dynamic>> checkSyncRequest() async {
    try {
      final response = await _dio.get('/sync/check');
      return _extractData(response.data);
    } catch (e) {
      throw ApiException('Failed to check sync request: $e');
    }
  }

  /// 完成同步（移动端调用）
  Future<Map<String, dynamic>> completeSync(String deviceId) async {
    try {
      final response = await _dio.post('/sync/complete', data: {
        'device_id': deviceId,
      });
      return _extractData(response.data);
    } catch (e) {
      throw ApiException('Failed to complete sync: $e');
    }
  }

  /// 获取同步状态（Web 版查询）
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final response = await _dio.get('/sync/status');
      return _extractData(response.data);
    } catch (e) {
      throw ApiException('Failed to get sync status: $e');
    }
  }

  // File scan endpoints
  
  /// 开始扫描目�?
  Future<ScanResponse> startScan({
    required List<String> paths,  // 支持多个路径
    required bool recursive,
  }) async {
    try {
      final response = await _dio.post('/scan/start', data: {
        'paths': paths,
        'recursive': recursive,
      });
      
      if (kDebugMode) {
        debugPrint('Scan response data: ${response.data}');
      }
      
      return ScanResponse.fromJson(_extractData(response.data));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to start scan: $e');
      }
      throw ApiException('Failed to start scan: $e');
    }
  }

  /// 执行文件匹配
  Future<MatchResponse> matchFiles(List<ScannedFile> scannedFiles, List<FileGroup> fileGroups) async {
    try {
      final requestData = {
        'scanned_files': scannedFiles.map((f) => f.toJson()).toList(),
        'file_groups': fileGroups.map((g) => g.toJson()).toList(),
      };
      
      if (kDebugMode) {
        debugPrint('Match request data: $requestData');
      }
      
      final response = await _dio.post('/scan/match', data: requestData);
      return MatchResponse.fromJson(_extractData(response.data));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Match files error: $e');
      }
      throw ApiException('Failed to match files: $e');
    }
  }

  /// 确认匹配结果
  Future<ConfirmMatchResponse> confirmMatches(List<ConfirmMatch> matches) async {
    try {
      final response = await _dio.post('/scan/confirm', data: {
        'matches': matches.map((m) => m.toJson()).toList(),
      });
      return ConfirmMatchResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to confirm matches: $e');
    }
  }

  /// 自动刮削未匹配的文件
  /// 批量刮削可能需要很长时间，使用更长的超时时间（10分钟�?
  Future<AutoScrapeResponse> autoScrapeUnmatched(
    List<ScannedFile> unmatchedFiles, {
    List<FileGroup>? unmatchedGroups,
  }) async {
    try {
      // 创建一个临时的 Dio 实例，使用更长的超时时间�?0分钟�?
      final tempDio = Dio(_dio.options.copyWith(
        connectTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ));
      
      final response = await tempDio.post('/scan/auto-scrape', data: {
        'unmatched_files': unmatchedFiles.map((f) => f.toJson()).toList(),
        if (unmatchedGroups != null)
          'unmatched_groups': unmatchedGroups.map((g) => g.toJson()).toList(),
      });
      return AutoScrapeResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to auto scrape: $e');
    }
  }

  /// 忽略文件
  Future<IgnoreFileResponse> ignoreFile({
    required String filePath,
    required String fileName,
    String? reason,
  }) async {
    try {
      final response = await _dio.post('/scan/ignore', data: {
        'file_path': filePath,
        'file_name': fileName,
        if (reason != null) 'reason': reason,
      });
      return IgnoreFileResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to ignore file: $e');
    }
  }

  /// 获取忽略文件列表
  Future<GetIgnoredFilesResponse> getIgnoredFiles() async {
    try {
      final response = await _dio.get('/scan/ignored');
      return GetIgnoredFilesResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to get ignored files: $e');
    }
  }

  /// 移除忽略文件
  Future<IgnoreFileResponse> removeIgnoredFile(String id) async {
    try {
      final response = await _dio.post('/scan/ignored/remove', data: {
        'id': id,
      });
      return IgnoreFileResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to remove ignored file: $e');
    }
  }

  /// 获取媒体的所有文件（多分段视频支持）
  Future<GetMediaFilesResponse> getMediaFiles(String mediaId) async {
    try {
      final response = await _dio.get('/media/$mediaId/files');
      return GetMediaFilesResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to get media files: $e');
    }
  }

  /// 获取媒体刮削进度
  Future<MediaScrapeProgressResponse> getMediaScrapeProgress(String sessionId) async {
    try {
      final response = await _dio.get('/scrape/progress/$sessionId');
      return MediaScrapeProgressResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to get scrape progress: $e');
    }
  }

  /// 刮削媒体（统一端点）
  /// 根据返回结果自动决定：
  /// - 1个结果：直接入库，返回 MediaItem
  /// - 多个结果：返回 ScrapeMultipleResponse 供用户选择
  Future<ScrapeMediaResponse> scrapeMedia({
    required String mediaId,
    String? code,
    String? contentType,
    String? series,
    String mode = 'replace',  // 'replace' 或 'supplement'
  }) async {
    try {
      final response = await _dio.post('/scrape/media/$mediaId', data: {
        if (code != null) 'code': code,
        if (contentType != null) 'content_type': contentType,
        if (series != null) 'series': series,
        'mode': mode,
      });
      
      final data = _extractData(response.data);
      
      // 检查是否是多结果格式
      if (data['mode'] == 'multiple') {
        return ScrapeMediaResponse.multiple(
          ScrapeMultipleResponse.fromJson(data),
        );
      }
      
      // 单个结果，直接入库了
      return ScrapeMediaResponse.single(
        MediaItem.fromJson(data),
      );
    } catch (e) {
      throw ApiException('Failed to scrape media: $e');
    }
  }

  /// 批量导入刮削结果
  Future<BatchImportScrapeResponse> batchImportScrapeResults({
    required String mediaId,
    required List<Map<String, dynamic>> selectedResults,
    String mode = 'replace',  // 默认为替换模式
  }) async {
    try {
      final response = await _dio.post('/scrape/media/batch-import', data: {
        'media_id': mediaId,
        'selected_results': selectedResults,
        'mode': mode,
      });
      return BatchImportScrapeResponse.fromJson(_extractData(response.data));
    } catch (e) {
      throw ApiException('Failed to batch import scrape results: $e');
    }
  }
}

// Provider for ApiService
final apiServiceProvider = Provider<ApiService>((ref) {
  // 监听 API 基础地址的变�?
  final baseUrl = ref.watch(apiBaseUrlProvider);
  // 添加 /api 路径
  final fullApiUrl = getFullApiUrl(baseUrl);
  return ApiService(baseUrl: fullApiUrl);
});

// Exception class for API errors
class ApiException implements Exception {
  final String message;
  
  const ApiException(this.message);
  
  @override
  String toString() => 'ApiException: $message';
}

// Request/Response models
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  const PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJsonT,
  ) {
    // 处理统一�?ApiResponse 包装格式
    final data = json.containsKey('data') ? json['data'] as Map<String, dynamic> : json;
    
    return PaginatedResponse(
      items: (data['items'] as List).map(fromJsonT).toList(),
      total: data['total'],
      page: data['page'],
      pageSize: data['page_size'],
      totalPages: data['total_pages'],
      hasNext: data['has_next'],
      hasPrev: data['has_prev'],
    );
  }
}

/// 筛选选项
class FilterOptions {
  final List<String> mediaTypes;
  final List<String> studios;
  final List<String> series;
  final List<int> years;
  final List<String> genres;

  const FilterOptions({
    required this.mediaTypes,
    required this.studios,
    required this.series,
    required this.years,
    required this.genres,
  });

  factory FilterOptions.fromJson(Map<String, dynamic> json) {
    // 处理统一�?ApiResponse 包装格式
    final data = json.containsKey('data') ? json['data'] as Map<String, dynamic> : json;
    
    return FilterOptions(
      mediaTypes: (data['media_types'] as List?)?.cast<String>() ?? [],
      studios: (data['studios'] as List?)?.cast<String>() ?? [],
      series: (data['series'] as List?)?.cast<String>() ?? [],
      years: (data['years'] as List?)?.cast<int>() ?? [],
      genres: (data['genres'] as List?)?.cast<String>() ?? [],
    );
  }
}

class SearchResponse {
  final List<MediaItem> results;
  final int total;
  final String query;
  final int tookMs;

  const SearchResponse({
    required this.results,
    required this.total,
    required this.query,
    required this.tookMs,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    // 处理统一�?ApiResponse 包装格式
    final data = json.containsKey('data') ? json['data'] as Map<String, dynamic> : json;
    
    return SearchResponse(
      results: (data['results'] as List)
          .map((item) => MediaItem.fromJson(item))
          .toList(),
      total: data['total'],
      query: data['query'],
      tookMs: data['took_ms'],
    );
  }
}

class SearchSuggestion {
  final String text;
  final String type;
  final int count;

  const SearchSuggestion({
    required this.text,
    required this.type,
    required this.count,
  });

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) {
    return SearchSuggestion(
      text: json['text'],
      type: json['type_'],
      count: json['count'],
    );
  }
}

// Request models
class CreateMediaRequest {
  final String? id;  // 客户端提供的 UUID（可选）
  final String title;
  final String? originalTitle;
  final String? code;
  final MediaType? mediaType;
  final int? year;
  final String? releaseDate;
  final String? overview;
  final List<String>? genres;
  final double? rating;
  final int? runtime;
  final String? posterUrl;
  final List<String>? backdropUrl;  // 支持多个背景图
  final String? studio;
  final String? series;
  final List<PlayLink>? playLinks;
  final List<DownloadLink>? downloadLinks;
  final List<Person>? cast;
  final List<Person>? crew;

  const CreateMediaRequest({
    this.id,  // 添加 id 参数
    required this.title,
    this.originalTitle,
    this.code,
    this.mediaType,
    this.year,
    this.releaseDate,
    this.overview,
    this.genres,
    this.rating,
    this.runtime,
    this.posterUrl,
    this.backdropUrl,
    this.studio,
    this.series,
    this.playLinks,
    this.downloadLinks,
    this.cast,
    this.crew,
  });

  Map<String, dynamic> toJson() {
    // 辅助函数：将 MediaType 枚举转换为后端期望的字符串格�?
    String? mediaTypeToString(MediaType? type) {
      if (type == null) return null;
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
    
    return {
      if (id != null) 'id': id,  // 包含 id 字段（如果提供）
      'title': title,
      if (originalTitle != null) 'original_title': originalTitle,
      if (code != null) 'code': code,
      if (mediaType != null) 'media_type': mediaTypeToString(mediaType),
      if (year != null) 'year': year,
      if (releaseDate != null) 'release_date': releaseDate,
      if (overview != null) 'overview': overview,
      if (genres != null) 'genres': genres,
      if (rating != null) 'rating': rating,
      if (runtime != null) 'runtime': runtime,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (backdropUrl != null) 'backdrop_url': backdropUrl,
      if (studio != null) 'studio': studio,
      if (series != null) 'series': series,
      if (playLinks != null) 'play_links': playLinks!.map((e) => e.toJson()).toList(),
      if (downloadLinks != null) 'download_links': downloadLinks!.map((e) => e.toJson()).toList(),
      if (cast != null) 'cast': cast!.map((e) => e.toJson()).toList(),
      if (crew != null) 'crew': crew!.map((e) => e.toJson()).toList(),
    };
  }
}

class UpdateMediaRequest {
  final String? title;
  final String? originalTitle;
  final String? code;
  final String? mediaType;  // 注意：后端期望字符串类型
  final int? year;
  final String? releaseDate;
  final String? overview;
  final List<String>? genres;
  final double? rating;
  final int? runtime;
  final String? posterUrl;
  final List<String>? backdropUrl;  // 支持多个背景图
  final String? studio;
  final String? series;
  final List<PlayLink>? playLinks;
  final List<DownloadLink>? downloadLinks;
  final List<String>? previewUrls;
  final List<String>? previewVideoUrls;
  final String? coverVideoUrl;  // 封面视频 URL
  final List<Person>? cast;
  final List<Person>? crew;

  const UpdateMediaRequest({
    this.title,
    this.originalTitle,
    this.code,
    this.mediaType,
    this.year,
    this.releaseDate,
    this.overview,
    this.genres,
    this.rating,
    this.runtime,
    this.posterUrl,
    this.backdropUrl,
    this.studio,
    this.series,
    this.playLinks,
    this.downloadLinks,
    this.previewUrls,
    this.previewVideoUrls,
    this.coverVideoUrl,
    this.cast,
    this.crew,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    
    // 对于可能需要清空的字段，发送空字符串而不�?null
    // 后端会将空字符串转换�?None（数据库�?NULL�?
    
    // title 字段：必填，所以只在有值时包含
    if (title != null) json['title'] = title;
    
    // 可选字符串字段：总是包含，null 转为空字符串（允许清空）
    json['original_title'] = originalTitle ?? '';
    json['code'] = code ?? '';
    json['release_date'] = releaseDate ?? '';
    json['overview'] = overview ?? '';
    json['poster_url'] = posterUrl ?? '';
    json['cover_video_url'] = coverVideoUrl ?? '';  // 封面视频 URL
    json['studio'] = studio ?? '';
    json['series'] = series ?? '';
    
    // backdrop_url: 支持多个背景图（数组格式）
    // 如果为 null，发送空数组（允许清空）
    json['backdrop_url'] = backdropUrl ?? [];
    
    // 媒体类型：只在有值时包含
    if (mediaType != null) json['media_type'] = mediaType;
    
    // 数值字段：只在有值时包含（不能用空字符串�?
    if (year != null) json['year'] = year;
    if (rating != null) json['rating'] = rating;
    if (runtime != null) json['runtime'] = runtime;
    
    // 数组字段：只在有值时包含
    if (genres != null) json['genres'] = genres;
    if (playLinks != null) json['play_links'] = playLinks!.map((e) => e.toJson()).toList();
    if (downloadLinks != null) json['download_links'] = downloadLinks!.map((e) => e.toJson()).toList();
    if (previewUrls != null) json['preview_urls'] = previewUrls;
    if (previewVideoUrls != null) json['preview_video_urls'] = previewVideoUrls;
    if (cast != null) json['cast'] = cast!.map((e) => e.toJson()).toList();
    if (crew != null) json['crew'] = crew!.map((e) => e.toJson()).toList();
    
    return json;
  }
}

class AddToCollectionRequest {
  final String mediaId;
  final WatchStatus? watchStatus;

  const AddToCollectionRequest({
    required this.mediaId,
    this.watchStatus,
  });

  Map<String, dynamic> toJson() => {
    'media_id': mediaId,
    if (watchStatus != null) 'watch_status': watchStatus!.name,
  };
}

class UpdateCollectionRequest {
  final WatchStatus? watchStatus;
  final double? progress;
  final double? personalRating;
  final bool? isFavorite;
  final List<String>? userTags;
  final String? notes;

  const UpdateCollectionRequest({
    this.watchStatus,
    this.progress,
    this.personalRating,
    this.isFavorite,
    this.userTags,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    String? watchStatusValue;
    if (watchStatus != null) {
      // 使用�?Collection 模型相同的格�?
      switch (watchStatus!) {
        case WatchStatus.wantToWatch:
          watchStatusValue = 'WantToWatch';
          break;
        case WatchStatus.watching:
          watchStatusValue = 'Watching';
          break;
        case WatchStatus.completed:
          watchStatusValue = 'Completed';
          break;
        case WatchStatus.onHold:
          watchStatusValue = 'OnHold';
          break;
        case WatchStatus.dropped:
          watchStatusValue = 'Dropped';
          break;
      }
    }
    
    return {
      if (watchStatusValue != null) 'watch_status': watchStatusValue,
      if (progress != null) 'progress': progress,
      if (personalRating != null) 'personal_rating': personalRating,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (userTags != null) 'user_tags': userTags,
      if (notes != null) 'notes': notes,
    };
  }
}

class AdvancedSearchRequest {
  final String? query;
  final MediaType? mediaType;
  final int? yearFrom;
  final int? yearTo;
  final String? genre;
  final double? ratingMin;
  final double? ratingMax;
  final int? page;
  final String? source;
  final int? limit;
  final String? actorId;
  final String? studio;
  final String? series;

  const AdvancedSearchRequest({
    this.query,
    this.mediaType,
    this.yearFrom,
    this.yearTo,
    this.genre,
    this.ratingMin,
    this.ratingMax,
    this.page,
    this.source,
    this.limit,
    this.actorId,
    this.studio,
    this.series,
  });

  Map<String, dynamic> toJson() => {
    if (query != null) 'query': query,
    if (mediaType != null) 'media_type': mediaType!.name,
    if (yearFrom != null) 'year_from': yearFrom,
    if (yearTo != null) 'year_to': yearTo,
    if (genre != null) 'genre': genre,
    if (ratingMin != null) 'rating_min': ratingMin,
    if (ratingMax != null) 'rating_max': ratingMax,
    if (page != null) 'page': page,
    if (source != null) 'source': source,
    if (limit != null) 'limit': limit,
    if (actorId != null) 'actor_id': actorId,
    if (studio != null) 'studio': studio,
    if (series != null) 'series': series,
  };
}


// Batch operation models
class BatchImportItem {
  final int? tmdbId;
  final String mediaType;
  final String? title;

  const BatchImportItem({
    this.tmdbId,
    required this.mediaType,
    this.title,
  });

  Map<String, dynamic> toJson() => {
    if (tmdbId != null) 'tmdb_id': tmdbId,
    'media_type': mediaType,
    if (title != null) 'title': title,
  };
}

class BatchImportResponse {
  final int successCount;
  final int failedCount;
  final List<BatchImportResult> results;

  const BatchImportResponse({
    required this.successCount,
    required this.failedCount,
    required this.results,
  });

  factory BatchImportResponse.fromJson(Map<String, dynamic> json) {
    return BatchImportResponse(
      successCount: json['success_count'],
      failedCount: json['failed_count'],
      results: (json['results'] as List)
          .map((e) => BatchImportResult.fromJson(e))
          .toList(),
    );
  }
}

class BatchImportResult {
  final int index;
  final bool success;
  final String? mediaId;
  final String? error;

  const BatchImportResult({
    required this.index,
    required this.success,
    this.mediaId,
    this.error,
  });

  factory BatchImportResult.fromJson(Map<String, dynamic> json) {
    return BatchImportResult(
      index: json['index'],
      success: json['success'],
      mediaId: json['media_id'],
      error: json['error'],
    );
  }
}

enum BatchCollectionAction {
  add,
  remove,
  updateStatus,
  addTags,
  removeTags,
}

class BatchCollectionResponse {
  final int successCount;
  final int failedCount;
  final List<String> errors;

  const BatchCollectionResponse({
    required this.successCount,
    required this.failedCount,
    required this.errors,
  });

  factory BatchCollectionResponse.fromJson(Map<String, dynamic> json) {
    return BatchCollectionResponse(
      successCount: json['success_count'],
      failedCount: json['failed_count'],
      errors: List<String>.from(json['errors'] ?? []),
    );
  }
}

/// 批量删除响应
class BatchDeleteResponse {
  final int successCount;
  final int failedCount;
  final List<String> errors;

  const BatchDeleteResponse({
    required this.successCount,
    required this.failedCount,
    required this.errors,
  });

  factory BatchDeleteResponse.fromJson(Map<String, dynamic> json) {
    return BatchDeleteResponse(
      successCount: json['success_count'],
      failedCount: json['failed_count'],
      errors: List<String>.from(json['errors'] ?? []),
    );
  }
}

/// 批量编辑更新内容
class BatchEditUpdates {
  final String? mediaType;
  final List<String>? genres;
  final String? studio;
  final String? series;
  final List<String>? addTags;
  final List<String>? removeTags;

  const BatchEditUpdates({
    this.mediaType,
    this.genres,
    this.studio,
    this.series,
    this.addTags,
    this.removeTags,
  });

  Map<String, dynamic> toJson() => {
    if (mediaType != null) 'media_type': mediaType,
    if (genres != null) 'genres': genres,
    if (studio != null) 'studio': studio,
    if (series != null) 'series': series,
    if (addTags != null) 'add_tags': addTags,
    if (removeTags != null) 'remove_tags': removeTags,
  };
}

/// 批量编辑响应
class BatchEditResponse {
  final int successCount;
  final int failedCount;
  final List<String> errors;

  const BatchEditResponse({
    required this.successCount,
    required this.failedCount,
    required this.errors,
  });

  factory BatchEditResponse.fromJson(Map<String, dynamic> json) {
    return BatchEditResponse(
      successCount: json['success_count'],
      failedCount: json['failed_count'],
      errors: List<String>.from(json['errors'] ?? []),
    );
  }
}


// Export/Import models
class ExportActorItem {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? photoUrl;
  final String? posterUrl;
  final String? backdropUrl;
  final String? biography;
  final String? birthDate;
  final String? nationality;

  const ExportActorItem({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.photoUrl,
    this.posterUrl,
    this.backdropUrl,
    this.biography,
    this.birthDate,
    this.nationality,
  });

  factory ExportActorItem.fromJson(Map<String, dynamic> json) {
    return ExportActorItem(
      id: json['id'],
      name: json['name'],
      avatarUrl: json['avatar_url'],
      photoUrl: json['photo_url'],
      posterUrl: json['poster_url'],
      backdropUrl: json['backdrop_url'],
      biography: json['biography'],
      birthDate: json['birth_date'],
      nationality: json['nationality'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
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

class ExportActorMediaRelation {
  final String actorId;
  final String mediaId;
  final String? characterName;
  final String role;

  const ExportActorMediaRelation({
    required this.actorId,
    required this.mediaId,
    this.characterName,
    required this.role,
  });

  factory ExportActorMediaRelation.fromJson(Map<String, dynamic> json) {
    return ExportActorMediaRelation(
      actorId: json['actor_id'],
      mediaId: json['media_id'],
      characterName: json['character_name'],
      role: json['role'],
    );
  }

  Map<String, dynamic> toJson() => {
    'actor_id': actorId,
    'media_id': mediaId,
    if (characterName != null) 'character_name': characterName,
    'role': role,
  };
}

class ExportDataResponse {
  final String version;
  final String exportedAt;
  final List<MediaItem> media;
  final List<Collection> collections;
  final List<ExportActorItem> actors;
  final List<ExportActorMediaRelation> actorMediaRelations;

  const ExportDataResponse({
    required this.version,
    required this.exportedAt,
    required this.media,
    required this.collections,
    required this.actors,
    required this.actorMediaRelations,
  });

  factory ExportDataResponse.fromJson(Map<String, dynamic> json) {
    return ExportDataResponse(
      version: json['version'],
      exportedAt: json['exported_at'],
      media: (json['media'] as List)
          .map((e) => MediaItem.fromJson(e))
          .toList(),
      collections: (json['collections'] as List)
          .map((e) => Collection.fromJson(e))
          .toList(),
      actors: (json['actors'] as List? ?? [])
          .map((e) => ExportActorItem.fromJson(e))
          .toList(),
      actorMediaRelations: (json['actor_media_relations'] as List? ?? [])
          .map((e) => ExportActorMediaRelation.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'exported_at': exportedAt,
    'media': media.map((e) => e.toJson()).toList(),
    'collections': collections.map((e) => e.toJson()).toList(),
    'actors': actors.map((e) => e.toJson()).toList(),
    'actor_media_relations': actorMediaRelations.map((e) => e.toJson()).toList(),
  };
}

class ImportActorItem {
  final String? id;
  final String name;
  final String? avatarUrl;
  final String? photoUrl;
  final String? posterUrl;
  final String? backdropUrl;
  final String? biography;
  final String? birthDate;
  final String? nationality;

  const ImportActorItem({
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

  factory ImportActorItem.fromJson(Map<String, dynamic> json) {
    return ImportActorItem(
      id: json['id'],
      name: json['name'] ?? '',
      avatarUrl: json['avatar_url'],
      photoUrl: json['photo_url'],
      posterUrl: json['poster_url'],
      backdropUrl: json['backdrop_url'],
      biography: json['biography'],
      birthDate: json['birth_date'],
      nationality: json['nationality'],
    );
  }
}

class ImportActorMediaRelation {
  final String? actorId;
  final String? actorName;
  final String? mediaId;
  final String? mediaTitle;
  final String? characterName;
  final String? role;

  const ImportActorMediaRelation({
    this.actorId,
    this.actorName,
    this.mediaId,
    this.mediaTitle,
    this.characterName,
    this.role,
  });

  Map<String, dynamic> toJson() => {
    if (actorId != null) 'actor_id': actorId,
    if (actorName != null) 'actor_name': actorName,
    if (mediaId != null) 'media_id': mediaId,
    if (mediaTitle != null) 'media_title': mediaTitle,
    if (characterName != null) 'character_name': characterName,
    if (role != null) 'role': role,
  };

  factory ImportActorMediaRelation.fromJson(Map<String, dynamic> json) {
    return ImportActorMediaRelation(
      actorId: json['actor_id'],
      actorName: json['actor_name'],
      mediaId: json['media_id'],
      mediaTitle: json['media_title'],
      characterName: json['character_name'],
      role: json['role'],
    );
  }
}

class ImportDataRequest {
  final String version;
  final List<ImportMediaItem> media;
  final List<ImportCollectionItem>? collections;
  final List<ImportActorItem>? actors;
  final List<ImportActorMediaRelation>? actorMediaRelations;

  const ImportDataRequest({
    required this.version,
    required this.media,
    this.collections,
    this.actors,
    this.actorMediaRelations,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'media': media.map((e) => e.toJson()).toList(),
    if (collections != null) 'collections': collections!.map((e) => e.toJson()).toList(),
    if (actors != null) 'actors': actors!.map((e) => e.toJson()).toList(),
    if (actorMediaRelations != null) 'actor_media_relations': actorMediaRelations!.map((e) => e.toJson()).toList(),
  };
}

class ImportMediaItem {
  final String title;
  final String? originalTitle;
  final int? year;
  final String mediaType;
  final List<String>? genres;
  final double? rating;
  final String? overview;
  final String? posterUrl;
  final List<String>? backdropUrl;  // 支持多个背景图
  final List<ImportPlayLink>? playLinks;
  final List<ImportDownloadLink>? downloadLinks;
  final List<String>? previewUrls;
  final List<String>? previewVideoUrls;
  final String? studio;
  final String? series;

  const ImportMediaItem({
    required this.title,
    this.originalTitle,
    this.year,
    required this.mediaType,
    this.genres,
    this.rating,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.playLinks,
    this.downloadLinks,
    this.previewUrls,
    this.previewVideoUrls,
    this.studio,
    this.series,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    if (originalTitle != null) 'original_title': originalTitle,
    if (year != null) 'year': year,
    'media_type': mediaType,
    if (genres != null) 'genres': genres,
    if (rating != null) 'rating': rating,
    if (overview != null) 'overview': overview,
    if (posterUrl != null) 'poster_url': posterUrl,
    if (backdropUrl != null) 'backdrop_url': backdropUrl,
    if (playLinks != null) 'play_links': playLinks!.map((e) => e.toJson()).toList(),
    if (downloadLinks != null) 'download_links': downloadLinks!.map((e) => e.toJson()).toList(),
    if (previewUrls != null) 'preview_urls': previewUrls,
    if (previewVideoUrls != null) 'preview_video_urls': previewVideoUrls,
    if (studio != null) 'studio': studio,
    if (series != null) 'series': series,
  };
}

/// 导入用播放链�?
class ImportPlayLink {
  final String name;
  final String url;
  final String? quality;

  const ImportPlayLink({
    required this.name,
    required this.url,
    this.quality,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    if (quality != null) 'quality': quality,
  };

  factory ImportPlayLink.fromJson(Map<String, dynamic> json) {
    return ImportPlayLink(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      quality: json['quality'],
    );
  }
}

/// 导入用下载链�?
class ImportDownloadLink {
  final String name;
  final String url;
  final String linkType;
  final String? size;
  final String? password;

  const ImportDownloadLink({
    required this.name,
    required this.url,
    required this.linkType,
    this.size,
    this.password,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'link_type': linkType,
    if (size != null) 'size': size,
    if (password != null) 'password': password,
  };

  factory ImportDownloadLink.fromJson(Map<String, dynamic> json) {
    return ImportDownloadLink(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      linkType: json['link_type'] ?? 'other',
      size: json['size'],
      password: json['password'],
    );
  }
}

class ImportCollectionItem {
  final String mediaTitle;
  final String watchStatus;
  final double? personalRating;
  final String? notes;
  final bool? isFavorite;
  final List<String>? userTags;

  const ImportCollectionItem({
    required this.mediaTitle,
    required this.watchStatus,
    this.personalRating,
    this.notes,
    this.isFavorite,
    this.userTags,
  });

  Map<String, dynamic> toJson() => {
    'media_title': mediaTitle,
    'watch_status': watchStatus,
    if (personalRating != null) 'personal_rating': personalRating,
    if (notes != null) 'notes': notes,
    if (isFavorite != null) 'is_favorite': isFavorite,
    if (userTags != null) 'user_tags': userTags,
  };
}

class ImportDataResponse {
  final int mediaImported;
  final int mediaFailed;
  final int collectionsImported;
  final int collectionsFailed;
  final int actorsImported;
  final int actorsFailed;
  final int relationsImported;
  final int relationsFailed;
  final List<String> errors;

  const ImportDataResponse({
    required this.mediaImported,
    required this.mediaFailed,
    required this.collectionsImported,
    required this.collectionsFailed,
    required this.actorsImported,
    required this.actorsFailed,
    required this.relationsImported,
    required this.relationsFailed,
    required this.errors,
  });

  factory ImportDataResponse.fromJson(Map<String, dynamic> json) {
    return ImportDataResponse(
      mediaImported: json['media_imported'],
      mediaFailed: json['media_failed'],
      collectionsImported: json['collections_imported'],
      collectionsFailed: json['collections_failed'],
      actorsImported: json['actors_imported'] ?? 0,
      actorsFailed: json['actors_failed'] ?? 0,
      relationsImported: json['relations_imported'] ?? 0,
      relationsFailed: json['relations_failed'] ?? 0,
      errors: List<String>.from(json['errors'] ?? []),
    );
  }
}

// File scan models

class ScannedFile {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String? parsedCode;      // JAV 番号（如 IPX-177）
  final String? parsedTitle;     // 标题
  final int? parsedYear;         // 年份
  final String? parsedSeries;    // 系列名（欧美，如 Straplez）
  final String? parsedDate;      // 发布日期（欧美，如 2026-01-23）

  const ScannedFile({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.parsedCode,
    this.parsedTitle,
    this.parsedYear,
    this.parsedSeries,
    this.parsedDate,
  });

  Map<String, dynamic> toJson() => {
    'file_path': filePath,
    'file_name': fileName,
    'file_size': fileSize,
    if (parsedCode != null) 'parsed_code': parsedCode,
    if (parsedTitle != null) 'parsed_title': parsedTitle,
    if (parsedYear != null) 'parsed_year': parsedYear,
    if (parsedSeries != null) 'parsed_series': parsedSeries,
    if (parsedDate != null) 'parsed_date': parsedDate,
  };

  factory ScannedFile.fromJson(Map<String, dynamic> json) {
    try {
      return ScannedFile(
        filePath: json['file_path']?.toString() ?? '',
        fileName: json['file_name']?.toString() ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
        parsedCode: json['parsed_code']?.toString(),
        parsedTitle: json['parsed_title']?.toString(),
        parsedYear: (json['parsed_year'] as num?)?.toInt(),
        parsedSeries: json['parsed_series']?.toString(),
        parsedDate: json['parsed_date']?.toString(),
      );
    } catch (e) {
      throw Exception('Failed to parse ScannedFile from JSON: $json. Error: $e');
    }
  }
}

class ScanResponse {
  final bool success;
  final int totalFiles;
  final List<ScannedFile> scannedFiles;
  final List<FileGroup> fileGroups;  // 文件分组
  final String message;

  const ScanResponse({
    required this.success,
    required this.totalFiles,
    required this.scannedFiles,
    this.fileGroups = const [],  // 默认空列表，向后兼容
    required this.message,
  });

  factory ScanResponse.fromJson(Map<String, dynamic> json) {
    try {
      return ScanResponse(
        success: json['success'] == true,
        totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
        scannedFiles: (json['scanned_files'] as List?)
            ?.map((f) => ScannedFile.fromJson(f as Map<String, dynamic>))
            .toList() ?? [],
        fileGroups: (json['file_groups'] as List?)
            ?.map((g) => FileGroup.fromJson(g as Map<String, dynamic>))
            .toList() ?? [],
        message: json['message']?.toString() ?? '',
      );
    } catch (e) {
      throw Exception('Failed to parse ScanResponse from JSON: $json. Error: $e');
    }
  }
}

// 文件分组模型
class FileGroup {
  final String baseName;
  final List<ScannedFile> files;
  final int totalSize;

  const FileGroup({
    required this.baseName,
    required this.files,
    required this.totalSize,
  });

  factory FileGroup.fromJson(Map<String, dynamic> json) {
    return FileGroup(
      baseName: json['base_name']?.toString() ?? '',
      files: (json['files'] as List?)
          ?.map((f) {
            // 后端返回的是 ScannedFileWithPart 结构：{ scanned_file: {...}, part_info: {...} }
            final fileData = f as Map<String, dynamic>;
            if (fileData.containsKey('scanned_file')) {
              // 提取 scanned_file 部分
              return ScannedFile.fromJson(fileData['scanned_file'] as Map<String, dynamic>);
            } else {
              // 向后兼容：如果直接是 ScannedFile 格式
              return ScannedFile.fromJson(fileData);
            }
          })
          .toList() ?? [],
      totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'base_name': baseName,
    'files': files.map((f) {
      // 后端期望 ScannedFileWithPart 格式：{ scanned_file: {...}, part_info: null }
      return {
        'scanned_file': f.toJson(),
        'part_info': null,  // 前端没有 part_info，发�?null
      };
    }).toList(),
    'total_size': totalSize,
  };

  String get formattedTotalSize {
    return MediaFile.formatFileSize(totalSize);
  }
}

class MatchResult {
  final ScannedFile scannedFile;
  final String matchType; // 'exact', 'fuzzy', 'none'
  final MediaItem? matchedMedia;
  final double confidence;
  final List<MediaItem> suggestions;

  const MatchResult({
    required this.scannedFile,
    required this.matchType,
    this.matchedMedia,
    required this.confidence,
    required this.suggestions,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    try {
      return MatchResult(
        scannedFile: ScannedFile.fromJson(json['scanned_file'] as Map<String, dynamic>),
        matchType: json['match_type']?.toString() ?? 'none',
        matchedMedia: json['matched_media'] != null
            ? MediaItem.fromJson(json['matched_media'] as Map<String, dynamic>)
            : null,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        suggestions: (json['suggestions'] as List?)
            ?.map((m) => MediaItem.fromJson(m as Map<String, dynamic>))
            .toList() ?? [],
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error parsing MatchResult: $e');
        debugPrint('JSON data: $json');
        debugPrint('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }
}

class MatchResponse {
  final bool success;
  final List<MatchResult> matchResults;
  final List<GroupMatchResult> groupMatchResults;  // 文件组匹配结�?
  final int exactMatches;
  final int fuzzyMatches;
  final int noMatches;

  const MatchResponse({
    required this.success,
    required this.matchResults,
    this.groupMatchResults = const [],  // 默认空列表，向后兼容
    required this.exactMatches,
    required this.fuzzyMatches,
    required this.noMatches,
  });

  factory MatchResponse.fromJson(Map<String, dynamic> json) {
    return MatchResponse(
      success: json['success'] == true,
      matchResults: (json['match_results'] as List?)
          ?.map((r) => MatchResult.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
      groupMatchResults: (json['group_match_results'] as List?)
          ?.map((r) => GroupMatchResult.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
      exactMatches: (json['exact_matches'] as num?)?.toInt() ?? 0,
      fuzzyMatches: (json['fuzzy_matches'] as num?)?.toInt() ?? 0,
      noMatches: (json['no_matches'] as num?)?.toInt() ?? 0,
    );
  }
}

// 文件组匹配结�?
class GroupMatchResult {
  final FileGroup fileGroup;
  final String matchType;  // 'exact', 'fuzzy', 'none'
  final MediaItem? matchedMedia;
  final double confidence;
  final List<MediaItem> suggestions;

  const GroupMatchResult({
    required this.fileGroup,
    required this.matchType,
    this.matchedMedia,
    required this.confidence,
    required this.suggestions,
  });

  factory GroupMatchResult.fromJson(Map<String, dynamic> json) {
    try {
      return GroupMatchResult(
        fileGroup: FileGroup.fromJson(json['file_group'] as Map<String, dynamic>),
        matchType: json['match_type']?.toString() ?? 'none',
        matchedMedia: json['matched_media'] != null
            ? MediaItem.fromJson(json['matched_media'] as Map<String, dynamic>)
            : null,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        suggestions: (json['suggestions'] as List?)
            ?.map((m) => MediaItem.fromJson(m as Map<String, dynamic>))
            .toList() ?? [],
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error parsing GroupMatchResult: $e');
        debugPrint('JSON data: $json');
        debugPrint('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }
}

class ConfirmMatch {
  final String mediaId;
  final List<FileInfo> files;  // 支持多个文件

  const ConfirmMatch({
    required this.mediaId,
    required this.files,
  });

  // 向后兼容的构造函数（单文件）
  factory ConfirmMatch.single({
    required String filePath,
    required String mediaId,
    int? fileSize,
  }) {
    return ConfirmMatch(
      mediaId: mediaId,
      files: [
        FileInfo(
          filePath: filePath,
          fileSize: fileSize ?? 0,
          partNumber: null,
          partLabel: null,
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'media_id': mediaId,
    'files': files.map((f) => f.toJson()).toList(),
  };
}

class FileInfo {
  final String filePath;
  final int fileSize;
  final int? partNumber;
  final String? partLabel;

  const FileInfo({
    required this.filePath,
    required this.fileSize,
    this.partNumber,
    this.partLabel,
  });

  Map<String, dynamic> toJson() => {
    'file_path': filePath,
    'file_size': fileSize,
    if (partNumber != null) 'part_number': partNumber,
    if (partLabel != null) 'part_label': partLabel,
  };
}

class ConfirmMatchResponse {
  final bool success;
  final int updatedCount;
  final String message;

  const ConfirmMatchResponse({
    required this.success,
    required this.updatedCount,
    required this.message,
  });

  factory ConfirmMatchResponse.fromJson(Map<String, dynamic> json) {
    return ConfirmMatchResponse(
      success: json['success'],
      updatedCount: json['updated_count'],
      message: json['message'],
    );
  }
}

class AutoScrapeResponse {
  final bool success;
  final int scrapedCount;
  final int failedCount;
  final List<ScrapeFileResult> results;
  final String message;

  const AutoScrapeResponse({
    required this.success,
    required this.scrapedCount,
    required this.failedCount,
    required this.results,
    required this.message,
  });

  factory AutoScrapeResponse.fromJson(Map<String, dynamic> json) {
    return AutoScrapeResponse(
      success: json['success'],
      scrapedCount: json['scraped_count'],
      failedCount: json['failed_count'],
      results: (json['results'] as List)
          .map((r) => ScrapeFileResult.fromJson(r))
          .toList(),
      message: json['message'],
    );
  }
}

class ScrapeFileResult {
  final String filePath;
  final String fileName;
  final bool success;
  final String? mediaId;
  final String? error;

  const ScrapeFileResult({
    required this.filePath,
    required this.fileName,
    required this.success,
    this.mediaId,
    this.error,
  });

  factory ScrapeFileResult.fromJson(Map<String, dynamic> json) {
    return ScrapeFileResult(
      filePath: json['file_path'],
      fileName: json['file_name'],
      success: json['success'],
      mediaId: json['media_id'],
      error: json['error'],
    );
  }
}

class IgnoreFileResponse {
  final bool success;
  final String message;

  const IgnoreFileResponse({
    required this.success,
    required this.message,
  });

  factory IgnoreFileResponse.fromJson(Map<String, dynamic> json) {
    return IgnoreFileResponse(
      success: json['success'],
      message: json['message'],
    );
  }
}

class IgnoredFile {
  final String id;
  final String filePath;
  final String fileName;
  final String ignoredAt;
  final String? reason;

  const IgnoredFile({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.ignoredAt,
    this.reason,
  });

  factory IgnoredFile.fromJson(Map<String, dynamic> json) {
    return IgnoredFile(
      id: json['id'],
      filePath: json['file_path'],
      fileName: json['file_name'],
      ignoredAt: json['ignored_at'],
      reason: json['reason'],
    );
  }
}

class GetIgnoredFilesResponse {
  final bool success;
  final List<IgnoredFile> files;

  const GetIgnoredFilesResponse({
    required this.success,
    required this.files,
  });

  factory GetIgnoredFilesResponse.fromJson(Map<String, dynamic> json) {
    return GetIgnoredFilesResponse(
      success: json['success'],
      files: (json['files'] as List)
          .map((f) => IgnoredFile.fromJson(f))
          .toList(),
    );
  }
}

// Multi-part video support models

class GetMediaFilesResponse {
  final bool success;
  final List<MediaFile> files;
  final int totalSize;

  const GetMediaFilesResponse({
    required this.success,
    required this.files,
    required this.totalSize,
  });

  factory GetMediaFilesResponse.fromJson(Map<String, dynamic> json) {
    return GetMediaFilesResponse(
      success: json['success'] == true,
      files: (json['files'] as List?)
          ?.map((f) => MediaFile.fromJson(f as Map<String, dynamic>))
          .toList() ?? [],
      totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
    );
  }
}


// Media scrape progress model

class MediaScrapeProgressResponse {
  final String status;
  final String? message;
  final int current;
  final int total;
  final String? currentItem;
  final String itemStatus;
  final int successCount;
  final int failedCount;
  final bool completed;

  const MediaScrapeProgressResponse({
    required this.status,
    this.message,
    required this.current,
    required this.total,
    this.currentItem,
    required this.itemStatus,
    required this.successCount,
    required this.failedCount,
    required this.completed,
  });

  factory MediaScrapeProgressResponse.fromJson(Map<String, dynamic> json) {
    return MediaScrapeProgressResponse(
      status: json['status'] ?? 'pending',
      message: json['message'],
      current: json['current'] ?? 0,
      total: json['total'] ?? 0,
      currentItem: json['current_item'],
      itemStatus: json['item_status'] ?? 'pending',
      successCount: json['success_count'] ?? 0,
      failedCount: json['failed_count'] ?? 0,
      completed: json['completed'] == true,
    );
  }
}

// Multiple results scrape models

/// 刮削媒体的统一响应类型
/// 可能是单个结果（已入库）或多个结果（待选择）
class ScrapeMediaResponse {
  final MediaItem? singleResult;
  final ScrapeMultipleResponse? multipleResults;
  
  bool get isSingle => singleResult != null;
  bool get isMultiple => multipleResults != null;
  
  const ScrapeMediaResponse._({
    this.singleResult,
    this.multipleResults,
  });
  
  factory ScrapeMediaResponse.single(MediaItem media) {
    return ScrapeMediaResponse._(singleResult: media);
  }
  
  factory ScrapeMediaResponse.multiple(ScrapeMultipleResponse response) {
    return ScrapeMediaResponse._(multipleResults: response);
  }
}

class ScrapeMultipleResponse {
  final bool success;
  final String mode;  // 'single' or 'multiple'
  final List<Map<String, dynamic>> results;
  final String? message;

  const ScrapeMultipleResponse({
    required this.success,
    required this.mode,
    required this.results,
    this.message,
  });

  factory ScrapeMultipleResponse.fromJson(Map<String, dynamic> json) {
    return ScrapeMultipleResponse(
      success: json['success'] == true,
      mode: json['mode'] ?? 'single',
      results: (json['results'] as List?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ?? [],
      message: json['message'],
    );
  }
}

class BatchImportScrapeResponse {
  final int importedCount;
  final int failedCount;
  final List<ImportScrapeResult> results;

  const BatchImportScrapeResponse({
    required this.importedCount,
    required this.failedCount,
    required this.results,
  });

  factory BatchImportScrapeResponse.fromJson(Map<String, dynamic> json) {
    return BatchImportScrapeResponse(
      importedCount: json['imported_count'] ?? 0,
      failedCount: json['failed_count'] ?? 0,
      results: (json['results'] as List?)
          ?.map((e) => ImportScrapeResult.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

class ImportScrapeResult {
  final bool success;
  final String? mediaId;
  final String? title;
  final String? error;

  const ImportScrapeResult({
    required this.success,
    this.mediaId,
    this.title,
    this.error,
  });

  factory ImportScrapeResult.fromJson(Map<String, dynamic> json) {
    return ImportScrapeResult(
      success: json['success'] == true,
      mediaId: json['media_id'],
      title: json['title'],
      error: json['error'],
    );
  }
}

