import 'package:dio/dio.dart';
import '../models/cache_config.dart';

/// 图片缓存管理 API 服务
class ImageCacheApiService {
  final Dio _dio;

  ImageCacheApiService({required String baseUrl}) : _dio = Dio() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  /// 获取缓存配置
  Future<CacheConfig> getCacheConfig() async {
    try {
      final response = await _dio.get('/api/cache/config');
      // 后端返回格式: { "success": true, "data": {...} }
      final data = response.data['data'];
      if (data == null) {
        throw Exception('API 返回数据为空');
      }
      return CacheConfig.fromJson(data);
    } catch (e) {
      throw Exception('获取缓存配置失败: $e');
    }
  }

  /// 更新缓存配置
  Future<void> updateCacheConfig(CacheConfig config) async {
    try {
      await _dio.put(
        '/api/cache/config',
        data: config.toJson(),
      );
    } catch (e) {
      throw Exception('更新缓存配置失败: $e');
    }
  }

  /// 更新单个刮削器配置
  Future<void> updateScraperConfig(
    String scraperName,
    ScraperCacheConfig config,
  ) async {
    try {
      await _dio.put(
        '/api/cache/config/scraper/$scraperName',
        data: config.toJson(),
      );
    } catch (e) {
      throw Exception('更新刮削器配置失败: $e');
    }
  }

  /// 查询缓存统计
  Future<CacheStats> getCacheStats() async {
    try {
      final response = await _dio.get('/api/cache/stats');
      return CacheStats.fromJson(response.data);
    } catch (e) {
      throw Exception('获取缓存统计失败: $e');
    }
  }

  /// 清理指定媒体缓存
  Future<void> clearMediaCache(String mediaId) async {
    try {
      await _dio.delete('/api/media/$mediaId/cache');
    } catch (e) {
      throw Exception('清理媒体缓存失败: $e');
    }
  }

  /// 清理所有缓存
  Future<void> clearAllCache() async {
    try {
      await _dio.delete('/api/cache/all');
    } catch (e) {
      throw Exception('清理所有缓存失败: $e');
    }
  }

  /// 清理孤立缓存
  Future<void> clearOrphanedCache() async {
    try {
      await _dio.delete('/api/cache/orphaned');
    } catch (e) {
      throw Exception('清理孤立缓存失败: $e');
    }
  }

  /// 获取所有插件列表
  Future<List<Map<String, dynamic>>> getPlugins() async {
    try {
      final response = await _dio.get('/api/scrape/plugins');
      // API 返回格式: { "success": true, "data": [...] }
      final data = response.data['data'];
      if (data == null) {
        return [];
      }
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      throw Exception('获取插件列表失败: $e');
    }
  }
}
