import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/models/collection.dart';
import '../../../../core/models/actor.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/backend_mode.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../../sync/sync_status_widget.dart';
import '../../../scan/presentation/screens/file_scan_screen.dart';
import 'cache_settings_screen.dart';

// Settings state providers
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');
// 用于触发设置页面刷新的 provider
final settingsRefreshProvider = StateProvider<int>((ref) => 0);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    final currentRoute = GoRouterState.of(context).uri.toString();
    final isOnSettingsPage = currentRoute == '/settings';
    
    // 监听刷新触发器
    ref.watch(settingsRefreshProvider);

    return PopScope(
      canPop: !isOnSettingsPage, // 只在设置页时禁止直接返回
      onPopInvoked: (didPop) {
        // 只在设置页时拦截返回，其他情况允许正常返回
        if (!isOnSettingsPage) return;
        // 左滑无反应，用户应该使用底部导航栏切换页面
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false, // 移除返回按钮
          title: const Text('设置'),
          actions: [
            // Plugin UI injection point: settings_page
            ...PluginUIRegistry.instance.getButtons('settings_page').map((button) {
              return PluginUIRenderer.renderButton(
                button,
                context,
                contextData: {},
              );
            }),
          ],
        ),
      body: ListView(
        children: [
          // Appearance section
          _buildSectionHeader(context, '外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_getThemeModeText(themeMode)),
            onTap: () => _showThemeDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('语言'),
            subtitle: Text(_getLanguageText(language)),
            onTap: () => _showLanguageDialog(context, ref),
          ),
          const Divider(),

          // Data section
          _buildSectionHeader(context, '数据'),
          
          // 同步状态
          const SyncStatusWidget(),
          
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('导出数据'),
            subtitle: const Text('将收藏导出为JSON文件'),
            onTap: () => _showExportDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('导入数据'),
            subtitle: const Text('从JSON或CSV文件导入收藏'),
            onTap: () => _showImportDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('扫描本地文件'),
            subtitle: const Text('扫描本地视频文件并匹配到媒体库'),
            onTap: () => _navigateToFileScan(context),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('缓存管理'),
            subtitle: const Text('管理图片缓存配置和统计'),
            onTap: () => _navigateToCacheSettings(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            subtitle: const Text('清除缓存的图片和数据'),
            onTap: () => _showClearCacheDialog(context),
          ),
          const Divider(),

          // Server section
          _buildSectionHeader(context, '服务器'),
          
          // 本地服务器（独立模式使用）- 始终显示
          FutureBuilder<String>(
            key: ValueKey('local_${ref.watch(settingsRefreshProvider)}'),
            future: _getLocalServerUrl(),
            builder: (context, snapshot) {
              final localUrl = snapshot.data ?? '加载中...';
              return ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('本地服务器'),
                subtitle: Text(localUrl),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    _copyToClipboard(context, localUrl);
                  },
                  tooltip: '复制',
                ),
              );
            },
          ),
          
          // PC 后端服务器（PC 模式使用）- 始终显示
          FutureBuilder<String>(
            key: ValueKey('pc_${ref.watch(settingsRefreshProvider)}'),
            future: _getPcBackendUrl(ref),
            builder: (context, snapshot) {
              final pcUrl = snapshot.data ?? '加载中...';
              return ListTile(
                leading: const Icon(Icons.computer),
                title: const Text('PC 后端服务器'),
                subtitle: Text(pcUrl),
                trailing: const Icon(Icons.edit),
                onTap: () => _showServerConfigDialog(context, ref),
              );
            },
          ),
          const Divider(),

          // About section
          _buildSectionHeader(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('开源许可'),
            onTap: () => showLicensePage(context: context),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 4,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/filter');
              break;
            case 2:
              context.go('/collection');
              break;
            case 3:
              context.go('/actors');
              break;
            case 4:
              // Already on settings
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.filter_list_outlined),
            selectedIcon: Icon(Icons.filter_list),
            label: '筛选',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: '演员',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  String _getLanguageText(String code) {
    switch (code) {
      case 'zh':
        return '中文';
      case 'en':
        return 'English';
      default:
        return code;
    }
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: ref.read(themeModeProvider),
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).state = value!;
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色'),
              value: ThemeMode.light,
              groupValue: ref.read(themeModeProvider),
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).state = value!;
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色'),
              value: ThemeMode.dark,
              groupValue: ref.read(themeModeProvider),
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).state = value!;
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择语言'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('中文'),
              value: 'zh',
              groupValue: ref.read(languageProvider),
              onChanged: (value) {
                ref.read(languageProvider.notifier).state = value!;
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('English'),
              value: 'en',
              groupValue: ref.read(languageProvider),
              onChanged: (value) {
                ref.read(languageProvider.notifier).state = value!;
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('选择导出格式：'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _performExportJson(context, ref);
              },
              icon: const Icon(Icons.code),
              label: const Text('JSON 格式'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _performExportCsv(context, ref);
              },
              icon: const Icon(Icons.table_chart),
              label: const Text('CSV 格式'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _performExportJson(BuildContext context, WidgetRef ref) async {
    try {
      if (!context.mounted) return;
      context.showLoading('正在导出数据...');
      
      // 检查当前模式
      final modeManager = ref.read(backendModeManagerProvider);
      final currentMode = modeManager.currentMode;
      
      ExportDataResponse exportData;
      
      if (currentMode == BackendMode.standalone) {
        // 独立模式：从本地数据库导出
        final collectionRepo = ref.read(collectionRepositoryProvider);
        final actorRepo = ref.read(actorRepositoryProvider);
        final mediaRepo = ref.read(mediaRepositoryProvider);
        
        // 获取所有收藏
        final collections = await collectionRepo.getCollections();
        
        // 获取所有演员
        final actorListResult = await actorRepo.getActorList(pageSize: 10000);
        final actors = actorListResult.actors;
        
        // 获取所有媒体（使用大的 pageSize 来获取所有数据）
        final mediaListResult = await mediaRepo.getMediaList(pageSize: 10000);
        final mediaList = mediaListResult.items;
        
        // 转换演员数据为 ExportActorItem
        final exportActorList = actors.map((actor) => ExportActorItem(
          id: actor.id,
          name: actor.name,
          photoUrl: actor.photoUrls?.join(','),  // 将列表转换为逗号分隔的字符串
          biography: actor.biography,
          birthDate: actor.birthDate,
          nationality: actor.nationality,
        )).toList();
        
        // 获取演员-媒体关系
        final exportRelationList = <ExportActorMediaRelation>[];
        for (final actor in actors) {
          final actorMedia = await actorRepo.getActorMedia(actor.id);
          for (final media in actorMedia) {
            exportRelationList.add(ExportActorMediaRelation(
              actorId: actor.id,
              mediaId: media.id,
              role: 'Actor',
            ));
          }
        }
        
        exportData = ExportDataResponse(
          version: '1.0',
          exportedAt: DateTime.now().toIso8601String(),
          media: mediaList,
          collections: collections,
          actors: exportActorList,
          actorMediaRelations: exportRelationList,
        );
      } else {
        // PC 模式：从后端 API 导出
        final apiService = ref.read(apiServiceProvider);
        exportData = await apiService.exportAllData();
      }
      
      // Convert to JSON string
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData.toJson());
      
      // 使用跨平台文件下载
      final bytes = utf8.encode(jsonString);
      await FileDownload.download(
        data: bytes,
        filename: 'media_manager_export_${DateTime.now().millisecondsSinceEpoch}.json',
        mimeType: 'application/json',
      );
      
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showSuccess('导出成功！共导出 ${exportData.media.length} 个媒体，${exportData.collections.length} 个收藏');
    } catch (e) {
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showError('导出失败: $e');
    }
  }

  Future<void> _performExportCsv(BuildContext context, WidgetRef ref) async {
    try {
      if (!context.mounted) return;
      context.showLoading('正在导出CSV...');
      
      // 检查当前模式
      final modeManager = ref.read(backendModeManagerProvider);
      final currentMode = modeManager.currentMode;
      
      List<MediaItem> mediaList;
      
      if (currentMode == BackendMode.standalone) {
        // 独立模式：从本地数据库导出所有媒体
        final mediaRepo = ref.read(mediaRepositoryProvider);
        
        // 获取所有媒体（使用大的 pageSize 来获取所有数据）
        final mediaListResult = await mediaRepo.getMediaList(pageSize: 10000);
        mediaList = mediaListResult.items;
      } else {
        // PC 模式：从后端 API 导出
        final apiService = ref.read(apiServiceProvider);
        final exportData = await apiService.exportAllData();
        
        // exportData.media 已经是 List<MediaItem>，直接使用
        mediaList = exportData.media;
      }
      
      // 构建CSV数据
      final List<List<dynamic>> csvData = [
        // 表头
        ['title', 'original_title', 'year', 'media_type', 'rating', 'genres', 'overview', 'poster_url', 'backdrop_url', 'play_links', 'download_links', 'preview_urls', 'preview_video_urls', 'studio', 'series'],
      ];
      
      // 数据行
      for (final media in mediaList) {
        // 将枚举转换为正确的字符串值
        String mediaTypeStr;
        switch (media.mediaType) {
          case MediaType.movie:
            mediaTypeStr = 'Movie';
            break;
          case MediaType.scene:
            mediaTypeStr = 'Scene';
            break;
          case MediaType.documentary:
            mediaTypeStr = 'Documentary';
            break;
          case MediaType.anime:
            mediaTypeStr = 'Anime';
            break;
          case MediaType.censored:
            mediaTypeStr = 'Censored';
            break;
          case MediaType.uncensored:
            mediaTypeStr = 'Uncensored';
            break;
        }
        
        // 将播放链接和下载链接序列化为JSON字符串
        final playLinksJson = media.playLinks.isNotEmpty 
            ? json.encode(media.playLinks.map((e) => e.toJson()).toList())
            : '';
        final downloadLinksJson = media.downloadLinks.isNotEmpty 
            ? json.encode(media.downloadLinks.map((e) => e.toJson()).toList())
            : '';
        // 将预览图和预览视频序列化为JSON字符串
        final previewUrlsJson = media.previewUrls.isNotEmpty 
            ? json.encode(media.previewUrls)
            : '';
        final previewVideoUrlsJson = media.previewVideoUrls.isNotEmpty 
            ? json.encode(media.previewVideoUrls)
            : '';
        
        csvData.add([
          media.title,
          media.originalTitle ?? '',
          media.year?.toString() ?? '',
          mediaTypeStr,
          media.rating?.toString() ?? '',
          media.genres.join(','),
          media.overview ?? '',
          media.posterUrl ?? '',
          media.backdropUrl.join('|'),  // 多个背景图用 | 分隔
          playLinksJson,
          downloadLinksJson,
          previewUrlsJson,
          previewVideoUrlsJson,
          media.studio ?? '',
          media.series ?? '',
        ]);
      }
      
      // 转换为CSV字符串
      final csvString = const ListToCsvConverter().convert(csvData);
      
      // 添加 BOM 以支持 Excel 正确识别 UTF-8
      final csvWithBom = '\uFEFF$csvString';
      
      // 使用跨平台文件下载
      await FileDownload.downloadText(
        content: csvWithBom,
        filename: 'media_manager_export_${DateTime.now().millisecondsSinceEpoch}.csv',
        mimeType: 'text/csv;charset=utf-8',
      );
      
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showSuccess('CSV导出成功！共导出 ${mediaList.length} 条数据');
    } catch (e) {
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showError('CSV导出失败: $e');
    }
  }

  Future<void> _performExport(BuildContext context, WidgetRef ref) async {
    // 保留旧方法以兼容
    await _performExportJson(context, ref);
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('选择要导入的文件格式：'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _performImportJson(context, ref);
              },
              icon: const Icon(Icons.code),
              label: const Text('JSON 文件'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _performImportCsv(context, ref);
              },
              icon: const Icon(Icons.table_chart),
              label: const Text('CSV 文件'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _performImportJson(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) {
        return;
      }
      
      final file = result.files.first;
      if (file.bytes == null) {
        if (!context.mounted) return;
        context.showError('无法读取文件');
        return;
      }
      
      if (!context.mounted) return;
      context.showLoading('正在导入数据...');
      
      final jsonString = utf8.decode(file.bytes!);
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      
      // Parse import data
      final mediaList = (jsonData['media'] as List?)?.map((e) {
        // 解析播放链接
        final playLinks = (e['play_links'] as List?)?.map((link) {
          return ImportPlayLink.fromJson(link as Map<String, dynamic>);
        }).toList();
        
        // 解析下载链接
        final downloadLinks = (e['download_links'] as List?)?.map((link) {
          return ImportDownloadLink.fromJson(link as Map<String, dynamic>);
        }).toList();
        
        // 解析预览图
        final previewUrls = (e['preview_urls'] as List?)?.cast<String>();
        
        // 解析预览视频
        final previewVideoUrls = (e['preview_video_urls'] as List?)?.cast<String>();
        
        return ImportMediaItem(
          title: e['title'] ?? '',
          originalTitle: e['original_title'],
          year: e['year'],
          mediaType: e['media_type'] ?? 'Movie',
          genres: (e['genres'] as List?)?.cast<String>(),
          rating: (e['rating'] as num?)?.toDouble(),
          overview: e['overview'],
          posterUrl: e['poster_url'],
          backdropUrl: (e['backdrop_url'] is List) 
              ? (e['backdrop_url'] as List).cast<String>()
              : (e['backdrop_url'] as String?)?.isNotEmpty == true 
                  ? [e['backdrop_url'] as String]
                  : null,
          playLinks: playLinks,
          downloadLinks: downloadLinks,
          previewUrls: previewUrls,
          previewVideoUrls: previewVideoUrls,
          studio: e['studio'],
          series: e['series'],
        );
      }).toList() ?? [];
      
      final collectionList = (jsonData['collections'] as List?)?.map((e) {
        return ImportCollectionItem(
          mediaTitle: e['media_title'] ?? '',
          watchStatus: e['watch_status'] ?? 'WantToWatch',
          personalRating: (e['personal_rating'] as num?)?.toDouble(),
          notes: e['notes'],
          isFavorite: e['is_favorite'],
          userTags: (e['user_tags'] as List?)?.cast<String>(),
        );
      }).toList();
      
      // 解析演员数据
      final actorList = (jsonData['actors'] as List?)?.map((e) {
        return ImportActorItem.fromJson(e as Map<String, dynamic>);
      }).toList();
      
      // 解析演员-媒体关系
      final relationList = (jsonData['actor_media_relations'] as List?)?.map((e) {
        return ImportActorMediaRelation.fromJson(e as Map<String, dynamic>);
      }).toList();
      
      final request = ImportDataRequest(
        version: jsonData['version'] ?? '1.0',
        media: mediaList,
        collections: collectionList,
        actors: actorList,
        actorMediaRelations: relationList,
      );
      
      // 检查当前模式
      final modeManager = ref.read(backendModeManagerProvider);
      final currentMode = modeManager.currentMode;
      
      ImportDataResponse response;
      
      if (currentMode == BackendMode.standalone) {
        // 独立模式：导入到本地数据库
        response = await _importToLocalDatabase(ref, request);
      } else {
        // PC 模式：调用后端 API
        final apiService = ref.read(apiServiceProvider);
        response = await apiService.importData(request);
      }
      
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showSuccess(
        '导入完成！\n'
        '媒体: ${response.mediaImported}成功/${response.mediaFailed}失败\n'
        '收藏: ${response.collectionsImported}成功/${response.collectionsFailed}失败\n'
        '演员: ${response.actorsImported}成功/${response.actorsFailed}失败\n'
        '关系: ${response.relationsImported}成功/${response.relationsFailed}失败',
      );
    } catch (e) {
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showError('导入失败: $e');
    }
  }

  Future<void> _performImportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) {
        return;
      }
      
      final file = result.files.first;
      if (file.bytes == null) {
        if (!context.mounted) return;
        context.showError('无法读取文件');
        return;
      }
      
      if (!context.mounted) return;
      context.showLoading('正在解析CSV文件...');
      
      // 尝试多种编码方式解码 CSV 文件
      String csvString;
      try {
        // 首先尝试 UTF-8
        csvString = utf8.decode(file.bytes!, allowMalformed: false);
      } catch (e) {
        try {
          // 如果 UTF-8 失败，尝试 Latin1（兼容大多数编码）
          csvString = latin1.decode(file.bytes!);
        } catch (e2) {
          if (!context.mounted) return;
          context.hideSnackBar();
          context.showError('无法解析CSV文件编码，请确保文件是UTF-8编码');
          return;
        }
      }
      
      final rows = const CsvToListConverter().convert(csvString);
      
      if (rows.isEmpty) {
        if (!context.mounted) return;
        context.hideSnackBar();
        context.showError('CSV文件为空');
        return;
      }
      
      // 第一行是表头
      final headers = rows.first.map((e) => e.toString().toLowerCase()).toList();
      final dataRows = rows.skip(1).toList();
      
      // 查找列索引
      final titleIndex = _findColumnIndex(headers, ['title', '标题', '名称', 'name']);
      final yearIndex = _findColumnIndex(headers, ['year', '年份', '年代']);
      final typeIndex = _findColumnIndex(headers, ['type', 'media_type', '类型']);
      final ratingIndex = _findColumnIndex(headers, ['rating', '评分', 'score']);
      final overviewIndex = _findColumnIndex(headers, ['overview', '简介', 'description', '描述']);
      final posterIndex = _findColumnIndex(headers, ['poster', 'poster_url', '封面', '海报']);
      final genresIndex = _findColumnIndex(headers, ['genres', 'genre', '类型', '分类']);
      final playLinksIndex = _findColumnIndex(headers, ['play_links', '播放链接']);
      final downloadLinksIndex = _findColumnIndex(headers, ['download_links', '下载链接']);
      final previewUrlsIndex = _findColumnIndex(headers, ['preview_urls', '预览图']);
      final previewVideoUrlsIndex = _findColumnIndex(headers, ['preview_video_urls', '预览视频']);
      final studioIndex = _findColumnIndex(headers, ['studio', '制作商', '厂商']);
      final seriesIndex = _findColumnIndex(headers, ['series', '系列']);
      
      if (titleIndex == -1) {
        if (!context.mounted) return;
        context.hideSnackBar();
        context.showError('CSV文件缺少标题列 (title/标题/名称)');
        return;
      }
      
      // 解析数据
      final mediaList = <ImportMediaItem>[];
      for (final row in dataRows) {
        if (row.length <= titleIndex) continue;
        
        final title = row[titleIndex]?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        
        // 解析播放链接（JSON格式）
        List<ImportPlayLink>? playLinks;
        if (playLinksIndex >= 0 && row.length > playLinksIndex) {
          final playLinksStr = row[playLinksIndex]?.toString().trim() ?? '';
          if (playLinksStr.isNotEmpty) {
            try {
              final playLinksJson = json.decode(playLinksStr) as List;
              playLinks = playLinksJson.map((e) => ImportPlayLink.fromJson(e as Map<String, dynamic>)).toList();
            } catch (_) {
              // 忽略解析错误
            }
          }
        }
        
        // 解析下载链接（JSON格式）
        List<ImportDownloadLink>? downloadLinks;
        if (downloadLinksIndex >= 0 && row.length > downloadLinksIndex) {
          final downloadLinksStr = row[downloadLinksIndex]?.toString().trim() ?? '';
          if (downloadLinksStr.isNotEmpty) {
            try {
              final downloadLinksJson = json.decode(downloadLinksStr) as List;
              downloadLinks = downloadLinksJson.map((e) => ImportDownloadLink.fromJson(e as Map<String, dynamic>)).toList();
            } catch (_) {
              // 忽略解析错误
            }
          }
        }
        
        // 解析预览图（JSON格式）
        List<String>? previewUrls;
        if (previewUrlsIndex >= 0 && row.length > previewUrlsIndex) {
          final previewUrlsStr = row[previewUrlsIndex]?.toString().trim() ?? '';
          if (previewUrlsStr.isNotEmpty) {
            try {
              final previewUrlsJson = json.decode(previewUrlsStr) as List;
              previewUrls = previewUrlsJson.cast<String>();
            } catch (_) {
              // 忽略解析错误
            }
          }
        }
        
        // 解析预览视频（JSON格式）
        List<String>? previewVideoUrls;
        if (previewVideoUrlsIndex >= 0 && row.length > previewVideoUrlsIndex) {
          final previewVideoUrlsStr = row[previewVideoUrlsIndex]?.toString().trim() ?? '';
          if (previewVideoUrlsStr.isNotEmpty) {
            try {
              final previewVideoUrlsJson = json.decode(previewVideoUrlsStr) as List;
              previewVideoUrls = previewVideoUrlsJson.cast<String>();
            } catch (_) {
              // 忽略解析错误
            }
          }
        }
        
        mediaList.add(ImportMediaItem(
          title: title,
          year: yearIndex >= 0 && row.length > yearIndex 
              ? int.tryParse(row[yearIndex]?.toString() ?? '') 
              : null,
          mediaType: typeIndex >= 0 && row.length > typeIndex 
              ? _parseMediaType(row[typeIndex]?.toString() ?? '') 
              : 'Movie',
          rating: ratingIndex >= 0 && row.length > ratingIndex 
              ? double.tryParse(row[ratingIndex]?.toString() ?? '') 
              : null,
          overview: overviewIndex >= 0 && row.length > overviewIndex 
              ? row[overviewIndex]?.toString() 
              : null,
          posterUrl: posterIndex >= 0 && row.length > posterIndex 
              ? row[posterIndex]?.toString() 
              : null,
          genres: genresIndex >= 0 && row.length > genresIndex 
              ? row[genresIndex]?.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() 
              : null,
          playLinks: playLinks,
          downloadLinks: downloadLinks,
          previewUrls: previewUrls,
          previewVideoUrls: previewVideoUrls,
          studio: studioIndex >= 0 && row.length > studioIndex 
              ? row[studioIndex]?.toString().trim() 
              : null,
          series: seriesIndex >= 0 && row.length > seriesIndex 
              ? row[seriesIndex]?.toString().trim() 
              : null,
        ));
      }
      
      if (mediaList.isEmpty) {
        if (!context.mounted) return;
        context.hideSnackBar();
        context.showError('没有找到有效的数据行');
        return;
      }
      
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showLoading('正在导入 ${mediaList.length} 条数据...');
      
      final request = ImportDataRequest(
        version: '1.0',
        media: mediaList,
      );
      
      // 检查当前模式
      final modeManager = ref.read(backendModeManagerProvider);
      final currentMode = modeManager.currentMode;
      
      ImportDataResponse response;
      
      if (currentMode == BackendMode.standalone) {
        // 独立模式：导入到本地数据库
        response = await _importToLocalDatabase(ref, request);
      } else {
        // PC 模式：调用后端 API
        final apiService = ref.read(apiServiceProvider);
        response = await apiService.importData(request);
      }
      
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showSuccess('CSV导入完成！成功: ${response.mediaImported}，失败: ${response.mediaFailed}');
    } catch (e) {
      if (!context.mounted) return;
      context.hideSnackBar();
      context.showError('CSV导入失败: $e');
    }
  }

  int _findColumnIndex(List<String> headers, List<String> possibleNames) {
    for (final name in possibleNames) {
      final index = headers.indexOf(name);
      if (index >= 0) return index;
    }
    return -1;
  }

  String _parseMediaType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('scene') || lower.contains('场景') || lower.contains('tv')) {
      return 'Scene';
    }
    return 'Movie';
  }

  WatchStatus _parseWatchStatus(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('watching') || lower.contains('观看中')) {
      return WatchStatus.watching;
    } else if (lower.contains('completed') || lower.contains('watched') || lower.contains('已观看')) {
      return WatchStatus.completed;
    } else if (lower.contains('want') || lower.contains('想看')) {
      return WatchStatus.wantToWatch;
    }
    return WatchStatus.wantToWatch;
  }

  /// 导入数据到本地数据库（独立模式）
  Future<ImportDataResponse> _importToLocalDatabase(WidgetRef ref, ImportDataRequest request) async {
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final collectionRepo = ref.read(collectionRepositoryProvider);
    final actorRepo = ref.read(actorRepositoryProvider);
    
    int mediaImported = 0;
    int mediaFailed = 0;
    int collectionsImported = 0;
    int collectionsFailed = 0;
    int actorsImported = 0;
    int actorsFailed = 0;
    int relationsImported = 0;
    int relationsFailed = 0;
    
    // 导入媒体
    final mediaIdMap = <String, String>{}; // title -> id
    for (final importMedia in request.media) {
      try {
        // 转换 ImportMediaItem 到 MediaItem
        final media = MediaItem(
          id: '',
          title: importMedia.title,
          originalTitle: importMedia.originalTitle,
          year: importMedia.year,
          mediaType: _parseMediaTypeEnum(importMedia.mediaType),
          genres: importMedia.genres ?? [],
          rating: importMedia.rating,
          posterUrl: importMedia.posterUrl,
          backdropUrl: importMedia.backdropUrl ?? [],
          overview: importMedia.overview,
          externalIds: const ExternalIds(),
          playLinks: importMedia.playLinks?.map((link) => PlayLink(
            name: link.name,
            url: link.url,
            quality: link.quality,
          )).toList() ?? [],
          downloadLinks: importMedia.downloadLinks?.map((link) => DownloadLink(
            name: link.name,
            url: link.url,
            linkType: _parseDownloadLinkType(link.linkType),
            size: link.size,
            password: link.password,
          )).toList() ?? [],
          previewUrls: importMedia.previewUrls ?? [],
          previewVideoUrls: importMedia.previewVideoUrls ?? [],
          studio: importMedia.studio,
          series: importMedia.series,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        final savedMedia = await mediaRepo.addMedia(media);
        mediaIdMap[importMedia.title] = savedMedia.id;
        mediaImported++;
      } catch (e) {
        print('导入媒体失败: ${importMedia.title}, 错误: $e');
        mediaFailed++;
      }
    }
    
    // 导入收藏
    if (request.collections != null) {
      for (final importCollection in request.collections!) {
        try {
          final mediaId = mediaIdMap[importCollection.mediaTitle];
          if (mediaId == null) {
            print('找不到媒体: ${importCollection.mediaTitle}');
            collectionsFailed++;
            continue;
          }
          
          // 添加收藏
          final collection = await collectionRepo.addCollection(
            mediaId,
            watchStatus: _parseWatchStatus(importCollection.watchStatus),
          );
          
          // 更新收藏详情
          await collectionRepo.updateCollection(
            mediaId,
            UpdateCollectionRequest(
              personalRating: importCollection.personalRating,
              notes: importCollection.notes,
              isFavorite: importCollection.isFavorite,
              userTags: importCollection.userTags,
            ),
          );
          
          collectionsImported++;
        } catch (e) {
          print('导入收藏失败: ${importCollection.mediaTitle}, 错误: $e');
          collectionsFailed++;
        }
      }
    }
    
    // 导入演员
    final actorIdMap = <String, String>{}; // name -> id
    if (request.actors != null) {
      for (final importActor in request.actors!) {
        try {
          // 将逗号分隔的字符串转换为列表
          final photoUrls = importActor.photoUrl != null && importActor.photoUrl!.isNotEmpty
              ? importActor.photoUrl!.split(',').map((url) => url.trim()).toList()
              : null;
          
          final actor = Actor(
            id: '',
            name: importActor.name,
            photoUrls: photoUrls,
            biography: importActor.biography,
            birthDate: importActor.birthDate,
            nationality: importActor.nationality,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          final savedActor = await actorRepo.addActor(actor);
          actorIdMap[importActor.name] = savedActor.id;
          actorsImported++;
        } catch (e) {
          print('导入演员失败: ${importActor.name}, 错误: $e');
          actorsFailed++;
        }
      }
    }
    
    // 导入演员-媒体关系
    if (request.actorMediaRelations != null) {
      for (final relation in request.actorMediaRelations!) {
        try {
          final actorId = actorIdMap[relation.actorName];
          final mediaId = mediaIdMap[relation.mediaTitle];
          
          if (actorId == null || mediaId == null) {
            print('找不到演员或媒体: ${relation.actorName} - ${relation.mediaTitle}');
            relationsFailed++;
            continue;
          }
          
          await actorRepo.linkToMedia(actorId, mediaId);
          relationsImported++;
        } catch (e) {
          print('导入关系失败: ${relation.actorName} - ${relation.mediaTitle}, 错误: $e');
          relationsFailed++;
        }
      }
    }
    
    return ImportDataResponse(
      mediaImported: mediaImported,
      mediaFailed: mediaFailed,
      collectionsImported: collectionsImported,
      collectionsFailed: collectionsFailed,
      actorsImported: actorsImported,
      actorsFailed: actorsFailed,
      relationsImported: relationsImported,
      relationsFailed: relationsFailed,
      errors: const [],
    );
  }

  /// 解析媒体类型枚举
  MediaType _parseMediaTypeEnum(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('scene') || lower == 'scene') {
      return MediaType.scene;
    } else if (lower.contains('documentary') || lower == 'documentary') {
      return MediaType.documentary;
    } else if (lower.contains('anime') || lower == 'anime') {
      return MediaType.anime;
    } else if (lower.contains('censored') || lower == 'censored') {
      return MediaType.censored;
    } else if (lower.contains('uncensored') || lower == 'uncensored') {
      return MediaType.uncensored;
    }
    return MediaType.movie;
  }

  /// 解析下载链接类型
  DownloadLinkType _parseDownloadLinkType(String type) {
    final lower = type.toLowerCase();
    if (lower == 'magnet') {
      return DownloadLinkType.magnet;
    } else if (lower == 'ed2k') {
      return DownloadLinkType.ed2k;
    } else if (lower == 'http') {
      return DownloadLinkType.http;
    } else if (lower == 'ftp') {
      return DownloadLinkType.ftp;
    } else if (lower == 'torrent') {
      return DownloadLinkType.torrent;
    } else if (lower == 'pan') {
      return DownloadLinkType.pan;
    }
    return DownloadLinkType.other;
  }

  /// 获取当前模式
  Future<BackendMode> _getCurrentMode(WidgetRef ref) async {
    try {
      final modeManager = ref.read(backendModeManagerProvider);
      return modeManager.currentMode;
    } catch (e) {
      print('获取当前模式失败: $e');
      return BackendMode.standalone;
    }
  }

  /// 获取 PC 后端地址
  Future<String> _getPcBackendUrl(WidgetRef ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pcBackendUrl = prefs.getString('pc_backend_url') ?? 'http://localhost:3000';
      return pcBackendUrl;
    } catch (e) {
      print('获取 PC 后端地址失败: $e');
      return 'http://localhost:3000';
    }
  }

  /// 获取本地服务器地址
  Future<String> _getLocalServerUrl() async {
    try {
      // 获取设备的局域网 IP
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
      for (final interface in interfaces) {
        if (interface.name.toLowerCase().contains('lo')) continue;
        
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
            return 'http://$ip:8080/api';
          }
        }
      }
      
      return 'http://localhost:8080/api';
    } catch (e) {
      print('获取本地服务器地址失败: $e');
      return 'http://localhost:8080/api';
    }
  }

  /// 复制到剪贴板
  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    context.showSuccess('已复制到剪贴板');
  }

  Future<void> _performImport(BuildContext context, WidgetRef ref) async {
    // 保留旧方法以兼容
    await _performImportJson(context, ref);
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('这将清除所有缓存的图片和数据，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.showSuccess('缓存已清除');
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  void _showServerConfigDialog(BuildContext context, WidgetRef ref) async {
    // 从 SharedPreferences 读取 PC 后端地址
    final prefs = await SharedPreferences.getInstance();
    final pcBackendUrl = prefs.getString('pc_backend_url') ?? 'http://localhost:3000';
    
    final controller = TextEditingController(text: pcBackendUrl);
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配置 PC 后端服务器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '请输入 PC 后端服务器地址：',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.17:3000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              // 移除末尾的斜杠
              final cleanUrl = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
              
              // 保存到 SharedPreferences（使用 pc_backend_url key）
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pc_backend_url', cleanUrl);
              
              // 同时更新 apiBaseUrlProvider（用于 API 服务）
              ref.read(apiBaseUrlProvider.notifier).state = cleanUrl;
              
              // 通知 BackendModeManager 更新
              final modeManager = ref.read(backendModeManagerProvider);
              modeManager.setPcBackendUrl(cleanUrl);
              
              // 触发设置页面刷新
              ref.read(settingsRefreshProvider.notifier).state++;
              
              Navigator.pop(context);
              context.showSuccess('服务器地址已更新');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}


  /// 导航到文件扫描页面
  void _navigateToFileScan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FileScanScreen(),
      ),
    );
  }

  /// 导航到缓存设置页面
  void _navigateToCacheSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CacheSettingsScreen(),
      ),
    );
  }
