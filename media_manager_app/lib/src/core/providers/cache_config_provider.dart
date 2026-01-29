import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cache_config.dart';
import '../services/image_cache_api_service.dart';
import '../services/cache_service.dart'; // 导入 Debouncer
import '../config/app_config.dart';

/// 缓存配置 Provider
final cacheConfigProvider = StateNotifierProvider<CacheConfigNotifier, AsyncValue<CacheConfig>>((ref) {
  final apiService = ref.watch(imageCacheApiServiceProvider);
  return CacheConfigNotifier(apiService);
});

/// 缓存配置 Notifier
class CacheConfigNotifier extends StateNotifier<AsyncValue<CacheConfig>> {
  final ImageCacheApiService _apiService;
  final Debouncer _debouncer = Debouncer(delay: const Duration(milliseconds: 300));

  CacheConfigNotifier(this._apiService) : super(const AsyncValue.loading()) {
    loadConfig();
  }

  @override
  void dispose() {
    _debouncer.cancel();
    super.dispose();
  }

  /// 加载配置
  Future<void> loadConfig() async {
    print('[CacheConfigProvider] 开始加载配置...');
    state = const AsyncValue.loading();
    try {
      final config = await _apiService.getCacheConfig();
      print('[CacheConfigProvider] 配置加载成功，刮削器数量: ${config.scrapers.length}');
      state = AsyncValue.data(config);
    } catch (e, stack) {
      print('[CacheConfigProvider] 配置加载失败: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// 更新全局缓存开关（带防抖）
  Future<void> updateGlobalCacheEnabled(bool enabled) async {
    final currentConfig = state.value;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(globalCacheEnabled: enabled);
    
    // 乐观更新
    state = AsyncValue.data(newConfig);
    
    // 使用防抖延迟 API 调用
    _debouncer.run(() async {
      try {
        await _apiService.updateCacheConfig(newConfig);
      } catch (e, stack) {
        // 回滚
        state = AsyncValue.data(currentConfig);
        state = AsyncValue.error(e, stack);
      }
    });
  }

  /// 更新刮削器缓存开关（带防抖）
  Future<void> updateScraperCacheEnabled(String scraperName, bool enabled) async {
    final currentConfig = state.value;
    if (currentConfig == null) return;

    final scraperConfig = currentConfig.scrapers[scraperName];
    if (scraperConfig == null) return;

    final newScraperConfig = scraperConfig.copyWith(cacheEnabled: enabled);
    final newScrapers = Map<String, ScraperCacheConfig>.from(currentConfig.scrapers);
    newScrapers[scraperName] = newScraperConfig;
    
    final newConfig = currentConfig.copyWith(scrapers: newScrapers);
    
    // 乐观更新
    state = AsyncValue.data(newConfig);
    
    // 使用防抖延迟 API 调用
    _debouncer.run(() async {
      try {
        await _apiService.updateScraperConfig(scraperName, newScraperConfig);
      } catch (e, stack) {
        // 回滚
        state = AsyncValue.data(currentConfig);
        state = AsyncValue.error(e, stack);
      }
    });
  }

  /// 更新刮削器缓存字段（带防抖）
  Future<void> updateScraperCacheFields(
    String scraperName,
    List<CacheField> fields,
  ) async {
    final currentConfig = state.value;
    if (currentConfig == null) return;

    final scraperConfig = currentConfig.scrapers[scraperName];
    if (scraperConfig == null) return;

    final newScraperConfig = scraperConfig.copyWith(cacheFields: fields);
    final newScrapers = Map<String, ScraperCacheConfig>.from(currentConfig.scrapers);
    newScrapers[scraperName] = newScraperConfig;
    
    final newConfig = currentConfig.copyWith(scrapers: newScrapers);
    
    // 乐观更新
    state = AsyncValue.data(newConfig);
    
    // 使用防抖延迟 API 调用
    _debouncer.run(() async {
      try {
        await _apiService.updateScraperConfig(scraperName, newScraperConfig);
      } catch (e, stack) {
        // 回滚
        state = AsyncValue.data(currentConfig);
        state = AsyncValue.error(e, stack);
      }
    });
  }

  /// 刷新配置
  Future<void> refresh() => loadConfig();
}

/// 缓存统计 Provider
final cacheStatsProvider = StateNotifierProvider<CacheStatsNotifier, AsyncValue<CacheStats>>((ref) {
  final apiService = ref.watch(imageCacheApiServiceProvider);
  return CacheStatsNotifier(apiService);
});

/// 缓存统计 Notifier
class CacheStatsNotifier extends StateNotifier<AsyncValue<CacheStats>> {
  final ImageCacheApiService _apiService;

  CacheStatsNotifier(this._apiService) : super(const AsyncValue.loading()) {
    loadStats();
  }

  /// 加载统计
  Future<void> loadStats() async {
    state = const AsyncValue.loading();
    try {
      final stats = await _apiService.getCacheStats();
      state = AsyncValue.data(stats);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 刷新统计
  Future<void> refresh() => loadStats();

  /// 清理所有缓存
  Future<void> clearAllCache() async {
    try {
      await _apiService.clearAllCache();
      await loadStats(); // 重新加载统计
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 清理孤立缓存
  Future<void> clearOrphanedCache() async {
    try {
      await _apiService.clearOrphanedCache();
      await loadStats(); // 重新加载统计
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

/// Image Cache API Service Provider
final imageCacheApiServiceProvider = Provider<ImageCacheApiService>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  return ImageCacheApiService(baseUrl: baseUrl);
});
