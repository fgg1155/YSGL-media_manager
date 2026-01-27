import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../utils/snackbar_utils.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import '../config/app_config.dart';
import 'scrape_preferences.dart';

/// 生成系列+日期格式的工具函数
String? generateSeriesDateQuery(Map<String, dynamic> contextData) {
  final series = contextData['series'] as String?;
  final releaseDate = contextData['release_date'] as String?;
  
  // 检查字段是否存在且不为空（包括 null 和空字符串）
  if (series == null || series.isEmpty || 
      releaseDate == null || releaseDate.isEmpty) {
    return null;
  }
  
  try {
    final date = DateTime.parse(releaseDate);
    final year = date.year.toString().substring(2);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    
    // 处理系列名称：去除空格，保持每个单词首字母大写
    final seriesFormatted = series
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join('');
    
    return '$seriesFormatted.$year.$month.$day';
  } catch (e) {
    // 日期解析失败，返回 null
    return null;
  }
}

/// 生成系列+标题格式的工具函数
String? generateSeriesTitleQuery(Map<String, dynamic> contextData) {
  final series = contextData['series'] as String?;
  final title = contextData['title'] as String?;
  
  if (series == null || series.isEmpty || 
      title == null || title.isEmpty) {
    return null;
  }
  
  // 处理系列：首字母大写，移除空格（例如 "brazzers exxtra" -> "BrazzersExxtra"）
  final seriesFormatted = series
      .split(' ')
      .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join('');
  
  // 标题保持原样，不做任何转换
  // 格式：系列-标题（例如 "Brazzers-You Bet Your Ass! Vol. 2"）
  return '$seriesFormatted-$title';
}

/// 增强版对话框渲染器 - 专门用于批量刮削对话框的美观优化
class EnhancedDialogRenderer {
  /// 渲染增强版批量刮削对话框
  static Widget renderBatchScrapeDialog({
    required BuildContext context,
    required String title,
    required int itemCount,
    required String itemType, // 'media' 或 'actor'
    required Function(bool concurrent, String scrapeMode, String contentType) onConfirm,
    required VoidCallback onCancel,
    bool showScrapeModeSelector = true,  // 新增：是否显示刮削方式选择器
  }) {
    return _EnhancedBatchScrapeDialog(
      title: title,
      itemCount: itemCount,
      itemType: itemType,
      onConfirm: onConfirm,
      onCancel: onCancel,
      showScrapeModeSelector: showScrapeModeSelector,
    );
  }

  /// 渲染增强版单个刮削对话框（详情页）
  static Widget renderSingleScrapeDialog({
    required BuildContext context,
    required String title,
    required Map<String, dynamic> contextData,
    required Function(String scrapeMode, String searchQuery, String contentType) onConfirm,
    required VoidCallback onCancel,
  }) {
    return _EnhancedSingleScrapeDialog(
      title: title,
      contextData: contextData,
      onConfirm: onConfirm,
      onCancel: onCancel,
    );
  }

  /// 渲染增强版磁力刮削对话框
  static Widget renderMagnetScrapeDialog({
    required BuildContext context,
    required String title,
    required Map<String, dynamic> contextData,
    required Function(String searchQuery) onConfirm,
    required VoidCallback onCancel,
  }) {
    return _EnhancedMagnetScrapeDialog(
      title: title,
      contextData: contextData,
      onConfirm: onConfirm,
      onCancel: onCancel,
    );
  }

  /// 显示媒体刮削进度对话框
  static void showMediaScrapeProgressDialog({
    required BuildContext context,
    required String sessionId,
    required String locale,
    required Function(Map<String, dynamic>) onComplete,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => EnhancedMediaScrapeProgressDialog(
        sessionId: sessionId,
        locale: locale,
        onComplete: onComplete,
      ),
    );
  }

  /// 渲染多选结果对话框
  static Widget renderMultipleResultsDialog({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> results,
    required String mediaId,  // 添加 mediaId 参数
    String mode = 'replace',  // 添加 mode 参数，默认为 replace
    VoidCallback? onSuccess,  // 添加成功回调
  }) {
    return _EnhancedMultipleResultsDialog(
      title: title,
      results: results,
      mediaId: mediaId,
      mode: mode,
      onSuccess: onSuccess,
    );
  }
}

class _EnhancedBatchScrapeDialog extends StatefulWidget {
  final String title;
  final int itemCount;
  final String itemType;
  final Function(bool concurrent, String scrapeMode, String contentType) onConfirm;
  final VoidCallback onCancel;
  final bool showScrapeModeSelector;  // 新增：是否显示刮削方式选择器

  const _EnhancedBatchScrapeDialog({
    required this.title,
    required this.itemCount,
    required this.itemType,
    required this.onConfirm,
    required this.onCancel,
    this.showScrapeModeSelector = true,  // 默认显示
  });

  @override
  State<_EnhancedBatchScrapeDialog> createState() => _EnhancedBatchScrapeDialogState();
}

class _EnhancedBatchScrapeDialogState extends State<_EnhancedBatchScrapeDialog> with SingleTickerProviderStateMixin {
  bool _concurrent = false;
  String _scrapeMode = 'code'; // 'code', 'title', 'series_date', 'series_title'
  String? _contentType; // 默认为 null，用户必须选择
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isLoading = true; // 加载记忆的选择

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    // 智能推荐：超过5个项目推荐并发
    if (widget.itemCount > 5) {
      _concurrent = true;
    }
    
