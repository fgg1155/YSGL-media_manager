import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/cache_config_provider.dart';
import '../../../../core/models/cache_config.dart';
import '../../../../core/utils/snackbar_utils.dart';

/// 缓存管理设置页面
class CacheSettingsScreen extends ConsumerWidget {
  const CacheSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(cacheConfigProvider);
    final statsAsync = ref.watch(cacheStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(cacheConfigProvider.notifier).refresh();
              ref.read(cacheStatsProvider.notifier).refresh();
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(cacheConfigProvider.notifier).refresh();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (config) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 缓存统计卡片
            _buildStatsCard(context, ref, statsAsync),
            const SizedBox(height: 16),
            
            // 全局缓存开关
            _buildGlobalCacheSwitch(context, ref, config),
            const SizedBox(height: 24),
            
            // 刮削器列表
            _buildScrapersList(context, ref, config),
          ],
        ),
      ),
    );
  }

  /// 构建缓存统计卡片
  Widget _buildStatsCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<CacheStats> statsAsync,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, size: 20),
                const SizedBox(width: 8),
                Text(
                  '缓存统计',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            statsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Text(
                '加载统计失败: $error',
                style: const TextStyle(color: Colors.red),
              ),
              data: (stats) => Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('总缓存大小'),
                      Text(
                        stats.formattedTotalSize,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('总文件数'),
                      Text(
                        '${stats.totalFiles} 个',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showClearCacheDialog(context, ref),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清理所有缓存'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _clearOrphanedCache(context, ref),
                          icon: const Icon(Icons.cleaning_services),
                          label: const Text('清理孤立文件'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建全局缓存开关
  Widget _buildGlobalCacheSwitch(
    BuildContext context,
    WidgetRef ref,
    CacheConfig config,
  ) {
    return Card(
      child: SwitchListTile(
        title: const Text('全局缓存开关'),
        subtitle: const Text('开启后，所有刮削器的图片都会自动缓存到本地'),
        value: config.globalCacheEnabled,
        onChanged: (value) {
          ref.read(cacheConfigProvider.notifier).updateGlobalCacheEnabled(value);
        },
      ),
    );
  }

  /// 构建刮削器列表
  Widget _buildScrapersList(
    BuildContext context,
    WidgetRef ref,
    CacheConfig config,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '刮削器配置',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ElevatedButton.icon(
              onPressed: () => _loadAllScrapers(context, ref),
              icon: const Icon(Icons.download),
              label: const Text('加载刮削器'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.scrapers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      '暂无刮削器配置',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '点击上方"加载刮削器"按钮，自动加载所有可用的刮削器',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...config.scrapers.entries.map((entry) {
            return _buildScraperCard(context, ref, entry.key, entry.value);
          }),
      ],
    );
  }

  /// 加载所有刮削器
  void _loadAllScrapers(BuildContext context, WidgetRef ref) async {
    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在加载刮削器...'),
            ],
          ),
        ),
      );

      final apiService = ref.read(imageCacheApiServiceProvider);
      
      // 1. 获取所有插件
      print('开始获取插件列表...');
      final plugins = await apiService.getPlugins();
      print('获取到 ${plugins.length} 个插件');
      
      // 2. 提取所有刮削器名称
      final scraperNames = <String>{};
      for (final plugin in plugins) {
        if (plugin['scrapers'] != null) {
          final scrapers = plugin['scrapers'] as List;
          for (final scraper in scrapers) {
            if (scraper['name'] != null) {
              scraperNames.add(scraper['name'] as String);
            }
          }
        }
      }
      print('提取到 ${scraperNames.length} 个刮削器: $scraperNames');

      if (scraperNames.isEmpty) {
        if (context.mounted) {
          Navigator.of(context).pop();
          SnackBarUtils.showError(context, '未找到可用的刮削器');
        }
        return;
      }

      // 3. 为每个刮削器创建默认配置
      final defaultConfig = ScraperCacheConfig(
        cacheEnabled: false,
        autoEnabled: false,
        autoEnabledAt: null,
        cacheFields: [
          CacheField.poster,
          CacheField.backdrop,
          CacheField.preview,
        ],
      );

      // 4. 批量添加刮削器配置
      print('开始批量添加刮削器配置...');
      for (final scraperName in scraperNames) {
        await apiService.updateScraperConfig(scraperName, defaultConfig);
      }
      print('配置添加完成');

      // 5. 等待后端写入配置文件
      await Future.delayed(const Duration(milliseconds: 1000));

      // 6. 强制刷新配置
      print('开始刷新配置...');
      await ref.read(cacheConfigProvider.notifier).refresh();
      print('配置刷新完成');

      if (context.mounted) {
        Navigator.of(context).pop();
        SnackBarUtils.showSuccess(
          context,
          '成功加载 ${scraperNames.length} 个刮削器',
        );
      }
    } catch (e) {
      print('加载刮削器失败: $e');
      if (context.mounted) {
        Navigator.of(context).pop();
        SnackBarUtils.showError(context, '加载失败: $e');
      }
    }
  }

  /// 构建单个刮削器卡片
  Widget _buildScraperCard(
    BuildContext context,
    WidgetRef ref,
    String scraperName,
    ScraperCacheConfig scraperConfig,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Row(
          children: [
            Text(scraperName),
            if (scraperConfig.autoEnabled) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('自动', style: TextStyle(fontSize: 12)),
                backgroundColor: Colors.blue.withOpacity(0.2),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
        subtitle: scraperConfig.autoEnabled && scraperConfig.autoEnabledAt != null
            ? Text(
                '自动开启于 ${_formatDateTime(scraperConfig.autoEnabledAt!)}',
                style: const TextStyle(fontSize: 12),
              )
            : null,
        trailing: Switch(
          value: scraperConfig.cacheEnabled,
          onChanged: (value) {
            ref.read(cacheConfigProvider.notifier).updateScraperCacheEnabled(
              scraperName,
              value,
            );
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '缓存字段',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CacheField.values.map((field) {
                    final isSelected = scraperConfig.cacheFields.contains(field);
                    return FilterChip(
                      label: Text(field.displayName),
                      selected: isSelected,
                      onSelected: (selected) {
                        final newFields = List<CacheField>.from(scraperConfig.cacheFields);
                        if (selected) {
                          newFields.add(field);
                        } else {
                          newFields.remove(field);
                        }
                        ref.read(cacheConfigProvider.notifier).updateScraperCacheFields(
                          scraperName,
                          newFields,
                        );
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 显示清理缓存确认对话框
  void _showClearCacheDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理所有缓存'),
        content: const Text('确定要清理所有缓存吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await ref.read(cacheStatsProvider.notifier).clearAllCache();
                if (context.mounted) {
                  SnackBarUtils.showSuccess(context, '缓存已清理');
                }
              } catch (e) {
                if (context.mounted) {
                  SnackBarUtils.showError(context, '清理失败: $e');
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 清理孤立缓存
  void _clearOrphanedCache(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(cacheStatsProvider.notifier).clearOrphanedCache();
      if (context.mounted) {
        SnackBarUtils.showSuccess(context, '孤立文件已清理');
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarUtils.showError(context, '清理失败: $e');
      }
    }
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
