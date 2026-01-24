import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../../../shared/widgets/media_card.dart';
import '../../providers/media_providers.dart';
import '../../providers/plugin_providers.dart';

class FilterScreen extends ConsumerStatefulWidget {
  const FilterScreen({super.key});

  @override
  ConsumerState<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends ConsumerState<FilterScreen> {
  bool _isSelectionMode = false;
  bool _isFilterPanelExpanded = false;
  final Set<String> _selectedIds = {};
  final _scrollController = ScrollController();
  int _currentPage = 1;
  Timer? _debounceTimer;  // 防抖定时器
  bool _isLoadingMore = false;  // 防止重复加载

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();  // 清理防抖定时器
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 取消之前的定时器
    _debounceTimer?.cancel();
    
    // 设置新的定时器（300ms 后执行）
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore) {
          _loadMore();
        }
      }
    });
  }

  void _loadMore() {
    if (_isLoadingMore) return;
    
    setState(() => _isLoadingMore = true);
    
    _currentPage++;
    ref.read(mediaListProvider.notifier).loadMore(page: _currentPage).then((_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }).catchError((error) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<MediaItem> items) {
    setState(() {
      _selectedIds.addAll(items.map((e) => e.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个媒体吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(mediaListProvider.notifier).batchDeleteMedia(_selectedIds.toList());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功删除 ${_selectedIds.length} 个媒体')),
        );
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showBatchEditDialog() async {
    if (_selectedIds.isEmpty) return;

    final result = await showDialog<BatchEditUpdates>(
      context: context,
      builder: (context) => _BatchEditDialog(selectedCount: _selectedIds.length),
    );

    if (result == null) return;

    try {
      await ref.read(mediaListProvider.notifier).batchEditMedia(_selectedIds.toList());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功编辑 ${_selectedIds.length} 个媒体')),
        );
        _toggleSelectionMode();
        // 刷新筛选选项
        ref.invalidate(filterOptionsNotifierProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('编辑失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(mediaFiltersProvider);
    final filterOptionsAsync = ref.watch(filterOptionsNotifierProvider);
    final mediaList = ref.watch(mediaListProvider);
    final currentRoute = GoRouterState.of(context).uri.toString();
    final isOnFilterPage = currentRoute == '/filter';

    return PopScope(
      canPop: !isOnFilterPage, // 只在筛选页时禁止直接返回
      onPopInvoked: (didPop) {
        // 只在筛选页时拦截返回，其他情况允许正常返回
        if (!isOnFilterPage) return;
        // 左滑无反应，用户应该使用底部导航栏切换页面
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar(mediaList) : _buildNormalAppBar(filters),
        body: filterOptionsAsync.when(
          data: (options) => _buildContent(context, options, filters, mediaList),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
        bottomNavigationBar: _isSelectionMode ? _buildSelectionBottomBar() : _buildNavigationBar(),
      ),
    );
  }

  AppBar _buildNormalAppBar(MediaFiltersState filters) {
    return AppBar(
      automaticallyImplyLeading: false, // 移除返回按钮
      title: GestureDetector(
        onTap: () {
          setState(() {
            _isFilterPanelExpanded = !_isFilterPanelExpanded;
          });
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFilterPanelExpanded ? Icons.expand_less : Icons.tune,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(_isFilterPanelExpanded ? '收起筛选' : '展开筛选'),
          ],
        ),
      ),
      centerTitle: true,
      actions: [
        if (filters.hasFilters)
          TextButton(
            onPressed: () {
              ref.read(mediaFiltersProvider.notifier).reset();
            },
            child: const Text('清除'),
          ),
      ],
    );
  }

  AppBar _buildSelectionAppBar(AsyncValue<List<MediaItem>> mediaList) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _toggleSelectionMode,
      ),
      title: Text('已选择 ${_selectedIds.length} 项'),
      actions: [
        TextButton(
          onPressed: () {
            final items = mediaList.value ?? [];
            _selectAll(items);
          },
          child: const Text('全选'),
        ),
        if (_selectedIds.isNotEmpty) ...[
          TextButton(
            onPressed: _clearSelection,
            child: const Text('取消全选'),
          ),
          // 插件UI注入点 - media_list_selection_actions（根据后端已安装插件过滤）
          ...PluginUIRegistry()
              .getButtonsFiltered('media_list_selection_actions', ref.watch(installedPluginIdsProvider))
              .map((button) => PluginUIRenderer.renderButton(
                    button,
                    context,
                    contextData: {
                      'selected_media_ids': _selectedIds.toList(),
                      'exit_selection_mode': () {
                        // 退出多选模式的回调
                        setState(() {
                          _isSelectionMode = false;
                          _selectedIds.clear();
                        });
                      },
                    },
                  )),
        ],
      ],
    );
  }

  Widget _buildSelectionBottomBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _showBatchEditDialog,
            icon: const Icon(Icons.edit),
            label: const Text('编辑'),
          ),
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _batchDelete,
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  NavigationBar _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: 1, // 筛选页面
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/');
            break;
          case 1:
            // 已在筛选页面
            break;
          case 2:
            context.go('/collection');
            break;
          case 3:
            context.go('/actors');
            break;
          case 4:
            context.go('/settings');
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
    );
  }

  Widget _buildContent(
    BuildContext context,
    FilterOptions options,
    MediaFiltersState filters,
    AsyncValue<List<MediaItem>> mediaList,
  ) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 筛选面板（可折叠）
        SliverToBoxAdapter(
          child: AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                // 年份
                _buildExpansionTile(
                  title: '年份',
                  selectedValue: filters.year?.toString(),
                  children: options.years,
                  selectedItem: filters.year,
                  onSelected: (year) {
                    ref.read(mediaFiltersProvider.notifier).updateYear(
                      filters.year == year ? null : year,
                    );
                  },
                  itemBuilder: (year) => year.toString(),
                ),
                
                const Divider(height: 1),
                
                // 媒体类型
                _buildExpansionTile(
                  title: '媒体',
                  selectedValue: filters.mediaType != null 
                      ? _getMediaTypeLabel(filters.mediaType!) 
                      : null,
                  children: options.mediaTypes,
                  selectedItem: filters.mediaType,
                  onSelected: (type) {
                    ref.read(mediaFiltersProvider.notifier).updateMediaType(
                      filters.mediaType == type ? null : type,
                    );
                  },
                  itemBuilder: (type) => _getMediaTypeLabel(type),
                ),
                
                const Divider(height: 1),
                
                // 制作商
                if (options.studios.isNotEmpty) ...[
                  _buildExpansionTile(
                    title: '制作商',
                    selectedValue: filters.studio,
                    children: options.studios,
                    selectedItem: filters.studio,
                    onSelected: (studio) {
                      ref.read(mediaFiltersProvider.notifier).updateStudio(
                        filters.studio == studio ? null : studio,
                      );
                    },
                    itemBuilder: (studio) => studio,
                  ),
                  const Divider(height: 1),
                ],
                
                // 系列
                if (options.series.isNotEmpty) ...[
                  _buildExpansionTile(
                    title: '系列',
                    selectedValue: filters.series,
                    children: options.series,
                    selectedItem: filters.series,
                    onSelected: (series) {
                      ref.read(mediaFiltersProvider.notifier).updateSeries(
                        filters.series == series ? null : series,
                      );
                    },
                    itemBuilder: (series) => series,
                  ),
                  const Divider(height: 1),
                ],
                
                // 类型/流派
                if (options.genres.isNotEmpty) ...[
                  _buildExpansionTile(
                    title: '类型',
                    selectedValue: filters.genre,
                    children: options.genres,
                    selectedItem: filters.genre,
                    onSelected: (genre) {
                      ref.read(mediaFiltersProvider.notifier).updateGenre(
                        filters.genre == genre ? null : genre,
                      );
                    },
                    itemBuilder: (genre) => genre,
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
            crossFadeState: _isFilterPanelExpanded 
                ? CrossFadeState.showSecond 
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ),
        
        // 已选筛选条件标签（折叠时显示）
        if (!_isFilterPanelExpanded && filters.hasFilters)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (filters.year != null)
                    Chip(
                      label: Text('${filters.year}'),
                      onDeleted: () => ref.read(mediaFiltersProvider.notifier).updateYear(null),
                      deleteIconColor: Colors.grey,
                    ),
                  if (filters.mediaType != null)
                    Chip(
                      label: Text(_getMediaTypeLabel(filters.mediaType!)),
                      onDeleted: () => ref.read(mediaFiltersProvider.notifier).updateMediaType(null),
                      deleteIconColor: Colors.grey,
                    ),
                  if (filters.studio != null)
                    Chip(
                      label: Text(filters.studio!),
                      onDeleted: () => ref.read(mediaFiltersProvider.notifier).updateStudio(null),
                      deleteIconColor: Colors.grey,
                    ),
                  if (filters.series != null)
                    Chip(
                      label: Text(filters.series!),
                      onDeleted: () => ref.read(mediaFiltersProvider.notifier).updateSeries(null),
                      deleteIconColor: Colors.grey,
                    ),
                  if (filters.genre != null)
                    Chip(
                      label: Text(filters.genre!),
                      onDeleted: () => ref.read(mediaFiltersProvider.notifier).updateGenre(null),
                      deleteIconColor: Colors.grey,
                    ),
                ],
              ),
            ),
          ),
        
        // 结果标题
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '结果',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                mediaList.when(
                  data: (items) => Text(
                    '(${items.length})',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('(错误)'),
                ),
                const Spacer(),
                if (!_isSelectionMode)
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: '多选模式',
                    onPressed: _toggleSelectionMode,
                  ),
              ],
            ),
          ),
        ),
        
        // 结果列表
        mediaList.when(
          data: (items) {
            if (items.isEmpty) {
              return SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '没有找到匹配的内容',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '尝试调整筛选条件',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            
            // 通过检测图片比例自动选择网格布局
            return FutureBuilder<bool>(
              future: _detectIsLandscape(items),
              builder: (context, snapshot) {
                final isLandscape = snapshot.data ?? false;
                
                if (isLandscape) {
                  // 横图网格
                  return SliverMasonryMediaGridLandscape(
                    items: items,
                    isSelected: _isSelectionMode ? (id) => _selectedIds.contains(id) : null,
                    onToggleSelection: _isSelectionMode ? _toggleSelection : null,
                  );
                } else {
                  // 竖图网格
                  return SliverMasonryMediaGridPortrait(
                    items: items,
                    isSelected: _isSelectionMode ? (id) => _selectedIds.contains(id) : null,
                    onToggleSelection: _isSelectionMode ? _toggleSelection : null,
                  );
                }
              },
            );
          },
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: Center(child: Text('加载失败: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildExpansionTile<T>({
    required String title,
    required String? selectedValue,
    required List<T> children,
    required T? selectedItem,
    required void Function(T) onSelected,
    required String Function(T) itemBuilder,
  }) {
    return ExpansionTile(
      title: Row(
        children: [
          Text(title),
          if (selectedValue != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                selectedValue,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children.map((item) {
              final isSelected = item == selectedItem;
              return FilterChip(
                label: Text(itemBuilder(item)),
                selected: isSelected,
                onSelected: (_) => onSelected(item),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _getMediaTypeLabel(String mediaType) {
    switch (mediaType) {
      case 'Movie':
        return '电影';
      case 'Scene':
        return '场景';
      case 'Documentary':
        return '纪录片';
      case 'Anime':
        return '动漫';
      case 'Censored':
        return '有码';
      case 'Uncensored':
        return '无码';
      default:
        return mediaType;
    }
  }

  /// 检测图片列表是否主要为横图
  Future<bool> _detectIsLandscape(List<MediaItem> items) async {
    if (items.isEmpty) return false;
    
    // 采样前5张图片来判断
    final sampleSize = items.length > 5 ? 5 : items.length;
    int landscapeCount = 0;
    int portraitCount = 0;
    
    for (int i = 0; i < sampleSize; i++) {
      final media = items[i];
      if (media.posterUrl == null || media.posterUrl!.isEmpty) continue;
      
      try {
        final proxiedUrl = getProxiedImageUrl(media.posterUrl);
        final imageProvider = CachedNetworkImageProvider(proxiedUrl);
        final completer = Completer<ImageInfo>();
        final stream = imageProvider.resolve(const ImageConfiguration());
        
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            if (!completer.isCompleted) {
              completer.complete(info);
            }
            stream.removeListener(listener);
          },
          onError: (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
            stream.removeListener(listener);
          },
        );
        
        stream.addListener(listener);
        
        final info = await completer.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () => throw TimeoutException('Image load timeout'),
        );
        
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        final ratio = width / height;
        
        // 判断横竖：比例 >= 1.0 为横图，< 1.0 为竖图
        if (ratio >= 1.0) {
          landscapeCount++;
        } else {
          portraitCount++;
        }
      } catch (e) {
        // 忽略单张图片的错误，继续检测下一张
        continue;
      }
    }
    
    // 横图数量更多则返回 true
    return landscapeCount > portraitCount;
  }
}

/// 可选择的媒体卡片
class _SelectableMediaCard extends StatelessWidget {
  final MediaItem media;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableMediaCard({
    required this.media,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          MediaCard(media: media, onTap: onTap),
          // 选择指示器
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black45,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
          // 选中时的遮罩
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 批量编辑对话框
class _BatchEditDialog extends StatefulWidget {
  final int selectedCount;

  const _BatchEditDialog({required this.selectedCount});

  @override
  State<_BatchEditDialog> createState() => _BatchEditDialogState();
}

class _BatchEditDialogState extends State<_BatchEditDialog> {
  String? _selectedMediaType;
  final _studioController = TextEditingController();
  final _seriesController = TextEditingController();

  @override
  void dispose() {
    _studioController.dispose();
    _seriesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('批量编辑 ${widget.selectedCount} 个媒体'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('只有填写的字段会被更新', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            
            // 媒体类型
            DropdownButtonFormField<String>(
              value: _selectedMediaType,
              decoration: const InputDecoration(
                labelText: '媒体类型',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('不修改')),
                DropdownMenuItem(value: 'Movie', child: Text('电影')),
                DropdownMenuItem(value: 'Scene', child: Text('场景')),
                DropdownMenuItem(value: 'Anime', child: Text('动漫')),
                DropdownMenuItem(value: 'Documentary', child: Text('纪录片')),
                DropdownMenuItem(value: 'Censored', child: Text('有码')),
                DropdownMenuItem(value: 'Uncensored', child: Text('无码')),
              ],
              onChanged: (value) => setState(() => _selectedMediaType = value),
            ),
            const SizedBox(height: 16),
            
            // 制作公司
            TextField(
              controller: _studioController,
              decoration: const InputDecoration(
                labelText: '制作商',
                hintText: '留空则不修改',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // 系列
            TextField(
              controller: _seriesController,
              decoration: const InputDecoration(
                labelText: '系列',
                hintText: '留空则不修改',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final updates = BatchEditUpdates(
              mediaType: _selectedMediaType,
              studio: _studioController.text.isEmpty ? null : _studioController.text,
              series: _seriesController.text.isEmpty ? null : _seriesController.text,
            );
            Navigator.pop(context, updates);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
