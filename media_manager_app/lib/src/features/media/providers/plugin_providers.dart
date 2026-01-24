import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/plugin_info.dart';
import '../../../core/services/api_service.dart';

/// 获取插件列表的 FutureProvider
final pluginsProvider = FutureProvider<List<PluginInfo>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  try {
    final plugins = await apiService.getPlugins();
    if (kDebugMode) {
      debugPrint('🔌 获取到 ${plugins.length} 个插件');
      for (var plugin in plugins) {
        debugPrint('  - ${plugin.name} (${plugin.id})');
      }
    }
    return plugins;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('🔌 获取插件失败: $e');
    }
    rethrow;
  }
});

/// 插件是否可用的派生 Provider
/// 注意：这个 Provider 会在插件加载完成后才返回 true
/// 在加载过程中或加载失败时返回 false
final pluginsAvailableProvider = Provider<bool>((ref) {
  final pluginsAsync = ref.watch(pluginsProvider);
  return pluginsAsync.when(
    data: (plugins) => plugins.isNotEmpty,
    loading: () => false,  // 加载中返回 false
    error: (_, __) => false,  // 错误时返回 false
  );
});

/// 已安装插件ID集合的 Provider
/// 用于快速检查某个插件是否已安装
final installedPluginIdsProvider = Provider<Set<String>>((ref) {
  final pluginsAsync = ref.watch(pluginsProvider);
  return pluginsAsync.when(
    data: (plugins) => plugins.map((p) => p.id).toSet(),
    loading: () => {},
    error: (_, __) => {},
  );
});

/// 检查特定插件是否已安装
/// 用法: ref.watch(isPluginInstalledProvider('media_scraper'))
final isPluginInstalledProvider = Provider.family<bool, String>((ref, pluginId) {
  final installedIds = ref.watch(installedPluginIdsProvider);
  return installedIds.contains(pluginId);
});