    // 加载上次选择的 content_type
    _loadLastContentType();
  }

  /// 加载上次选择的 content_type
  Future<void> _loadLastContentType() async {
    final lastContentType = await ScrapePreferences.loadLastContentType();
    if (mounted) {
      setState(() {
        _contentType = lastContentType;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // 计算预估时间（秒）
  int _estimateTime() {
    const int avgTimePerItem = 3; // 平均每个项目3秒
    if (_concurrent) {
      const int concurrentWorkers = 10; // 10个并发线程
      return (widget.itemCount / concurrentWorkers * avgTimePerItem).ceil();
    } else {
      return widget.itemCount * avgTimePerItem;
    }
  }

  // 格式化时间显示
  String _formatTime(int seconds) {
    if (seconds < 60) {
      return '$seconds秒';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '$minutes分${remainingSeconds}秒';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final estimatedTime = _estimateTime();

    // 如果还在加载记忆的选择，显示加载指示器
    if (_isLoading) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和关闭按钮
            Row(
              children: [
                Icon(
                  Icons.cloud_download,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.itemCount} 个${widget.itemType == 'media' ? '媒体' : '演员'} · 预计 ${_formatTime(estimatedTime)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onCancel,
                  tooltip: '取消',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 刮削方式选择（仅媒体类型显示，且 showScrapeModeSelector 为 true）
            if (widget.itemType == 'media' && widget.showScrapeModeSelector) ...[
              Text(
                '刮削方式',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              
              // 刮削方式卡片 - 紧凑版
              _CompactScrapeModeSelector(
                selectedMode: _scrapeMode,
                onModeChanged: (newMode) {
                  setState(() {
                    _scrapeMode = newMode;
                  });
                },
              ),
              
              const SizedBox(height: 16),
            ],

            // 内容类型选择 (仅媒体刮削显示)
            if (widget.itemType == 'media') ...[
              Text(
                '内容类型',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              
              Row(
                children: [
                  Expanded(
                    child: _ContentTypeCard(
                      type: 'Scene',
                      icon: Icons.movie_outlined,
                      isSelected: _contentType == 'Scene',
                      onTap: () {
                        setState(() => _contentType = 'Scene');
                        ScrapePreferences.saveContentType('Scene');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ContentTypeCard(
                      type: 'Movie',
                      icon: Icons.video_library_outlined,
                      isSelected: _contentType == 'Movie',
                      onTap: () {
                        setState(() => _contentType = 'Movie');
                        ScrapePreferences.saveContentType('Movie');
                      },
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
            ],

            // 处理模式选择
            Text(
              '处理模式',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 串行模式
                Expanded(
                  child: _CompactModeCard(
                    icon: Icons.list_rounded,
                    title: '串行',
                    time: _formatTime(widget.itemCount * 3),
                    color: Colors.blue,
                    isSelected: !_concurrent,
                    onTap: () {
                      setState(() {
                        _concurrent = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // 并发模式
                Expanded(
                  child: _CompactModeCard(
                    icon: Icons.flash_on_rounded,
                    title: '并发',
                    time: _formatTime(_estimateTime()),
                    color: Colors.green,
                    isSelected: _concurrent,
                    recommended: widget.itemCount > 5,
                    onTap: () {
                      setState(() {
                        _concurrent = true;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    // 如果是媒体刮削，必须选择 content_type
                    if (widget.itemType == 'media' && _contentType == null) {
                      context.showWarning('请选择内容类型（Scene 或 Movie）');
                      return;
                    }
                    widget.onConfirm(_concurrent, _scrapeMode, _contentType ?? 'Scene');
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('开始'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑型模式选择卡片
class _CompactModeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String time;
  final Color color;
  final bool isSelected;
  final bool recommended;
  final VoidCallback onTap;

  const _CompactModeCard({
    required this.icon,
    required this.title,
    required this.time,
    required this.color,
    required this.isSelected,
    this.recommended = false,
    required this.onTap,
  });

  @override
  State<_CompactModeCard> createState() => _CompactModeCardState();
}

class _CompactModeCardState extends State<_CompactModeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        transform: Matrix4.identity()
          ..scale(_isHovered ? 1.02 : 1.0),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? widget.color.withOpacity(0.12)
                  : colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isSelected
                    ? widget.color
                    : colorScheme.outline.withOpacity(0.3),
                width: widget.isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // 图标
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                // 标题和时间
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: widget.isSelected ? widget.color : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 12,
                            color: widget.isSelected ? widget.color : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.time,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.isSelected ? widget.color : colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 推荐标签
                if (widget.recommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '推荐',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// 增强版单个刮削对话框（详情页）
class _EnhancedSingleScrapeDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic> contextData;
  final Function(String scrapeMode, String searchQuery, String contentType) onConfirm;
  final VoidCallback onCancel;

  const _EnhancedSingleScrapeDialog({
    required this.title,
    required this.contextData,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_EnhancedSingleScrapeDialog> createState() => _EnhancedSingleScrapeDialogState();
}

class _EnhancedSingleScrapeDialogState extends State<_EnhancedSingleScrapeDialog> {
  String _scrapeMode = 'code';
  String? _contentType; // 默认为 null，用户必须选择
  late TextEditingController _searchController;
  bool _isLoading = true; // 加载记忆的选择

  @override
  void initState() {
    super.initState();
    
    // 加载上次选择的 content_type
    _loadLastContentType();
    
    // 默认使用 code 模式
    _scrapeMode = 'code';
    
    // 根据当前模式生成初始搜索关键词
    final code = widget.contextData['code'] as String?;
    String initialQuery = code ?? '';
    
    _searchController = TextEditingController(text: initialQuery);
  }

  /// 检查是否为日本 AV
  bool _isJapaneseAV() {
    final code = widget.contextData['code'] as String?;
    return code != null && 
           code.isNotEmpty && 
           RegExp(r'^[A-Z]{2,6}-\d+$', caseSensitive: false).hasMatch(code);
  }

  /// 加载上次选择的 content_type
  Future<void> _loadLastContentType() async {
    final lastContentType = await ScrapePreferences.loadLastContentType();
    if (mounted) {
      setState(() {
        _contentType = lastContentType;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 生成系列+日期格式
  String? _generateSeriesDateQuery() {
    return generateSeriesDateQuery(widget.contextData);
  }

  /// 生成系列+标题格式
  String? _generateSeriesTitleQuery() {
    return generateSeriesTitleQuery(widget.contextData);
  }

  /// 当刮削模式改变时，更新搜索关键词
  void _onScrapeModeChanged(String newMode) {
    String newQuery = '';
    
    switch (newMode) {
      case 'code':
        // code 模式：直接使用 code 字段
        newQuery = widget.contextData['code'] as String? ?? '';
        break;
      case 'title':
        // title 模式：使用 title 字段
        newQuery = widget.contextData['title'] as String? ?? '';
        break;
      case 'studio_code':
        // studio_code 模式：生成 片商-番号 格式（用于 JAV）
        final studio = widget.contextData['studio'] as String?;
        final code = widget.contextData['code'] as String?;
        
        // 调试日志
        print('🔍 studio_code 模式:');
        print('   studio from contextData: $studio');
        print('   code from contextData: $code');
        print('   contextData keys: ${widget.contextData.keys.toList()}');
        
        // 如果有 studio 和 code，自动生成
        if (studio != null && studio.isNotEmpty && code != null && code.isNotEmpty) {
          newQuery = '$studio-$code';
          print('   ✅ 生成查询: $newQuery');
        } 
        // 如果只有 code，让用户手动输入片商名
        else if (code != null && code.isNotEmpty) {
          newQuery = code;  // 先显示番号，让用户在前面加片商名
          print('   ⚠️ 只有 code，显示: $newQuery');
        } 
        // 如果都没有，显示空
        else {
          newQuery = '';
          print('   ❌ 都没有，显示空');
        }
        break;
      case 'series_date':
        // series_date 模式：生成 系列.YY.MM.DD 格式
        final seriesDate = _generateSeriesDateQuery();
        if (seriesDate != null) {
          newQuery = seriesDate;
        } else {
          // 如果无法生成，提示并切回title模式
          context.showWarning('缺少系列或发布日期信息');
          newMode = 'title';
          newQuery = widget.contextData['title'] as String? ?? '';
        }
        break;
      case 'series_title':
        // series_title 模式：生成 系列-标题 格式
        final seriesTitle = _generateSeriesTitleQuery();
        if (seriesTitle != null) {
          newQuery = seriesTitle;
        } else {
          // 如果无法生成，提示并切回title模式
          context.showWarning('缺少系列或标题信息');
          newMode = 'title';
          newQuery = widget.contextData['title'] as String? ?? '';
        }
        break;
    }
    
    setState(() {
      _scrapeMode = newMode;
      _searchController.text = newQuery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 如果还在加载记忆的选择，显示加载指示器
    if (_isLoading) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和关闭按钮
            Row(
              children: [
                Icon(
                  Icons.cloud_download,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onCancel,
                  tooltip: '取消',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 刮削方式选择 - 紧凑版
            Text(
              '刮削方式',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            
            // 刮削方式卡片 - 紧凑版
            _CompactScrapeModeSelector(
              selectedMode: _scrapeMode,
              onModeChanged: _onScrapeModeChanged,
            ),
            
            const SizedBox(height: 16),

            // 内容类型选择（ThePornDB）
            Text(
              '内容类型',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _ContentTypeCard(
                    type: 'Scene',
                    icon: Icons.movie_outlined,
                    isSelected: _contentType == 'Scene',
                    onTap: () {
                      setState(() => _contentType = 'Scene');
                      ScrapePreferences.saveContentType('Scene');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ContentTypeCard(
                    type: 'Movie',
                    icon: Icons.video_library_outlined,
                    isSelected: _contentType == 'Movie',
                    onTap: () {
                      setState(() => _contentType = 'Movie');
                      ScrapePreferences.saveContentType('Movie');
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),

            // 搜索关键词输入
            Text(
              '搜索关键词',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '输入识别号或标题',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                isDense: true,
              ),
            ),
            
            const SizedBox(height: 16),

            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final query = _searchController.text.trim();
                    if (query.isEmpty) {
                      context.showWarning('请输入搜索关键词');
                      return;
                    }
                    if (_contentType == null) {
                      context.showWarning('请选择内容类型（Scene 或 Movie）');
                      return;
                    }
                    widget.onConfirm(_scrapeMode, query, _contentType!);
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('开始'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 通用模式选择器组件
class _ModeOptionCard extends StatelessWidget {
  final String mode;
  final String selectedMode;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Function(String) onModeChanged;

  const _ModeOptionCard({
    required this.mode,
    required this.selectedMode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = selectedMode == mode;

    return InkWell(
      onTap: () => onModeChanged(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.1)
              : colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color
                : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: color,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

/// 刮削方式选择器
class _ScrapeModeSelector extends StatelessWidget {
  final String selectedMode;
  final Function(String) onModeChanged;

  const _ScrapeModeSelector({
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModeOptionCard(
          mode: 'code',
          selectedMode: selectedMode,
          icon: Icons.tag,
          title: '按识别号',
          subtitle: '识别号精确匹配',
          color: Colors.blue,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 8),
        _ModeOptionCard(
          mode: 'title',
          selectedMode: selectedMode,
          icon: Icons.title,
          title: '按标题',
          subtitle: '标题模糊搜索',
          color: Colors.green,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 8),
        _ModeOptionCard(
          mode: 'series_title',
          selectedMode: selectedMode,
          icon: Icons.video_library,
          title: '按系列+标题',
          subtitle: '系列名称+标题组合搜索',
          color: Colors.purple,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 8),
        _ModeOptionCard(
          mode: 'series_date',
          selectedMode: selectedMode,
          icon: Icons.calendar_today,
          title: '按系列+日期',
          subtitle: '系列名称+发布日期',
          color: Colors.orange,
          onModeChanged: onModeChanged,
        ),
      ],
    );
  }
}

/// 紧凑版刮削方式选择器
class _CompactScrapeModeSelector extends StatelessWidget {
  final String selectedMode;
  final Function(String) onModeChanged;

  const _CompactScrapeModeSelector({
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CompactModeOptionCard(
          mode: 'code',
          selectedMode: selectedMode,
          icon: Icons.tag,
          title: '按识别号',
          subtitle: '识别号精确匹配',
          color: Colors.blue,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 6),
        _CompactModeOptionCard(
          mode: 'studio_code',
          selectedMode: selectedMode,
          icon: Icons.business,
          title: '按片商+识别号',
          subtitle: '片商名称+识别号',
          color: Colors.teal,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 6),
        _CompactModeOptionCard(
          mode: 'title',
          selectedMode: selectedMode,
          icon: Icons.title,
          title: '按标题',
          subtitle: '标题模糊搜索',
          color: Colors.green,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 6),
        _CompactModeOptionCard(
          mode: 'series_title',
          selectedMode: selectedMode,
          icon: Icons.video_library,
          title: '按系列+标题',
          subtitle: '系列名称+标题组合搜索',
          color: Colors.purple,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 6),
        _CompactModeOptionCard(
          mode: 'series_date',
          selectedMode: selectedMode,
          icon: Icons.calendar_today,
          title: '按系列+日期',
          subtitle: '系列名称+发布日期',
          color: Colors.orange,
          onModeChanged: onModeChanged,
        ),
      ],
    );
  }
}

/// 紧凑版模式选项卡片
class _CompactModeOptionCard extends StatelessWidget {
  final String mode;
  final String selectedMode;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Function(String) onModeChanged;

  const _CompactModeOptionCard({
    required this.mode,
    required this.selectedMode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = selectedMode == mode;

    return InkWell(
      onTap: () => onModeChanged(mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.1)
              : colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? color
                : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: color,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}


/// 增强版磁力刮削对话框
class _EnhancedMagnetScrapeDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic> contextData;
  final Function(String searchQuery) onConfirm;
  final VoidCallback onCancel;

  const _EnhancedMagnetScrapeDialog({
    required this.title,
    required this.contextData,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_EnhancedMagnetScrapeDialog> createState() => _EnhancedMagnetScrapeDialogState();
}

class _EnhancedMagnetScrapeDialogState extends State<_EnhancedMagnetScrapeDialog> {
  late TextEditingController _searchController;
  late String _searchMode; // 'code', 'title', 'series_date'

  @override
  void initState() {
    super.initState();
    
    // 智能初始化：优先使用识别号，其次使用标题
    final code = widget.contextData['code'] as String?;
    final title = widget.contextData['title'] as String?;
    
    String initialQuery = '';
    String initialMode = 'code';
    
    if (code != null && code.isNotEmpty) {
      initialMode = 'code';
      initialQuery = code;
    } else if (title != null && title.isNotEmpty) {
      initialMode = 'title';
      initialQuery = title;
    }
    
    _searchMode = initialMode;
    _searchController = TextEditingController(text: initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 生成系列+日期格式
  String? _generateSeriesDateQuery() {
    return generateSeriesDateQuery(widget.contextData);
  }

  /// 当搜索模式改变时，更新搜索关键词
  void _onSearchModeChanged(String newMode) {
    String newQuery = '';
    
    switch (newMode) {
      case 'code':
        newQuery = widget.contextData['code'] as String? ?? '';
        break;
      case 'title':
        newQuery = widget.contextData['title'] as String? ?? '';
        break;
      case 'series_date':
        final seriesDate = _generateSeriesDateQuery();
        if (seriesDate != null) {
          newQuery = seriesDate;
        } else {
          // 如果无法生成，提示并切回title模式
          context.showWarning('缺少系列或发布日期信息');
          newMode = 'title';
          newQuery = widget.contextData['title'] as String? ?? '';
        }
        break;
    }
    
    setState(() {
      _searchMode = newMode;
      _searchController.text = newQuery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和关闭按钮
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
                    widget.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onCancel,
                  tooltip: '取消',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 信息提示卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '将从多个磁力网站搜索资源',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 搜索模式选择
            Text(
              '选择搜索方式',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            _MagnetSearchModeSelector(
              selectedMode: _searchMode,
              onModeChanged: _onSearchModeChanged,
            ),
            
            const SizedBox(height: 24),

            // 搜索关键词输入
            Text(
              '搜索关键词',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '输入识别号或标题',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
              ),
              onSubmitted: (_) {
                final query = _searchController.text.trim();
                if (query.isNotEmpty) {
                  widget.onConfirm(query);
                }
              },
            ),
            
            const SizedBox(height: 24),

            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () {
                    final query = _searchController.text.trim();
                    if (query.isEmpty) {
                      context.showWarning('请输入搜索关键词');
                      return;
                    }
                    widget.onConfirm(query);
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// 磁力搜索模式选择器
class _MagnetSearchModeSelector extends StatelessWidget {
  final String selectedMode;
  final Function(String) onModeChanged;

  const _MagnetSearchModeSelector({
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModeOptionCard(
          mode: 'code',
          selectedMode: selectedMode,
          icon: Icons.tag,
          title: '按识别号搜索',
          subtitle: '使用识别号精确匹配',
          color: Colors.blue,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 8),
        _ModeOptionCard(
          mode: 'title',
          selectedMode: selectedMode,
          icon: Icons.title,
          title: '按标题搜索',
          subtitle: '使用标题模糊搜索',
          color: Colors.green,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 8),
        _ModeOptionCard(
          mode: 'series_date',
          selectedMode: selectedMode,
          icon: Icons.calendar_today,
          title: '按系列+日期搜索',
          subtitle: '使用系列名称+发布日期',
          color: Colors.orange,
          onModeChanged: onModeChanged,
        ),
      ],
    );
  }
}



/// 增强版磁力搜索进度对话框
class EnhancedMagnetSearchProgressDialog extends StatefulWidget {
  final String sessionId;
  final String locale;
  final Function(Map<String, dynamic>) onComplete;

  const EnhancedMagnetSearchProgressDialog({
    super.key,
    required this.sessionId,
    required this.locale,
    required this.onComplete,
  });

  @override
  State<EnhancedMagnetSearchProgressDialog> createState() =>
      _EnhancedMagnetSearchProgressDialogState();
}

class _EnhancedMagnetSearchProgressDialogState
    extends State<EnhancedMagnetSearchProgressDialog>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  ProviderContainer? _container;
  
  String _currentSite = '';
  String _currentStatus = 'searching';
  int _progress = 0;
  int _total = 3;
  bool _isCompleted = false;
  int _resultCount = 0;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // 友好的等待提示语
  final List<String> _waitingTips = [
    '正在搜索磁力资源...',
    '请稍候，正在努力工作...',
    '搜索中，这可能需要一点时间...',
    '正在努力寻找资源...',
  ];
  int _currentTipIndex = 0;
  Timer? _tipTimer;

  @override
  void initState() {
    super.initState();
    
    // 脉冲动画
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // 定时切换提示语
    _tipTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !_isCompleted) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % _waitingTips.length;
        });
      }
    });
    
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tipTimer?.cancel();
    _pulseController.dispose();
    _container?.dispose();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted) {
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

        final response = await dio.get('/scrape/magnets/progress/${widget.sessionId}');
        final responseData = response.data as Map<String, dynamic>;

        if (!mounted) return;

        _parseProgressData(responseData);

        if (_isCompleted) {
          _timer?.cancel();
          final results = _buildCompletionResult(responseData);
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            widget.onComplete(results);
          }
        }
      } catch (e) {
        print('❌ Error polling progress: $e');
        // 不要因为单次错误就关闭对话框，继续轮询
      }
    });
  }

  void _parseProgressData(Map<String, dynamic> responseData) {
    final data = responseData['data'] as Map<String, dynamic>? ?? {};
    final sitesStatus = data['sites_status'] as List<dynamic>? ?? [];
    
    // 找到当前正在搜索的网站
    String currentSite = data['current_site'] as String? ?? '';
    String currentStatus = 'searching';
    int resultCount = 0;
    
    // 计算已完成的网站数
    int completedCount = 0;
    for (final site in sitesStatus) {
      final siteMap = site as Map<String, dynamic>;
      final status = siteMap['status'] as String? ?? 'pending';
      if (status == 'completed' || status == 'failed' || status == 'skipped') {
        completedCount++;
      }
      if (siteMap['site_name'] == currentSite) {
        currentStatus = status;
        resultCount = siteMap['result_count'] as int? ?? 0;
      }
    }
    
    // 解析 completed 字段
    bool isCompleted = false;
    final completedValue = data['completed'];
    if (completedValue is bool) {
      isCompleted = completedValue;
    } else if (completedValue is int) {
      isCompleted = completedValue != 0;
    }
    
    // 计算总结果数
    int totalResults = 0;
    final results = data['results'] as List<dynamic>?;
    if (results != null) {
      totalResults = results.length;
    }

    setState(() {
      _currentSite = currentSite;
      _currentStatus = currentStatus;
      _progress = completedCount;
      _total = sitesStatus.length > 0 ? sitesStatus.length : 3;
      _isCompleted = isCompleted;
      _resultCount = totalResults;
    });
  }

  Map<String, dynamic> _buildCompletionResult(Map<String, dynamic> responseData) {
    final data = responseData['data'] as Map<String, dynamic>? ?? {};
    return {
      'success': true,
      'data': data['results'] ?? [],
    };
  }

  String _getSiteDisplayName(String siteName) {
    switch (siteName.toLowerCase()) {
      case 'kitetuan':
        return 'kitetuan (快速)';
      case 'knaben':
        return 'knaben (快速)';
      case 'skrbt':
        return 'skrbt (慢速)';
      default:
        return siteName;
    }
  }

  IconData _getSiteIcon(String siteName) {
    switch (siteName.toLowerCase()) {
      case 'kitetuan':
        return Icons.pets;
      case 'knaben':
        return Icons.hub;
      case 'skrbt':
        return Icons.search;
      default:
        return Icons.language;
    }
  }

  Color _getStatusColor(String status, ColorScheme colorScheme) {
    switch (status) {
      case 'searching':
        return colorScheme.primary;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'skipped':
        return Colors.grey;
      default:
        return colorScheme.onSurfaceVariant;
    }
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
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部动画图标
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.search,
                      size: 36,
                      color: colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            // 友好提示语（带动画切换）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _waitingTips[_currentTipIndex],
                key: ValueKey(_currentTipIndex),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progressPercent,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // 进度文字
            Text(
              '$_progress / $_total 个网站',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 当前搜索网站（单行显示）
            if (_currentSite.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getStatusColor(_currentStatus, colorScheme).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // 状态指示器
                    if (_currentStatus == 'searching')
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary,
                          ),
                        ),
                      )
                    else
                      Icon(
                        _currentStatus == 'completed'
                            ? Icons.check_circle
                            : _currentStatus == 'failed'
                                ? Icons.error
                                : Icons.remove_circle,
                        size: 20,
                        color: _getStatusColor(_currentStatus, colorScheme),
                      ),
                    
                    const SizedBox(width: 12),
                    
                    // 网站图标
                    Icon(
                      _getSiteIcon(_currentSite),
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // 网站名称
                    Expanded(
                      child: Text(
                        _getSiteDisplayName(_currentSite),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            
            // 已找到结果数（如果有）
            if (_resultCount > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '已找到 $_resultCount 个资源',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
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
}


/// 增强版媒体刮削进度对话框
class EnhancedMediaScrapeProgressDialog extends StatefulWidget {
  final String sessionId;
  final String locale;
  final Function(Map<String, dynamic>) onComplete;

  const EnhancedMediaScrapeProgressDialog({
    super.key,
    required this.sessionId,
    required this.locale,
    required this.onComplete,
  });

  @override
  State<EnhancedMediaScrapeProgressDialog> createState() =>
      _EnhancedMediaScrapeProgressDialogState();
}

class _EnhancedMediaScrapeProgressDialogState
    extends State<EnhancedMediaScrapeProgressDialog>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  ProviderContainer? _container;
  
  int _current = 0;
  int _total = 0;
  String _currentItem = '';
  String _itemStatus = 'pending';
  int _successCount = 0;
  int _failedCount = 0;
  bool _isCompleted = false;
  String _message = '正在初始化刮削...';
  bool _concurrent = false;  // 是否并发模式
  List<String> _processingItems = [];  // 正在处理的项目列表（并发模式）
  int _processingItemIndex = 0;  // 当前显示的项目索引（轮换显示）
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // 友好的等待提示语
  final List<String> _waitingTips = [
    '正在刮削媒体信息...',
    '请稍候，正在努力工作...',
    '刮削中，这可能需要一点时间...',
    '正在获取元数据...',
  ];
  int _currentTipIndex = 0;
  Timer? _tipTimer;
  Timer? _itemRotateTimer;  // 并发模式下轮换显示项目的定时器

  @override
  void initState() {
    super.initState();
    
    // 脉冲动画
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // 定时切换提示语
    _tipTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !_isCompleted) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % _waitingTips.length;
        });
      }
    });
    
    // 并发模式下轮换显示项目（每1.5秒切换一次）
    _itemRotateTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted && !_isCompleted && _concurrent && _processingItems.isNotEmpty) {
        setState(() {
          _processingItemIndex = (_processingItemIndex + 1) % _processingItems.length;
        });
      }
    });
    
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tipTimer?.cancel();
    _itemRotateTimer?.cancel();
    _pulseController.dispose();
    _container?.dispose();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted) {
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

        final response = await dio.get('/scrape/progress/${widget.sessionId}');
        final responseData = response.data as Map<String, dynamic>;

        if (!mounted) return;

        _parseProgressData(responseData);

        if (_isCompleted) {
          _timer?.cancel();
          final results = _buildCompletionResult(responseData);
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            widget.onComplete(results);
          }
        }
      } catch (e) {
        print('❌ Error polling media scrape progress: $e');
        // 不要因为单次错误就关闭对话框，继续轮询
      }
    });
  }

  void _parseProgressData(Map<String, dynamic> responseData) {
    final data = responseData['data'] as Map<String, dynamic>? ?? {};
    
    final current = data['current'] as int? ?? 0;
    final total = data['total'] as int? ?? 0;
    final currentItem = data['current_item'] as String? ?? '';
    final itemStatus = data['item_status'] as String? ?? 'pending';
    final successCount = data['success_count'] as int? ?? 0;
    final failedCount = data['failed_count'] as int? ?? 0;
    final message = data['message'] as String? ?? '';
    final concurrent = data['concurrent'] as bool? ?? false;
    
    // 解析正在处理的项目列表（并发模式）
    List<String> processingItems = [];
    final processingItemsData = data['processing_items'];
    if (processingItemsData is List) {
      processingItems = processingItemsData.map((e) => e.toString()).toList();
    }
    
    // 解析 completed 字段
    bool isCompleted = false;
    final completedValue = data['completed'];
    if (completedValue is bool) {
      isCompleted = completedValue;
    } else if (completedValue is int) {
      isCompleted = completedValue != 0;
    }

    setState(() {
      _current = current;
      _total = total;
      _currentItem = currentItem;
      _itemStatus = itemStatus;
      _successCount = successCount;
      _failedCount = failedCount;
      _message = message;
      _isCompleted = isCompleted;
      _concurrent = concurrent;
      _processingItems = processingItems;
      // 确保索引在有效范围内
      if (_processingItems.isNotEmpty && _processingItemIndex >= _processingItems.length) {
        _processingItemIndex = 0;
      }
    });
  }

  Map<String, dynamic> _buildCompletionResult(Map<String, dynamic> responseData) {
    final data = responseData['data'] as Map<String, dynamic>? ?? {};
    return {
      'success': true,
      'success_count': data['success_count'] ?? 0,
      'failed_count': data['failed_count'] ?? 0,
      'message': data['message'] ?? '',
    };
  }

  Color _getStatusColor(String status, ColorScheme colorScheme) {
    switch (status) {
      case 'scraping':
        return colorScheme.primary;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'skipped':
        return Colors.grey;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressPercent = _total > 0 ? _current / _total : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部动画图标
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.movie_filter,
                      size: 36,
                      color: colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            // 友好提示语（带动画切换）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _waitingTips[_currentTipIndex],
                key: ValueKey(_currentTipIndex),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progressPercent,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // 进度文字
            Text(
              _concurrent 
                  ? '$_current / $_total 个项目 (并发)'
                  : '$_current / $_total 个项目',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 并发模式：显示正在处理的项目列表（轮换显示）
            if (_concurrent && _processingItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 并发状态标题
                    Row(
                      children: [
                        Icon(
                          Icons.flash_on,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '正在并发处理 ${_processingItems.length} 个项目',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 轮换显示当前项目（带动画）
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Row(
                        key: ValueKey(_processingItemIndex),
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.movie,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _processingItems.isNotEmpty && _processingItemIndex < _processingItems.length
                                  ? _processingItems[_processingItemIndex]
                                  : '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 显示项目索引
                          Text(
                            '${_processingItemIndex + 1}/${_processingItems.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            // 串行模式：显示单个当前项目
            else if (!_concurrent && _currentItem.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getStatusColor(_itemStatus, colorScheme).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // 状态指示器
                    if (_itemStatus == 'scraping')
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary,
                          ),
                        ),
                      )
                    else
                      Icon(
                        _itemStatus == 'completed'
                            ? Icons.check_circle
                            : _itemStatus == 'failed'
                                ? Icons.error
                                : Icons.remove_circle,
                        size: 20,
                        color: _getStatusColor(_itemStatus, colorScheme),
                      ),
                    
                    const SizedBox(width: 12),
                    
                    // 项目图标
                    Icon(
                      Icons.movie,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // 项目名称
                    Expanded(
                      child: Text(
                        _currentItem,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            
            // 成功/失败统计
            if (_successCount > 0 || _failedCount > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_successCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '成功 $_successCount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_successCount > 0 && _failedCount > 0)
                    const SizedBox(width: 8),
                  if (_failedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '失败 $_failedCount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// 内容类型选择卡片
class _ContentTypeCard extends StatelessWidget {
  final String type;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ContentTypeCard({
    required this.type,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(0.1)
              : colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              type,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 多选结果对话框 - 用于显示多个刮削结果供用户选择
class _EnhancedMultipleResultsDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> results;
  final String mediaId;
  final String mode;  // 添加 mode 参数
  final VoidCallback? onSuccess;

  const _EnhancedMultipleResultsDialog({
    required this.title,
    required this.results,
    required this.mediaId,
    this.mode = 'replace',  // 默认为 replace
    this.onSuccess,
  });

  @override
  State<_EnhancedMultipleResultsDialog> createState() =>
      _EnhancedMultipleResultsDialogState();
}

class _EnhancedMultipleResultsDialogState
    extends State<_EnhancedMultipleResultsDialog> {
  // 状态变量
  Set<int> _selectedIndices = {};
  List<Map<String, dynamic>> _filteredResults = [];
  String _searchQuery = '';
  String _sortBy = 'release_date';
  bool _sortAscending = false;
  Timer? _searchDebounce;
  bool _isImporting = false;  // 添加导入状态

  @override
  void initState() {
    super.initState();
    _filteredResults = List.from(widget.results);
    _sortResults();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// 批量导入选中的结果
  Future<void> _importSelectedResults() async {
    if (_selectedIndices.isEmpty) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final selectedResults = _getSelectedResults();
      final locale = Localizations.localeOf(context).languageCode;
      
      // 显示进度对话框
      if (mounted) {
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
                      locale == 'zh' ? '正在导入...' : 'Importing...',
                      style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      locale == 'zh' 
                          ? '正在导入 ${selectedResults.length} 个结果，请稍候...' 
                          : 'Importing ${selectedResults.length} results, please wait...',
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

      // 调用 API
      final container = ProviderScope.containerOf(context, listen: false);
      final apiService = container.read(apiServiceProvider);
      
      final response = await apiService.batchImportScrapeResults(
        mediaId: widget.mediaId,
        selectedResults: selectedResults,
        mode: widget.mode,  // 传递 mode 参数
      );

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // 关闭多选对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 显示结果
      if (mounted) {
        final successMsg = locale == 'zh'
            ? '成功导入 ${response.importedCount} 个，失败 ${response.failedCount} 个'
            : 'Imported ${response.importedCount}, failed ${response.failedCount}';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: response.failedCount == 0
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        // 调用成功回调
        widget.onSuccess?.call();
      }
    } catch (e) {
      // 关闭进度对话框
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }

      // 显示错误
      if (mounted) {
        final locale = Localizations.localeOf(context).languageCode;
        final errorMsg = locale == 'zh'
            ? '导入失败: $e'
            : 'Import failed: $e';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  /// 切换选中状态
  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// 全选
  void _selectAll() {
    setState(() {
      _selectedIndices = Set.from(
        List.generate(_filteredResults.length, (i) => i),
      );
    });
  }

  /// 取消全选
  void _clearSelection() {
    setState(() {
      _selectedIndices.clear();
    });
  }

  /// 搜索过滤（带防抖）
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query;
        _filteredResults = widget.results.where((result) {
          final title = result['title'] as String? ?? '';
          return title.toLowerCase().contains(query.toLowerCase());
        }).toList();
        _sortResults();
        // 清空选中状态
        _selectedIndices.clear();
      });
    });
  }

  /// 排序
  void _sortResults() {
    _filteredResults.sort((a, b) {
      int comparison = 0;
      if (_sortBy == 'release_date') {
        final dateA = a['release_date'] as String? ?? '';
        final dateB = b['release_date'] as String? ?? '';
        comparison = dateA.compareTo(dateB);
      } else if (_sortBy == 'title') {
        final titleA = a['title'] as String? ?? '';
        final titleB = b['title'] as String? ?? '';
        comparison = titleA.compareTo(titleB);
      }
      return _sortAscending ? comparison : -comparison;
    });
  }

  /// 切换排序方式
  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = false;
      }
      _sortResults();
    });
  }

  /// 获取选中的结果
  List<Map<String, dynamic>> _getSelectedResults() {
    return _selectedIndices.map((i) => _filteredResults[i]).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedCount = _selectedIndices.length;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 900,
          maxHeight: 700,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(
                  Icons.grid_view,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '找到 ${_filteredResults.length} 个结果',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '取消',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 搜索和工具栏
            Row(
              children: [
                // 搜索框
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索标题...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      isDense: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 8),

                // 排序按钮
                PopupMenuButton<String>(
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 4),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 14,
                      ),
                    ],
                  ),
                  tooltip: '排序',
                  onSelected: _toggleSort,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'release_date',
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: _sortBy == 'release_date'
                                ? colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '按日期',
                            style: TextStyle(
                              color: _sortBy == 'release_date'
                                  ? colorScheme.primary
                                  : null,
                              fontWeight: _sortBy == 'release_date'
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'title',
                      child: Row(
                        children: [
                          Icon(
                            Icons.title,
                            size: 16,
                            color: _sortBy == 'title'
                                ? colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '按标题',
                            style: TextStyle(
                              color: _sortBy == 'title'
                                  ? colorScheme.primary
                                  : null,
                              fontWeight: _sortBy == 'title'
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 全选/取消全选按钮
                TextButton.icon(
                  onPressed: selectedCount == _filteredResults.length
                      ? _clearSelection
                      : _selectAll,
                  icon: Icon(
                    selectedCount == _filteredResults.length
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  label: Text(
                    selectedCount == _filteredResults.length ? '取消全选' : '全选',
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 结果网格
            Expanded(
              child: _filteredResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '没有找到匹配的结果',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.7,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _filteredResults.length,
                      itemBuilder: (context, index) {
                        final result = _filteredResults[index];
                        final isSelected = _selectedIndices.contains(index);
                        return _ResultCard(
                          result: result,
                          isSelected: isSelected,
                          onTap: () => _toggleSelection(index),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),

            // 底部操作栏
            Row(
              children: [
                Text(
                  '已选中 $selectedCount 个',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (selectedCount > 0 && !_isImporting)
                      ? _importSelectedResults
                      : null,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.download, size: 18),
                  label: Text(_isImporting ? '导入中...' : '导入选中项 ($selectedCount)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果卡片组件
class _ResultCard extends StatefulWidget {
  final Map<String, dynamic> result;
  final bool isSelected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
        child: Card(
          elevation: widget.isSelected ? 4 : (_isHovered ? 2 : 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: widget.isSelected
                  ? colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面和复选框
                Expanded(
                  child: Stack(
                    children: [
                      // 封面图
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: widget.result['poster_url'] != null &&
                                (widget.result['poster_url'] as String).isNotEmpty
                            ? Image.network(
                                widget.result['poster_url'],
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: colorScheme.surfaceVariant,
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        size: 48,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: colorScheme.surfaceVariant,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: colorScheme.surfaceVariant,
                                child: Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                      ),
                      // 复选框（右上角）
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Checkbox(
                            value: widget.isSelected,
                            onChanged: (_) => widget.onTap(),
                            shape: const CircleBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 标题和信息
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        widget.result['title'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 发布日期
                      if (widget.result['release_date'] != null)
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.result['release_date'],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      // 时长（可选）
                      if (widget.result['runtime'] != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.result['runtime']} 分钟',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
