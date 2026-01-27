import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'ui_models.dart';
import 'ui_registry.dart';
import 'enhanced_dialog_renderer.dart';
import '../services/api_service.dart';
import '../services/backend_mode.dart';
import '../config/app_config.dart';
import '../providers/app_providers.dart';
import '../utils/snackbar_utils.dart';
import '../../features/actors/providers/actor_providers.dart';
import '../../features/media/providers/media_providers.dart';
import '../../shared/widgets/media_card.dart';

/// UI渲染器 - 根据配置动态生成Widget
class PluginUIRenderer {
  /// 渲染按钮
  /// 
  /// [button] 按钮配置
  /// [context] BuildContext
  /// [contextData] 上下文数据（如 media_id, actor_id 等）
  static Widget renderButton(
    UIButton button,
    BuildContext context, {
    Map<String, dynamic>? contextData,
  }) {
    // 使用 Consumer 来访问 Provider
    return Consumer(
      builder: (context, ref, child) {
        try {
          final locale = Localizations.localeOf(context).languageCode;
          
          // 调试输出：显示当前locale
          print('🌍 Button ${button.id} - Detected locale: $locale');

          // 获取本地化文本
          final label = button.getLocalizedText(button.label, locale);
          final tooltip = button.getLocalizedText(button.tooltip, locale);
          
          // 调试输出：显示选择的文本
          if (label.isNotEmpty) {
            print('   Label: $label');
          }
          if (tooltip.isNotEmpty) {
            print('   Tooltip: $tooltip');
          }

          // 获取图标
          final icon = _getIcon(button.icon);

          // 检查是否为刮削相关按钮（在独立模式下不可用）
          final isScrapingButton = button.id.contains('scrape') || 
                                   button.id.contains('supplement') ||
                                   button.id.contains('magnet');
          
          // 创建按钮的 onPressed 回调
          VoidCallback? onPressed;
          
          if (isScrapingButton) {
            // 刮削按钮：需要检查后端模式
            onPressed = () {
              // 从 ref 读取后端模式
              final modeManager = ref.read(backendModeManagerProvider);
              final currentMode = modeManager.currentMode;
              
              print('🔍 Button clicked: ${button.id}');
              print('   Current mode: $currentMode');
              
              if (currentMode == BackendMode.standalone) {
                // 独立模式：显示友好提示
                print('⚠️ Showing standalone mode warning');
                showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(dialogContext).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(locale == 'zh' ? '功能不可用' : 'Feature Unavailable'),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locale == 'zh' 
                            ? '刮削功能需要连接到 PC 后端才能使用。'
                            : 'Scraping features require connection to PC backend.',
                          style: Theme.of(dialogContext).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(dialogContext).colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                locale == 'zh' ? '如何启用：' : 'How to enable:',
                                style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                locale == 'zh'
                                  ? '1. 确保 PC 后端正在运行\n2. 在设置中配置 PC 后端地址\n3. 切换到 PC 模式'
                                  : '1. Ensure PC backend is running\n2. Configure PC backend address in settings\n3. Switch to PC mode',
                                style: Theme.of(dialogContext).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(locale == 'zh' ? '知道了' : 'Got it'),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          // 跳转到设置页面
                          context.go('/settings');
                        },
                        icon: const Icon(Icons.settings),
                        label: Text(locale == 'zh' ? '前往设置' : 'Go to Settings'),
                      ),
                    ],
                  ),
                );
              } else {
                // PC 模式：正常执行操作
                print('✅ PC mode, executing action');
                _handleAction(button.action, context, contextData);
              }
            };
          } else {
            // 非刮削按钮：直接执行操作
            onPressed = () => _handleAction(button.action, context, contextData);
          }

          // 创建按钮
          if (label.isNotEmpty) {
            // 带标签的按钮
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: TextButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label),
              ),
            );
          } else {
            // 只有图标的按钮
            return IconButton(
              icon: Icon(icon),
              tooltip: tooltip,
              onPressed: onPressed,
            );
          }
        } catch (e) {
          print('❌ Error rendering button ${button.id}: $e');
          // 返回一个空的占位符，避免整个UI崩溃
          return const SizedBox.shrink();
        }
      },
    );
  }

  /// 渲染对话框
  /// 
  /// [dialog] 对话框配置
  /// [context] BuildContext
  /// [contextData] 上下文数据
  static Widget renderDialog(
    UIDialog dialog,
    BuildContext context, {
    Map<String, dynamic>? contextData,
  }) {
    try {
      final locale = Localizations.localeOf(context).languageCode;
      final title = dialog.getLocalizedTitle(locale);

      // 检查是否是批量刮削/补全对话框，使用增强版渲染
      final isBatchDialog = dialog.id.contains('batch_scrape') || 
                           dialog.id.contains('batch_supplement') ||
                           dialog.id == 'auto_scrape_unmatched_dialog';
      
      // 检查是否是单个刮削/补全对话框（详情页）
      final isSingleScrapeDialog = dialog.id == 'scrape_media_dialog' || 
                                   dialog.id == 'supplement_media_dialog';
      
      // 检查是否是磁力刮削对话框
      final isMagnetScrapeDialog = dialog.id == 'magnet_scrape_dialog';
      
      if (isMagnetScrapeDialog && contextData != null) {
        // 使用增强版磁力刮削对话框
        return EnhancedDialogRenderer.renderMagnetScrapeDialog(
          context: context,
          title: title,
          contextData: contextData,
          onConfirm: (searchQuery) {
            final formData = <String, dynamic>{
              'search_query': searchQuery,
            };
            
            final mainAction = dialog.actions.firstWhere(
              (action) => action.type == 'call_api',
              orElse: () => dialog.actions.first,
            );
            
            // 不要在这里关闭对话框，让进度对话框显示在上面
            
            _handleDialogAction(
              mainAction,
              context,
              locale,
              contextData,
              formData,
            );
          },
          onCancel: () {
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
        );
      }
      
      if (isSingleScrapeDialog && contextData != null) {
        // 根据对话框ID决定模式
        final mode = dialog.id == 'supplement_media_dialog' ? 'supplement' : 'replace';
        final dialogTitle = dialog.id == 'supplement_media_dialog' 
            ? (locale == 'zh' ? '补全媒体' : locale == 'ja' ? '補完' : 'Supplement Media')
            : title;
        
        return EnhancedDialogRenderer.renderSingleScrapeDialog(
          context: context,
          title: dialogTitle,
          contextData: contextData,
          onConfirm: (scrapeMode, searchQuery, contentType) async {
            // 调用多结果刮削 API
            try {
              // 显示进度对话框
              if (context.mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  useRootNavigator: true,
                  builder: (dialogContext) => PopScope(
                    canPop: false,
                    child: Dialog(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(dialogContext).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: CircularProgressIndicator(
                                strokeWidth: 6,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(dialogContext).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              locale == 'zh' ? '正在刮削...' : 'Scraping...',
                              style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              // 调用 API
              final container = ProviderScope.containerOf(context, listen: false);
              final apiService = container.read(apiServiceProvider);
              final mediaId = contextData['media_id'] as String;
              
              // 根据刮削模式决定是否传递 series/studio 参数
              String? seriesParam;
              String? studioParam;
              
              print('🔍 刮削模式: $scrapeMode');
              print('   searchQuery: $searchQuery');
              
              if (scrapeMode == 'series_date' || scrapeMode == 'series_title') {
                // series_date 和 series_title 模式：传递 series
                seriesParam = contextData['series'] as String?;
                print('   ✅ 传递 series: $seriesParam');
              } else if (scrapeMode == 'studio_code') {
                // studio_code 模式：传递 studio
                studioParam = contextData['studio'] as String?;
                print('   ✅ 传递 studio: $studioParam');
              } else {
                print('   ⚠️ 不传递 series/studio');
              }
              
              // 调用统一的刮削API
              final response = await apiService.scrapeMedia(
                mediaId: mediaId,
                code: searchQuery,
                contentType: contentType,
                series: seriesParam,  // 只在 series_date/series_title 模式传递
                studio: studioParam,  // 只在 studio_code 模式传递
                mode: mode,  // 'replace' 或 'supplement'
              );

              // 关闭进度对话框
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }

              if (response.isSingle) {
                // 单个结果：已经直接入库，关闭刮削对话框
                if (context.mounted) {
                  Navigator.of(context).pop();
                  
                  // 显示成功消息
                  final successMsg = locale == 'zh' ? '刮削成功' : 'Scrape successful';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(successMsg),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  // 刷新页面
                  final container = ProviderScope.containerOf(context, listen: false);
                  if (contextData.containsKey('media_id')) {
                    // 清除旧的图片缓存
                    clearAspectRatioCache();
                    
                    // 清除网络图片缓存（强制重新下载）
                    if (context.mounted) {
                      // 清除 Flutter 的图片缓存
                      PaintingBinding.instance.imageCache.clear();
                      PaintingBinding.instance.imageCache.clearLiveImages();
                    }
                    
                    // 预检测新图片的尺寸并缓存（避免列表页卡顿）
                    try {
                      // 获取刮削后的媒体详情
                      final apiService = container.read(apiServiceProvider);
                      final mediaDetail = await apiService.getMediaDetail(mediaId);
                      
                      // 预检测封面图片尺寸
                      if (mediaDetail.posterUrl != null && mediaDetail.posterUrl!.isNotEmpty) {
                        await precacheImageAspectRatio(mediaDetail.posterUrl!);
                      }
                      
                      print('✅ 图片尺寸预检测完成');
                    } catch (e) {
                      print('⚠️ 图片尺寸预检测失败: $e');
                    }
                    
                    // 刷新详情页和列表页
                    container.invalidate(mediaDetailProvider(mediaId));
                    container.invalidate(mediaListProvider);
                  }
                }
              } else if (response.isMultiple) {
                // 多个结果：显示多选对话框
                if (context.mounted) {
                  // 先关闭刮削对话框
                  Navigator.of(context).pop();
                  
                  // 显示多选对话框
                  showDialog(
                    context: context,
                    builder: (context) => EnhancedDialogRenderer.renderMultipleResultsDialog(
                      context: context,
                      title: locale == 'zh' ? '选择要导入的结果' : 'Select Results to Import',
                      results: response.multipleResults!.results,
                      mediaId: mediaId,
                      mode: mode,  // 传递 mode 参数
                      onSuccess: () async {
                        // 刷新页面
                        if (context.mounted) {
                          final container = ProviderScope.containerOf(context, listen: false);
                          // 清除旧的图片缓存
                          clearAspectRatioCache();
                          
                          // 清除网络图片缓存（强制重新下载）
                          // 清除 Flutter 的图片缓存
                          PaintingBinding.instance.imageCache.clear();
                          PaintingBinding.instance.imageCache.clearLiveImages();
                          
                          // 预检测新图片的尺寸并缓存（避免列表页卡顿）
                          try {
                            // 获取刮削后的媒体详情
                            final apiService = container.read(apiServiceProvider);
                            final mediaDetail = await apiService.getMediaDetail(mediaId);
                            
                            // 预检测封面图片尺寸
                            if (mediaDetail.posterUrl != null && mediaDetail.posterUrl!.isNotEmpty) {
                              await precacheImageAspectRatio(mediaDetail.posterUrl!);
                            }
                            
                            print('✅ 图片尺寸预检测完成');
                          } catch (e) {
                            print('⚠️ 图片尺寸预检测失败: $e');
                          }
                          
                          // 刷新详情页和列表页
                          container.invalidate(mediaDetailProvider(mediaId));
                          container.invalidate(mediaListProvider);
                        }
                      },
                    ),
                  );
                }
              }
            } catch (e) {
              // 关闭进度对话框
              if (context.mounted) {
                try {
                  Navigator.of(context, rootNavigator: true).pop();
                } catch (_) {}
              }

              // 显示错误
              if (context.mounted) {
                final errorMsg = locale == 'zh' ? '刮削失败: $e' : 'Scrape failed: $e';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMsg),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          },
          onCancel: () {
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
        );
      }
      
      if (isBatchDialog && contextData != null) {
        String itemType = 'media';
        int itemCount = 0;
        
        if (contextData.containsKey('actor_ids')) {
          itemType = 'actor';
          final actorIds = contextData['actor_ids'];
          itemCount = actorIds is List ? actorIds.length : 0;
        } else if (contextData.containsKey('media_ids')) {
          itemType = 'media';
          final mediaIds = contextData['media_ids'];
          itemCount = mediaIds is List ? mediaIds.length : 0;
        } else if (contextData.containsKey('selected_media_ids')) {
          itemType = 'media';
          final mediaIds = contextData['selected_media_ids'];
          itemCount = mediaIds is List ? mediaIds.length : 0;
        } else if (contextData.containsKey('selected_actor_ids')) {
          itemType = 'actor';
          final actorIds = contextData['selected_actor_ids'];
          itemCount = actorIds is List ? actorIds.length : 0;
        } else if (contextData.containsKey('unmatched_files')) {
          itemType = 'media';
          final unmatchedFiles = contextData['unmatched_files'];
          final unmatchedGroups = contextData['unmatched_groups'];
          int filesCount = unmatchedFiles is List ? unmatchedFiles.length : 0;
          int groupsCount = unmatchedGroups is List ? unmatchedGroups.length : 0;
          itemCount = filesCount + groupsCount;
        }
        
        if (itemCount > 0) {
          // 判断是否是未匹配文件刮削
          final isUnmatchedFileScrape = contextData.containsKey('unmatched_files');
          
          return EnhancedDialogRenderer.renderBatchScrapeDialog(
            context: context,
            title: title,
            itemCount: itemCount,
            itemType: itemType,
            showScrapeModeSelector: !isUnmatchedFileScrape,  // 未匹配文件刮削时隐藏刮削方式选择器
            onConfirm: (concurrent, scrapeMode, contentType) {
              final formData = <String, dynamic>{
                'concurrent': concurrent,
                'scrape_mode': scrapeMode,  // 刮削方式：code/title/series_date/series_title
                'content_type': contentType,  // 内容类型：Scene/Movie
                // mode 由 YAML 配置中的 action.body.mode 提供
              };
              
              final mainAction = dialog.actions.firstWhere(
                (action) => action.type == 'call_api',
                orElse: () => dialog.actions.first,
              );
              
              // 不要在这里关闭对话框
              
              _handleDialogAction(
                mainAction,
                context,
                locale,
                contextData,
                formData,
              );
            },
            onCancel: () {
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          );
        }
      }

      // 使用原有的智能对话框渲染
      final formKey = GlobalKey<FormState>();
      final formData = <String, dynamic>{};

      for (final field in dialog.fields) {
        if (field.defaultValue != null) {
          formData[field.id] = field.defaultValue;
        }
      }

      return _SmartDialog(
        dialog: dialog,
        formKey: formKey,
        formData: formData,
        contextData: contextData,
        locale: locale,
        title: title,
      );
    } catch (e) {
      print('❌ Error rendering dialog ${dialog.id}: $e');
      return AlertDialog(
        title: const Text('Error'),
        content: Text('Failed to render dialog: $e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
  }

  /// 获取图标
  static IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'download_outlined':
        return Icons.download_outlined;
      case 'refresh':
        return Icons.refresh;
      case 'search':
        return Icons.search;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'add':
        return Icons.add;
      case 'settings':
        return Icons.settings;
      case 'info':
        return Icons.info;
      default:
        return Icons.extension;
    }
  }

  /// 处理UI动作
  static Future<void> _handleAction(
    UIAction action,
    BuildContext context,
    Map<String, dynamic>? contextData,
  ) async {
    print('🎬 Handling action: ${action.type}');
    if (contextData != null && contextData.isNotEmpty) {
      print('   Context data: $contextData');
    }
    
    switch (action.type) {
      case 'show_dialog':
        print('   Opening dialog: ${action.dialogId}');
        final registry = PluginUIRegistry();
        final dialog = registry.getDialog(action.dialogId!);
        if (dialog != null) {
          showDialog(
            context: context,
            builder: (context) =>
                renderDialog(dialog, context, contextData: contextData),
          );
        } else {
          print('❌ Error: Dialog not found: ${action.dialogId}');
        }
        break;

      case 'call_api':
        print('   Calling API: ${action.apiEndpoint}');
        await _callAPI(action, context, contextData, {});
        break;

      case 'close':
        print('   Closing dialog');
        if (context.mounted) {
          Navigator.pop(context);
        }
        break;
    }
  }

  /// 处理对话框动作
  static Future<void> _handleDialogAction(
    UIDialogAction action,
    BuildContext context,
    String locale,
    Map<String, dynamic>? contextData,
    Map<String, dynamic> formData,
  ) async {
    if (action.type == 'call_api') {
      await _callAPI(
        UIAction(
          type: 'call_api',
          apiEndpoint: action.apiEndpoint,
          method: action.method,
          body: action.body,
          params: action.params,
          showProgress: action.showProgress,
          progressMessage: action.progressMessage,
          successMessage: action.successMessage,
          errorMessage: action.errorMessage,
          onSuccess: action.onSuccess,
        ),
        context,
        contextData,
        formData,
      );
    }
  }

  /// Dio实例复用（避免重复创建）
  static Dio _createDio(String baseUrl) {
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  /// 调用API
  static Future<void> _callAPI(
    UIAction action,
    BuildContext context,
    Map<String, dynamic>? contextData,
    Map<String, dynamic> formData,
  ) async {
    // 将locale变量移到try块外部，确保catch块可以访问
    final locale = context.mounted ? Localizations.localeOf(context).languageCode : 'en';
    
    // 使用 Consumer 来访问 Provider，而不是创建新的 ProviderContainer
    final container = ProviderScope.containerOf(context);
    final baseUrl = container.read(apiBaseUrlProvider);
    final fullApiUrl = getFullApiUrl(baseUrl);
    
    print('🌐 API Call Started');
    print('   Base URL: $baseUrl');
    print('   Full API URL: $fullApiUrl');
    print('   Endpoint: ${action.apiEndpoint}');
    print('   Method: ${action.method}');
    
    try {
      print('🌐 API Call Started');
      print('   Endpoint: ${action.apiEndpoint}');
      print('   Method: ${action.method}');
      
      final isAutoScrape = action.apiEndpoint?.contains('/scan/auto-scrape') ?? false;
      
      if (action.showProgress && context.mounted) {
        final progressMsg =
            action.getLocalizedMessage(action.progressMessage, locale) ??
                'Loading...';
        print('   Showing progress: $progressMsg');
        
        showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,  // 使用 root navigator
          builder: (dialogContext) => PopScope(  // 使用 dialogContext 而不是 context
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        strokeWidth: 6,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(dialogContext).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      progressMsg,
                      style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      locale == 'zh' ? '请稍候...' : 'Please wait...',
                      style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // 空安全检查：确保apiEndpoint不为空
      if (action.apiEndpoint == null || action.apiEndpoint!.isEmpty) {
        throw Exception('API endpoint is empty');
      }
      
      String apiUrl = action.apiEndpoint!;
      final params = <String, dynamic>{};
      
      if (contextData != null) {
        print('   Adding context data...');
        contextData.forEach((key, value) {
          // 跳过函数类型的值(如 exit_selection_mode 回调)
          if (value is Function) {
            print('     Skipping function: $key');
            return;
          }
          
          String paramKey = key;
          if (key == 'selected_media_ids') {
            paramKey = 'media_ids';
          } else if (key == 'selected_actor_ids') {
            paramKey = 'actor_ids';
          } else if (key == 'unmatched_files') {
            paramKey = 'unmatched_files';
          } else if (key == 'unmatched_groups') {
            paramKey = 'unmatched_groups';
          }
          
          params[paramKey] = value;
          print('     $key -> $paramKey: $value');
        });
      }
      
      if (action.params != null) {
        print('   Building parameters from form data...');
        for (final param in action.params!) {
          final fieldValue = formData[param.field];
          if (fieldValue != null) {
            dynamic convertedValue = fieldValue;
            if (fieldValue is String) {
              if (fieldValue.toLowerCase() == 'true') {
                convertedValue = true;
              } else if (fieldValue.toLowerCase() == 'false') {
                convertedValue = false;
              }
            }
            params[param.param] = convertedValue;
            print('     ${param.param}: $convertedValue (原始值: $fieldValue)');
          }
        }
      }

      print('   Replacing URL placeholders...');
      print('   Original URL: $apiUrl');
      
      // 统一处理URL占位符替换（避免重复处理）
      final allReplacementData = <String, dynamic>{
        ...?contextData,
        ...params,
        ...formData,
      };
      
      print('   All replacement data keys: ${allReplacementData.keys.toList()}');
      print('   Looking for placeholders in URL: $apiUrl');
      
      allReplacementData.forEach((key, value) {
        if (value != null) {
          final placeholder = '{$key}';
          print('     Checking placeholder: $placeholder');
          if (apiUrl.contains(placeholder)) {
            final valueStr = value.toString();
            final encodedValue = Uri.encodeComponent(valueStr);
            apiUrl = apiUrl.replaceAll(placeholder, encodedValue);
            print('     ✓ Replaced $placeholder -> $valueStr (encoded: $encodedValue)');
          } else {
            print('     ✗ Placeholder $placeholder not found in URL');
          }
        }
      });

      print('   Final URL: $apiUrl');
      print('   Parameters: $params');
      
      // 将 formData 中的额外字段加入到 params（如 scrape_mode）
      // 注意：不覆盖已有的字段，action.body 中的 mode 优先
      formData.forEach((key, value) {
        if (value != null && !params.containsKey(key)) {
          params[key] = value;
          print('     formData.$key: $value');
        }
      });

      // 过滤掉只用于 URL 占位符的参数（不应该出现在请求体中）
      // 这些参数已经在 URL 中使用了，不需要再放到请求体里
      final urlPlaceholderKeys = <String>{};
      final originalApiUrl = action.apiEndpoint ?? '';
      allReplacementData.forEach((key, value) {
        if (originalApiUrl.contains('{$key}')) {
          urlPlaceholderKeys.add(key);
        }
      });
      
      // 创建一个新的 params 副本，排除 URL 占位符参数
      final bodyParams = <String, dynamic>{};
      params.forEach((key, value) {
        if (!urlPlaceholderKeys.contains(key)) {
          bodyParams[key] = value;
        } else {
          print('     Excluding URL placeholder from body: $key');
        }
      });

      print('⏳ Executing API call...');
      print('   Body parameters (excluding URL placeholders): $bodyParams');
      print('   action.body: ${action.body}');
      print('   Final request body: ${<dynamic, dynamic>{...bodyParams, ...?action.body}}');
      
      // 使用已经从 context 获取的 fullApiUrl
      final dio = _createDio(fullApiUrl);
      
      Response response;
      final method = action.method?.toUpperCase() ?? 'GET';
      
      switch (method) {
        case 'GET':
          response = await dio.get(apiUrl, queryParameters: params);
          break;
        case 'POST':
          // action.body 优先级最高，覆盖 bodyParams 中的同名字段
          response = await dio.post(apiUrl, data: {...bodyParams, ...?action.body});
          break;
        case 'PUT':
          // action.body 优先级最高，覆盖 bodyParams 中的同名字段
          response = await dio.put(apiUrl, data: {...bodyParams, ...?action.body});
          break;
        case 'DELETE':
          // action.body 优先级最高，覆盖 bodyParams 中的同名字段
          response = await dio.delete(apiUrl, data: {...bodyParams, ...?action.body});
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      print('✅ API call completed successfully');
      print('   Status: ${response.statusCode}');
      print('   Response: ${response.data}');
      
      print('🔍 Checking response type...');
      print('   isAutoScrape: ${action.apiEndpoint?.contains('/scan/auto-scrape')}');
      print('   isMagnetSearch check: ${action.apiEndpoint?.contains('/scrape/magnets/')}');
      print('   isBatchMediaScrape check: ${action.apiEndpoint?.contains('/scrape/media/batch')}');
      print('   isBatchActorScrape check: ${action.apiEndpoint?.contains('/scrape/actor/batch')}');
      
      final isMagnetSearch = (action.apiEndpoint?.contains('/scrape/magnets/') ?? false) && 
                             !(action.apiEndpoint?.contains('/progress') ?? false);
      
      // 检测批量媒体刮削（/scrape/media/batch 但不是 /progress）
      final isBatchMediaScrape = (action.apiEndpoint?.contains('/scrape/media/batch') ?? false) && 
                                  !(action.apiEndpoint?.contains('/progress') ?? false);
      
      // 检测批量演员刮削（/scrape/actor/batch 但不是 /progress）
      final isBatchActorScrape = (action.apiEndpoint?.contains('/scrape/actor/batch') ?? false) && 
                                  !(action.apiEndpoint?.contains('/progress') ?? false);
      
      print('   isMagnetSearch: $isMagnetSearch');
      print('   isBatchMediaScrape: $isBatchMediaScrape');
      print('   isBatchActorScrape: $isBatchActorScrape');
      print('   isAutoScrape: $isAutoScrape');
      
      // 处理批量演员刮削（返回 session_id，复用媒体刮削进度对话框）
      if (isBatchActorScrape && context.mounted) {
        print('🔍 Checking batch actor scrape session...');
        final sessionId = response.data['session_id'] as String?;
        print('   sessionId: $sessionId');
        if (sessionId != null) {
          if (action.showProgress) {
            print('🔴 Closing initial progress dialog for batch actor scrape...');
            try {
              Navigator.of(context, rootNavigator: true).pop();
              print('✅ Initial progress dialog closed');
            } catch (e) {
              print('⚠️ Failed to close initial progress dialog: $e');
            }
          }
          
          // 显示演员刮削进度对话框（复用媒体刮削进度对话框）
          EnhancedDialogRenderer.showMediaScrapeProgressDialog(
            context: context,
            sessionId: sessionId,
            locale: locale,
            onComplete: (responseData) {
              // 进度对话框已经在内部关闭了
              // 关闭批量刮削对话框
              print('🎯 Batch actor scrape completed, closing batch dialog...');
              if (context.mounted) {
                Navigator.pop(context);
                print('✅ Batch dialog closed');
                
                // 立即刷新列表数据
                print('🔄 刷新列表数据...');
                final container = ProviderScope.containerOf(context, listen: false);
                clearAspectRatioCache();
                container.invalidate(actorListProvider);
                print('✅ 列表数据已刷新');
              }
              // 显示结果（复用媒体刮削结果显示）
              _showBatchMediaScrapeResults(context, responseData, locale, contextData: contextData);
            },
          );
          return;
        }
        print('   No session_id, continuing...');
      }
      
      // 处理批量媒体刮削（返回 session_id）
      if (isBatchMediaScrape && context.mounted) {
        print('🔍 Checking batch media scrape session...');
        final sessionId = response.data['session_id'] as String?;
        print('   sessionId: $sessionId');
        if (sessionId != null) {
          if (action.showProgress) {
            print('🔴 Closing initial progress dialog for batch media scrape...');
            try {
              Navigator.of(context, rootNavigator: true).pop();
              print('✅ Initial progress dialog closed');
            } catch (e) {
              print('⚠️ Failed to close initial progress dialog: $e');
            }
          }
          
          // 显示媒体刮削进度对话框
          EnhancedDialogRenderer.showMediaScrapeProgressDialog(
            context: context,
            sessionId: sessionId,
            locale: locale,
            onComplete: (responseData) {
              // 进度对话框已经在内部关闭了
              // 关闭批量刮削对话框
              print('🎯 Batch media scrape completed, closing batch dialog...');
              if (context.mounted) {
                Navigator.pop(context);
                print('✅ Batch dialog closed');
                
                // 立即刷新列表数据
                print('🔄 刷新列表数据...');
                final container = ProviderScope.containerOf(context, listen: false);
                clearAspectRatioCache();
                container.invalidate(mediaListProvider);
                container.invalidate(actorListProvider);
                print('✅ 列表数据已刷新');
              }
              // 显示结果
              _showBatchMediaScrapeResults(context, responseData, locale, contextData: contextData);
            },
          );
          return;
        }
        print('   No session_id, continuing...');
      }
      
      if (isAutoScrape && context.mounted) {
        print('🔍 Checking auto-scrape session...');
        final sessionId = response.data['session_id'] as String?;
        print('   sessionId: $sessionId');
        if (sessionId != null) {
          if (action.showProgress) {
            print('🔴 Closing initial progress dialog for auto-scrape...');
            try {
              Navigator.of(context, rootNavigator: true).pop();
              print('✅ Initial progress dialog closed');
            } catch (e) {
              print('⚠️ Failed to close initial progress dialog: $e');
            }
          }
          
          final progressMsg = action.getLocalizedMessage(action.progressMessage, locale) ?? 'Loading...';
          showDialog(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (dialogContext) => PopScope(
              canPop: false,
              child: _AutoScrapeProgressDialog(
                sessionId: sessionId,
                progressMessage: progressMsg,
                locale: locale,
                onComplete: (responseData) {
                  // 注意：进度对话框已经在 _AutoScrapeProgressDialog 内部关闭了
                  // 这里只需要关闭批量刮削对话框
                  print('🎯 Auto-scrape completed, closing batch dialog...');
                  if (context.mounted) {
                    Navigator.pop(context);
                    print('✅ Batch dialog closed');
                    
                    // 立即刷新列表数据
                    print('🔄 刷新列表数据...');
                    final container = ProviderScope.containerOf(context, listen: false);
                    clearAspectRatioCache();
                    container.invalidate(mediaListProvider);
                    print('✅ 列表数据已刷新');
                  }
                  _showAutoScrapeResults(context, responseData, locale);
                },
              ),
            ),
          );
          return;
        }
        print('   No session_id, continuing...');
      }
      
      if (isMagnetSearch && context.mounted) {
        print('🔍 Checking magnet search session...');
        final sessionId = response.data['session_id'] as String?;
        print('   sessionId: $sessionId');
        if (sessionId != null) {
          if (action.showProgress) {
            print('🔴 Closing initial progress dialog for magnet search...');
            try {
              Navigator.of(context, rootNavigator: true).pop();
              print('✅ Initial progress dialog closed');
            } catch (e) {
              print('⚠️ Failed to close initial progress dialog: $e');
            }
          }
          
          showDialog(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (dialogContext) => PopScope(
              canPop: false,
              child: EnhancedMagnetSearchProgressDialog(
                sessionId: sessionId,
                locale: locale,
                onComplete: (responseData) {
                  // 注意：进度对话框已经在内部关闭了
                  // 不要关闭磁力刮削对话框，直接显示结果对话框在上面
                  print('🎯 Magnet search completed, showing results dialog...');
                  
                  // 显示结果对话框（在磁力刮削对话框上方）
                  _showResultsDialog(context, responseData, locale, contextData);
                },
              ),
            ),
          );
          return;
        }
        print('   No session_id, continuing...');
      }
      
      print('🚀 Continuing to progress dialog closure...');
      print('   Checking conditions:');
      print('   action.showProgress: ${action.showProgress}');
      print('   isAutoScrape: $isAutoScrape');
      
      if (action.showProgress && !isAutoScrape) {
        print('🔴 Closing progress dialog...');
        try {
          // 使用 rootNavigator 确保关闭的是进度对话框
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            print('✅ Progress dialog closed');
          } else {
            print('⚠️ Context not mounted, trying alternative approach...');
            // 如果 context 不可用，尝试使用全局导航器
            final navigatorState = Navigator.of(context, rootNavigator: true);
            if (navigatorState.canPop()) {
              navigatorState.pop();
              print('✅ Progress dialog closed via alternative approach');
            }
          }
        } catch (e) {
          print('⚠️ Failed to close progress dialog: $e');
        }
      } else {
        print('❌ Skipping progress dialog closure');
        print('   Reason: action.showProgress=${action.showProgress}, isAutoScrape=$isAutoScrape');
      }

      if (isAutoScrape && context.mounted) {
        _showAutoScrapeResults(context, response.data, locale);
      }

      if (action.successMessage != null && context.mounted && !isAutoScrape) {
        print('📢 Showing success message...');
        final successMsg =
            action.getLocalizedMessage(action.successMessage, locale) ??
                'Success';
        context.showSuccess(successMsg);
      }

      if (context.mounted) {
        print('🎯 Handling onSuccess: ${action.onSuccess}');
        if (action.onSuccess == 'close_dialog_and_refresh') {
          print('   close_dialog_and_refresh - 关闭对话框并刷新页面数据');
          
          // 先关闭刮削对话框（如果还在）
          if (context.mounted) {
            try {
              Navigator.of(context).pop();
              print('✅ Scrape dialog closed');
            } catch (e) {
              print('⚠️ Failed to close scrape dialog: $e');
            }
          }
          
          // 然后刷新数据
          if (context.mounted) {
            final container = ProviderScope.containerOf(context, listen: false);
            
            if (contextData != null) {
              String? actorId;
              if (contextData.containsKey('actor_id')) {
                actorId = contextData['actor_id'] as String?;
              } else if (contextData.containsKey('actor_ids')) {
                final actorIds = contextData['actor_ids'];
                if (actorIds is List && actorIds.isNotEmpty) {
                  actorId = actorIds.first as String?;
                }
              }
              
              if (actorId != null) {
                print('   刷新演员详情页: $actorId');
                container.invalidate(actorDetailProvider(actorId));
                container.invalidate(actorMediaListProvider(actorId));
                container.invalidate(actorListProvider);
              }
              
              String? mediaId;
              if (contextData.containsKey('media_id')) {
                mediaId = contextData['media_id'] as String?;
              } else if (contextData.containsKey('selected_media_ids')) {
                final mediaIds = contextData['selected_media_ids'];
                if (mediaIds is List && mediaIds.isNotEmpty) {
                  mediaId = mediaIds.first as String?;
                }
              }
              
              if (mediaId != null) {
                print('   刷新媒体详情页: $mediaId');
                // 清除图片缓存
                clearAspectRatioCache();
                container.invalidate(mediaDetailProvider(mediaId));
                container.invalidate(mediaListProvider);
              }
            }
          }
        } else if (action.onSuccess == 'refresh_page') {
          print('   refresh_page - 刷新页面数据');
          
          // 注意：进度对话框已经在前面关闭了（第810行）
          // 这里不需要再关闭任何对话框
          
          // 获取 ProviderContainer
          if (context.mounted) {
            final container = ProviderScope.containerOf(context, listen: false);
            
            // 清除图片比例缓存，确保封面图和演员头像重新加载
            clearAspectRatioCache();
            print('✅ 图片缓存已清除');
            
            // 刷新演员详情页数据（如果在演员详情页）
            // 支持两种情况：单个演员(actor_id)和批量操作(actor_ids)
            if (contextData != null) {
              String? actorId;
              
              // 情况1：单个演员详情页
              if (contextData.containsKey('actor_id')) {
                actorId = contextData['actor_id'] as String;
              }
              // 情况2：批量操作但只有一个演员（可能是从详情页触发的）
              else if (contextData.containsKey('actor_ids')) {
                final actorIds = contextData['actor_ids'] as List<dynamic>;
                if (actorIds.length == 1) {
                  actorId = actorIds[0] as String;
                }
              }
              
              if (actorId != null) {
                print('   刷新演员详情: $actorId');
                container.invalidate(actorDetailProvider(actorId));
                container.invalidate(actorMediaListProvider(actorId));
                // 同时刷新演员列表，以便返回列表页时看到更新
                container.invalidate(actorListProvider);
              }
            }
            
            // 刷新媒体详情页数据（如果在媒体详情页）
            // 支持两种情况：单个媒体(media_id)和批量操作(selected_media_ids)
            if (contextData != null) {
              String? mediaId;
              
              // 情况1：单个媒体详情页
              if (contextData.containsKey('media_id')) {
                mediaId = contextData['media_id'] as String;
              }
              // 情况2：批量操作但只有一个媒体（可能是从详情页触发的）
              else if (contextData.containsKey('selected_media_ids')) {
                final selectedIds = contextData['selected_media_ids'] as List<dynamic>;
                if (selectedIds.length == 1) {
                  mediaId = selectedIds[0] as String;
                }
              }
              
              if (mediaId != null) {
                print('   刷新媒体详情: $mediaId');
                container.invalidate(mediaDetailProvider(mediaId));
                // 刷新媒体列表（主页和其他使用媒体列表的地方）
                container.invalidate(mediaListProvider);
              }
            }
          }
        } else if (action.onSuccess == 'close') {
          print('   close - 关闭对话框');
          Navigator.pop(context);
        } else if (action.onSuccess == 'show_results') {
          print('   show_results - 关闭对话框并显示结果');
          Navigator.pop(context);
          _showResultsDialog(context, response.data, locale, contextData);
        }
      }
    } catch (e) {
      print('❌ API call failed: ${action.apiEndpoint}');
      print('   Error: $e');
      
      if (action.showProgress && context.mounted) {
        Navigator.pop(context);
      }

      String errorMsg;
      if (action.errorMessage != null) {
        errorMsg = action.getLocalizedMessage(action.errorMessage, locale) ?? 'Error';
      } else {
        if (e.toString().contains('SocketException') || 
            e.toString().contains('NetworkException')) {
          errorMsg = locale == 'zh' ? '网络连接失败' : 'Network connection failed';
        } else if (e.toString().contains('TimeoutException')) {
          errorMsg = locale == 'zh' ? '请求超时' : 'Request timeout';
        } else if (e.toString().contains('FormatException')) {
          errorMsg = locale == 'zh' ? '数据格式错误' : 'Invalid data format';
        } else if (e.toString().contains('401') || e.toString().contains('403')) {
          errorMsg = locale == 'zh' ? '权限不足' : 'Permission denied';
        } else if (e.toString().contains('404')) {
          errorMsg = locale == 'zh' ? '资源未找到' : 'Resource not found';
        } else if (e.toString().contains('500')) {
          errorMsg = locale == 'zh' ? '服务器错误' : 'Server error';
        } else {
          errorMsg = locale == 'zh' ? '操作失败' : 'Operation failed';
        }
      }
      
      if (context.mounted) {
        SnackBarUtils.showWithAction(
          context,
          '$errorMsg: ${e.toString().split('\n').first}',
          actionLabel: locale == 'zh' ? '关闭' : 'Close',
          onAction: () {
            if (context.mounted) {
              context.hideSnackBar();
            }
          },
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      // 不再需要释放 container，因为我们使用的是 context 中的
    }
  }

  /// 显示自动刮削结果对话框
  static void _showAutoScrapeResults(
    BuildContext context,
    dynamic responseData,
    String locale,
  ) {
    if (!context.mounted) return;
    
    final data = responseData as Map<String, dynamic>;
    final success = data['success'] as bool? ?? false;
    final scrapedCount = data['scraped_count'] as int? ?? 0;
    final failedCount = data['failed_count'] as int? ?? 0;
    final results = data['results'] as List<dynamic>? ?? [];
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(locale == 'zh' ? '刮削完成' : 'Scraping Complete'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      locale == 'zh' ? '成功: $scrapedCount' : 'Success: $scrapedCount',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              if (failedCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        locale == 'zh' ? '失败: $failedCount' : 'Failed: $failedCount',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              
              if (results.isNotEmpty) ...[
                Text(
                  locale == 'zh' ? '详细结果:' : 'Details:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final result = results[index] as Map<String, dynamic>;
                      final fileName = result['file_name'] as String? ?? '';
                      final resultSuccess = result['success'] as bool? ?? false;
                      final error = result['error'] as String?;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            resultSuccess ? Icons.check_circle : Icons.error,
                            color: resultSuccess ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          title: Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: error != null
                              ? Text(
                                  error,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              // 先刷新数据（在关闭对话框之前，确保context有效）
              if (context.mounted) {
                print('🔄 刷新列表数据...');
                final container = ProviderScope.containerOf(context, listen: false);
                container.invalidate(mediaListProvider);
                container.invalidate(actorListProvider);
                print('✅ 列表数据已刷新');
              }
              
              // 然后关闭对话框
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);  // 关闭结果对话框
              }
              
              // 使用延迟确保结果对话框完全关闭后再关闭批量刮削对话框
              Future.delayed(const Duration(milliseconds: 100), () {
                if (context.mounted) {
                  try {
                    Navigator.pop(context);  // 关闭批量刮削对话框
                    print('✅ 批量刮削对话框已关闭');
                  } catch (e) {
                    print('⚠️ 关闭批量刮削对话框失败: $e');
                  }
                }
              });
            },
            child: Text(locale == 'zh' ? '完成' : 'Done'),
          ),
        ],
      ),
    );
  }

  /// 显示批量媒体刮削结果对话框
  static void _showBatchMediaScrapeResults(
    BuildContext context,
    dynamic responseData,
    String locale, {
    Map<String, dynamic>? contextData,
  }) {
    if (!context.mounted) return;
    
    final data = responseData as Map<String, dynamic>;
    final successCount = data['success_count'] as int? ?? 0;
    final failedCount = data['failed_count'] as int? ?? 0;
    final message = data['message'] as String? ?? '';
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              failedCount == 0 ? Icons.check_circle : Icons.info,
              color: failedCount == 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(locale == 'zh' ? '刮削完成' : 'Scraping Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    locale == 'zh' ? '成功: $successCount' : 'Success: $successCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            if (failedCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      locale == 'zh' ? '失败: $failedCount' : 'Failed: $failedCount',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              // 先刷新数据
              if (context.mounted) {
                print('🔄 刷新列表数据...');
                final container = ProviderScope.containerOf(context, listen: false);
                
                // 清除图片比例缓存，确保页面重新渲染
                clearAspectRatioCache();
                print('✅ 图片缓存已清除');
                
                container.invalidate(mediaListProvider);
                container.invalidate(actorListProvider);
                print('✅ 列表数据已刷新');
              }
              
              // 关闭对话框
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              
              // 调用退出多选模式的回调
              if (contextData != null && contextData.containsKey('exit_selection_mode')) {
                final exitCallback = contextData['exit_selection_mode'] as Function?;
                if (exitCallback != null) {
                  print('🔄 调用退出多选模式回调...');
                  exitCallback();
                  print('✅ 已退出多选模式');
                }
              }
            },
            child: Text(locale == 'zh' ? '完成' : 'Done'),
          ),
        ],
      ),
    );
  }

  /// 显示搜索结果对话框
  static Future<void> _showResultsDialog(
    BuildContext context,
    dynamic responseData,
    String locale,
    Map<String, dynamic>? contextData,
  ) async {
    if (!context.mounted) return;
    
    final data = responseData as Map<String, dynamic>;
    final success = data['success'] as bool? ?? false;
    
    if (!success) {
      final error = data['error'] as String? ?? 'Unknown error';
      context.showError(error);
      return;
    }
    
    final results = data['data'] as List<dynamic>? ?? [];
    
    if (results.isEmpty) {
      context.showWarning(locale == 'zh' ? '未找到结果' : 'No results found');
      return;
    }
    
    await showDialog(
      context: context,
      builder: (dialogContext) => _MagnetResultsSelectionDialog(
        results: results,
        locale: locale,
        contextData: contextData,
      ),
    );
  }
}

/// 磁力链接结果选择对话框
class _MagnetResultsSelectionDialog extends StatefulWidget {
  final List<dynamic> results;
  final String locale;
  final Map<String, dynamic>? contextData;

  const _MagnetResultsSelectionDialog({
    required this.results,
    required this.locale,
    this.contextData,
  });

  @override
  State<_MagnetResultsSelectionDialog> createState() =>
      _MagnetResultsSelectionDialogState();
}

class _MagnetResultsSelectionDialogState
    extends State<_MagnetResultsSelectionDialog> {
  final Set<int> _selectedIndices = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.locale == 'zh' ? '选择磁力链接' : 'Select Magnet Links',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.locale == 'zh'
                  ? '找到 ${widget.results.length} 个结果，已选择 ${_selectedIndices.length} 个'
                  : 'Found ${widget.results.length} results, ${_selectedIndices.length} selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.results.length,
                itemBuilder: (context, index) {
                  final result = widget.results[index] as Map<String, dynamic>;
                  final title = result['title'] as String? ?? '';
                  final size = result['size'] as String? ?? '';
                  final date = result['date'] as String? ?? '';
                  final magnet = result['magnet'] as String? ?? '';
                  final isSelected = _selectedIndices.contains(index);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : null,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedIndices.remove(index);
                          } else {
                            _selectedIndices.add(index);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: colorScheme.primary,
                                    size: 20,
                                  ),
                                if (isSelected) const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (size.isNotEmpty) ...[
                                  Icon(
                                    Icons.storage,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    size,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                if (date.isNotEmpty) ...[
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    date,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(widget.locale == 'zh' ? '取消' : 'Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _selectedIndices.isEmpty
                      ? null
                      : () async {
                          // 获取media_id
                          final mediaId = widget.contextData?['media_id'] as String?;
                          if (mediaId == null) {
                            context.showError(
                              widget.locale == 'zh' ? '媒体ID不存在' : 'Media ID not found',
                            );
                            return;
                          }
                          
                          try {
                            final container = ProviderScope.containerOf(context);
                            final baseUrl = container.read(apiBaseUrlProvider);
                            final fullApiUrl = getFullApiUrl(baseUrl);
                            
                            final dio = Dio(BaseOptions(
                              baseUrl: fullApiUrl,
                              connectTimeout: const Duration(seconds: 10),
                              receiveTimeout: const Duration(seconds: 10),
                            ));
                            
                            // 先获取当前媒体的download_links
                            final getResponse = await dio.get('/media/$mediaId');
                            final mediaData = getResponse.data['data'] as Map<String, dynamic>;
                            final currentLinks = (mediaData['download_links'] as List<dynamic>?) ?? [];
                            
                            // 构建新的下载链接列表
                            final newLinks = <Map<String, dynamic>>[];
                            int addedCount = 0;
                            int duplicateCount = 0;
                            
                            for (final index in _selectedIndices) {
                              final result = widget.results[index] as Map<String, dynamic>;
                              final magnetLink = result['magnet'] as String? ?? result['magnet_link'] as String? ?? '';
                              final title = result['title'] as String? ?? '';
                              final size = result['size'] as String? ?? '';
                              
                              if (magnetLink.isEmpty) continue;
                              
                              // 检查是否已存在相同的磁力链接
                              final isDuplicate = currentLinks.any((link) {
                                final linkMap = link as Map<String, dynamic>;
                                return linkMap['url'] == magnetLink;
                              });
                              
                              if (isDuplicate) {
                                duplicateCount++;
                                continue;
                              }
                              
                              // 构建下载链接对象
                              newLinks.add({
                                'name': title.isNotEmpty ? title : '磁力链接',
                                'url': magnetLink,
                                'link_type': 'magnet',
                                'size': size.isNotEmpty ? size : null,
                                'password': null,
                              });
                              addedCount++;
                            }
                            
                            if (newLinks.isEmpty) {
                              if (context.mounted) {
                                if (duplicateCount > 0) {
                                  context.showWarning(
                                    widget.locale == 'zh'
                                        ? '所有选中的磁力链接都已存在'
                                        : 'All selected magnet links already exist',
                                  );
                                } else {
                                  context.showWarning(
                                    widget.locale == 'zh'
                                        ? '没有有效的磁力链接'
                                        : 'No valid magnet links',
                                  );
                                }
                              }
                              return;
                            }
                            
                            // 添加新的磁力链接
                            final updatedLinks = [...currentLinks, ...newLinks];
                            
                            // 更新媒体
                            await dio.put('/media/$mediaId', data: {
                              'download_links': updatedLinks,
                            });
                            
                            if (context.mounted) {
                              // 显示成功消息
                              String message = widget.locale == 'zh'
                                  ? '已保存 $addedCount 个磁力链接'
                                  : 'Saved $addedCount magnet link${addedCount > 1 ? 's' : ''}';
                              if (duplicateCount > 0) {
                                message += widget.locale == 'zh'
                                    ? '，跳过 $duplicateCount 个重复链接'
                                    : ', skipped $duplicateCount duplicate${duplicateCount > 1 ? 's' : ''}';
                              }
                              context.showSuccess(message);
                              
                              // 关闭结果对话框
                              Navigator.pop(context);
                              
                              // 刷新媒体详情页
                              final ref = ProviderScope.containerOf(context);
                              ref.invalidate(mediaDetailProvider(mediaId));
                              
                              // 延迟后关闭磁力刮削对话框
                              Future.delayed(const Duration(milliseconds: 100), () {
                                if (context.mounted) {
                                  try {
                                    Navigator.pop(context);
                                    print('✅ Magnet scrape dialog closed after save');
                                  } catch (e) {
                                    print('⚠️ Failed to close magnet scrape dialog: $e');
                                  }
                                }
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              context.showError(
                                widget.locale == 'zh'
                                    ? '保存失败: $e'
                                    : 'Save failed: $e',
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.save),
                  label: Text(widget.locale == 'zh' ? '保存' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 智能对话框 - 根据字段类型动态生成表单
class _SmartDialog extends StatefulWidget {
  final UIDialog dialog;
  final GlobalKey<FormState> formKey;
  final Map<String, dynamic> formData;
  final Map<String, dynamic>? contextData;
  final String locale;
  final String title;

  const _SmartDialog({
    required this.dialog,
    required this.formKey,
    required this.formData,
    this.contextData,
    required this.locale,
    required this.title,
  });

  @override
  State<_SmartDialog> createState() => _SmartDialogState();
}

class _SmartDialogState extends State<_SmartDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: widget.formKey,
          child: ListView(
            shrinkWrap: true,
            children: widget.dialog.fields.map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildField(field),
              );
            }).toList(),
          ),
        ),
      ),
      actions: widget.dialog.actions.map((action) {
        return TextButton(
          onPressed: () {
            if (action.type == 'close') {
              Navigator.pop(context);
            } else if (action.type == 'call_api') {
              if (widget.formKey.currentState!.validate()) {
                widget.formKey.currentState!.save();
                Navigator.pop(context);
                PluginUIRenderer._handleDialogAction(
                  action,
                  context,
                  widget.locale,
                  widget.contextData,
                  widget.formData,
                );
              }
            }
          },
          child: Text(action.getLocalizedLabel(widget.locale)),
        );
      }).toList(),
    );
  }

  Widget _buildField(UIField field) {
    final label = field.getLocalizedLabel(widget.locale);
    final hint = field.getLocalizedHint(widget.locale);

    switch (field.type) {
      case 'text':
        return TextFormField(
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          initialValue: widget.formData[field.id]?.toString() ?? '',
          validator: field.required
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return widget.locale == 'zh' ? '此字段为必填项' : 'This field is required';
                  }
                  return null;
                }
              : null,
          onSaved: (value) {
            widget.formData[field.id] = value;
          },
        );

      case 'number':
        return TextFormField(
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          initialValue: widget.formData[field.id]?.toString() ?? '',
          validator: field.required
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return widget.locale == 'zh' ? '此字段为必填项' : 'This field is required';
                  }
                  if (int.tryParse(value) == null) {
                    return widget.locale == 'zh' ? '请输入有效的数字' : 'Please enter a valid number';
                  }
                  return null;
                }
              : null,
          onSaved: (value) {
            widget.formData[field.id] = int.tryParse(value ?? '');
          },
        );

      case 'checkbox':
        return CheckboxListTile(
          title: Text(label),
          subtitle: hint != null ? Text(hint) : null,
          value: widget.formData[field.id] as bool? ?? false,
          onChanged: (value) {
            setState(() {
              widget.formData[field.id] = value;
            });
          },
        );

      case 'radio':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            if (hint != null)
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ...field.options!.map((option) {
              return RadioListTile<String>(
                title: Text(option.getLocalizedLabel(widget.locale)),
                value: option.value,
                groupValue: widget.formData[field.id] as String?,
                onChanged: (value) {
                  setState(() {
                    widget.formData[field.id] = value;
                  });
                },
              );
            }).toList(),
          ],
        );

      case 'dropdown':
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          value: widget.formData[field.id] as String?,
          items: field.options!.map((option) {
            return DropdownMenuItem<String>(
              value: option.value,
              child: Text(option.getLocalizedLabel(widget.locale)),
            );
          }).toList(),
          validator: field.required
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return widget.locale == 'zh' ? '此字段为必填项' : 'This field is required';
                  }
                  return null;
                }
              : null,
          onChanged: (value) {
            setState(() {
              widget.formData[field.id] = value;
            });
          },
          onSaved: (value) {
            widget.formData[field.id] = value;
          },
        );

      default:
        return Text('Unsupported field type: ${field.type}');
    }
  }
}

/// 通用进度对话框基类
abstract class _BaseProgressDialog extends StatefulWidget {
  final String sessionId;
  final String progressMessage;
  final String locale;
  final Function(Map<String, dynamic>) onComplete;

  const _BaseProgressDialog({
    required this.sessionId,
    required this.progressMessage,
    required this.locale,
    required this.onComplete,
  });
}

abstract class _BaseProgressDialogState<T extends _BaseProgressDialog> extends State<T> {
  Timer? _timer;
  int _progress = 0;
  int _total = 0;
  String _currentItem = '';
  bool _isCompleted = false;
  ProviderContainer? _container;

  // 子类需要实现的抽象方法
  String get progressEndpoint;
  Duration get pollingInterval;
  IconData get progressIcon;
  String get itemLabel;
  
  // 解析进度数据
  void parseProgressData(Map<String, dynamic> data);
  
  // 构造完成结果
  Map<String, dynamic> buildCompletionResult(Map<String, dynamic> data);

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _container?.dispose();
    super.dispose();
  }

  void _startPolling() {
    print('🔄 Starting polling for session: ${widget.sessionId}');
    _timer = Timer.periodic(pollingInterval, (timer) async {
      if (!mounted) {
        print('⚠️ Widget not mounted, canceling timer');
        timer.cancel();
        return;
      }
      
      try {
        _container ??= ProviderContainer();
        final baseUrl = _container!.read(apiBaseUrlProvider);
        final fullApiUrl = getFullApiUrl(baseUrl);

        final dio = Dio(BaseOptions(
          baseUrl: fullApiUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

        print('📡 Polling progress: $progressEndpoint');
        final response = await dio.get(progressEndpoint);
        final responseData = response.data as Map<String, dynamic>;
        
        print('📊 Progress response: $responseData');

        if (!mounted) {
          print('⚠️ Widget unmounted after response');
          return;
        }

        // 让子类解析数据
        parseProgressData(responseData);
        
        print('📈 Progress: $_progress/$_total, Current: $_currentItem, Completed: $_isCompleted');

        if (_isCompleted) {
          print('✅ Task completed! Closing dialog...');
          _timer?.cancel();
          final results = buildCompletionResult(responseData);
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            print('✅ Progress dialog closed, calling onComplete');
            widget.onComplete(results);
          }
        }
      } catch (e) {
        print('❌ Error polling progress: $e');
        if (e is DioException) {
          print('   Status code: ${e.response?.statusCode}');
          print('   Response data: ${e.response?.data}');
        }
        if (mounted) {
          _timer?.cancel();
          Navigator.pop(context);
          print('❌ Closed progress dialog due to error');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressPercent = _total > 0 ? _progress / _total : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: progressPercent,
                      strokeWidth: 6,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                      backgroundColor: colorScheme.surfaceVariant,
                    ),
                  ),
                  progressIcon == Icons.percent
                      ? Text(
                          '${(progressPercent * 100).toInt()}%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        )
                      : Icon(
                          progressIcon,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.progressMessage,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$_progress / $_total $itemLabel',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (_currentItem.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getItemIcon(),
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentItem,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getItemIcon() {
    // 子类可以重写此方法来自定义图标
    return Icons.info;
  }
}

/// 自动刮削进度对话框
class _AutoScrapeProgressDialog extends _BaseProgressDialog {
  const _AutoScrapeProgressDialog({
    required super.sessionId,
    required super.progressMessage,
    required super.locale,
    required super.onComplete,
  });

  @override
  State<_AutoScrapeProgressDialog> createState() =>
      _AutoScrapeProgressDialogState();
}

class _AutoScrapeProgressDialogState extends _BaseProgressDialogState<_AutoScrapeProgressDialog> {
  @override
  String get progressEndpoint => '/scan/auto-scrape/progress/${widget.sessionId}';

  @override
  Duration get pollingInterval => const Duration(seconds: 1);

  @override
  IconData get progressIcon => Icons.percent;

  @override
  String get itemLabel => '';

  @override
  void parseProgressData(Map<String, dynamic> responseData) {
    setState(() {
      _progress = responseData['current'] as int? ?? 0;
      _total = responseData['total'] as int? ?? 0;
      _currentItem = responseData['file_name'] as String? ?? '';
      _isCompleted = responseData['status'] == 'completed';
    });
  }

  @override
  Map<String, dynamic> buildCompletionResult(Map<String, dynamic> responseData) {
    return {
      'success': responseData['scraped_count'] as int? ?? 0 > 0,
      'scraped_count': responseData['scraped_count'] as int? ?? 0,
      'failed_count': responseData['failed_count'] as int? ?? 0,
      'results': <Map<String, dynamic>>[],
    };
  }

  @override
  IconData _getItemIcon() => Icons.movie;
}

/// 磁力搜索进度对话框
class _MagnetSearchProgressDialog extends _BaseProgressDialog {
  const _MagnetSearchProgressDialog({
    required super.sessionId,
    required super.progressMessage,
    required super.locale,
    required super.onComplete,
  });

  @override
  State<_MagnetSearchProgressDialog> createState() =>
      _MagnetSearchProgressDialogState();
}

class _MagnetSearchProgressDialogState extends _BaseProgressDialogState<_MagnetSearchProgressDialog> {
  @override
  String get progressEndpoint => '/scrape/magnets/progress/${widget.sessionId}';

  @override
  Duration get pollingInterval => const Duration(milliseconds: 500);

  @override
  IconData get progressIcon => Icons.search;

  @override
  String get itemLabel => widget.locale == 'zh' ? '个网站' : 'sites';

  @override
  void parseProgressData(Map<String, dynamic> responseData) {
    final data = responseData['data'] as Map<String, dynamic>? ?? {};
    
    print('📊 Magnet search progress response: $responseData');
    print('   data field: $data');
    print('   completed field: ${data['completed']} (type: ${data['completed'].runtimeType})');

    final sitesStatus = data['sites_status'] as List<dynamic>? ?? [];
    final completedSites = sitesStatus.where((site) {
      final status = (site as Map<String, dynamic>)['status'] as String?;
      return status == 'completed' || status == 'failed';
    }).length;
    
    // 安全地解析 completed 字段，支持 bool、int、String 类型
    bool isCompleted = false;
    final completedValue = data['completed'];
    if (completedValue is bool) {
      isCompleted = completedValue;
    } else if (completedValue is int) {
      isCompleted = completedValue != 0;
    } else if (completedValue is String) {
      isCompleted = completedValue.toLowerCase() == 'true' || completedValue == '1';
    }
    
    setState(() {
      _progress = completedSites;
      _total = sitesStatus.length;
      _currentItem = data['current_site'] as String? ?? '';
      _isCompleted = isCompleted;
      
      print('   _isCompleted set to: $_isCompleted');
      print('   _progress: $_progress / $_total');
    });
  }

  @override
  Map<String, dynamic> buildCompletionResult(Map<String, dynamic> responseData) {
    final data = responseData['data'] as Map<String, dynamic>? ?? {};
    return {
      'success': true,
      'data': data['results'] ?? [],
    };
  }

  @override
  IconData _getItemIcon() => Icons.language;
}