import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/backend_mode.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../../../shared/widgets/media_card.dart';
import '../../../media/providers/media_providers.dart';
import '../../../media/providers/plugin_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedMediaType = 'all';
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  DateTime? _lastBackPressed;
  final _scrollController = ScrollController();
  int _currentPage = 1;
  Timer? _debounceTimer;  // 防抖定时器
  bool _isLoadingMore = false;  // 防止重复加载
  String? _cachedRoute;  // 缓存路由状态
  bool? _cachedIsLandscape;  // 缓存横竖图判断结果
  List<MediaItem>? _lastDetectedItems;  // 上次检测的数据

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 首页进入时重置全局筛选条件（首页使用本地筛选）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mediaFiltersProvider.notifier).reset();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在依赖变化时更新路由缓存
    _cachedRoute = GoRouterState.of(context).uri.toString();
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
      
      // 预加载即将出现的图片
      _preloadUpcomingImages();
    });
  }

  void _preloadUpcomingImages() {
    final mediaList = ref.read(mediaListProvider).value;
    if (mediaList == null || mediaList.isEmpty) return;
    
    // 计算当前可见区域
    final scrollPosition = _scrollController.position.pixels;
    final viewportHeight = _scrollController.position.viewportDimension;
    
    // 预加载即将进入视口的图片（提前一屏的距离）
    final preloadThreshold = scrollPosition + viewportHeight * 1.5;
    
    // 估算每个卡片的高度（根据网格布局）
    final cardHeight = 300.0; // 大约高度
    final cardsPerRow = 2; // 默认每行2个
    
    // 计算应该预加载哪些图片
    final startIndex = ((scrollPosition + viewportHeight) / cardHeight * cardsPerRow).floor();
    final endIndex = (preloadThreshold / cardHeight * cardsPerRow).ceil();
    
    // 预加载图片
    for (int i = startIndex; i < endIndex && i < mediaList.length; i++) {
      final media = mediaList[i];
      if (media.posterUrl != null) {
        precacheImage(
          CachedNetworkImageProvider(getProxiedImageUrl(media.posterUrl)),
          context,
        );
      }
    }
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
        context.showSuccess('成功删除 ${_selectedIds.length} 个媒体');
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        context.showError('删除失败: $e');
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
        context.showSuccess('成功编辑 ${_selectedIds.length} 个媒体');
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        context.showError('编辑失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaList = ref.watch(mediaListProvider);
    final isOnHomePage = _cachedRoute == '/';  // 使用缓存的路由状态

    return PopScope(
      canPop: !isOnHomePage, // 只在首页时禁止直接返回
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        // 只在首页时执行双击退出逻辑
        if (!isOnHomePage) return;
        
        // 双击返回退出提示
        final now = DateTime.now();
        if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          if (mounted) {
            context.showInfo('再按一次退出应用');
          }
        } else {
          // 用户在2秒内再次按返回，退出应用
          if (mounted) {
            await SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          _currentPage = 1; // 重置页码
          // 清除图片比例缓存
          _cachedIsLandscape = null;
          _lastDetectedItems = null;
          ref.invalidate(mediaListProvider);
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (!_isSelectionMode) ...[
              // Welcome section
              SliverToBoxAdapter(child: _buildWelcomeSection()),
              // Quick actions
              SliverToBoxAdapter(child: _buildQuickActions()),
            ],
            
            // Media type selector
            mediaList.when(
              data: (items) {
                final existingTypes = items.map((e) => e.mediaType).toSet().toList();
                return SliverToBoxAdapter(
                  child: _buildDynamicMediaTypeSelector(existingTypes),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            
            // Title with count
            mediaList.when(
              data: (items) {
                final filteredItems = _selectedMediaType == 'all'
                    ? items
                    : items.where((item) => item.mediaType.name == _selectedMediaType).toList();
                
                String title = '全部媒体';
                if (_selectedMediaType != 'all') {
                  final type = MediaType.values.firstWhere(
                    (t) => t.name == _selectedMediaType,
                    orElse: () => MediaType.movie,
                  );
                  title = _getMediaTypeLabel(type);
                }
                
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          '$title (${filteredItems.length})',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            
            // Media grid
            mediaList.when(
              data: (items) {
                final filteredItems = _selectedMediaType == 'all'
                    ? items
                    : items.where((item) => item.mediaType.name == _selectedMediaType).toList();
                
                if (filteredItems.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('暂无媒体', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(
                            '搜索并添加电影或场景',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => context.push('/search'),
                            icon: const Icon(Icons.search),
                            label: const Text('搜索'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                // 通过检测图片比例来判断使用哪个网格
                // 采样前几张图片（最多5张）来快速判断
                return FutureBuilder<bool>(
                  future: _detectIsLandscape(filteredItems),
                  builder: (context, snapshot) {
                    final isLandscape = snapshot.data ?? false;
                    
                    if (isLandscape) {
                      // 横图网格
                      return SliverMasonryMediaGridLandscape(
                        items: filteredItems,
                        isSelected: _isSelectionMode ? (id) => _selectedIds.contains(id) : null,
                        onToggleSelection: _isSelectionMode ? _toggleSelection : null,
                      );
                    } else {
                      // 竖图网格
                      return SliverMasonryMediaGridPortrait(
                        items: filteredItems,
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
              error: (error, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('加载失败'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          // 清除图片比例缓存
                          _cachedIsLandscape = null;
                          _lastDetectedItems = null;
                          ref.invalidate(mediaListProvider);
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isSelectionMode ? _buildSelectionBottomBar() : _buildNavigationBar(),
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    final modeManager = ref.watch(backendModeManagerProvider);
    final isPcMode = modeManager.isPcMode;
    
    // 判断是否为移动端
    final isMobile = _isMobile();
    
    return AppBar(
      // 桌面端不显示模式切换按钮（桌面端强制使用 PC 模式）
      leading: isMobile ? IconButton(
        icon: Icon(
          isPcMode ? Icons.cloud : Icons.phone_android,
          color: isPcMode ? Colors.blue : Colors.green,
        ),
        tooltip: isPcMode ? 'PC模式' : '独立模式',
        onPressed: () => _toggleMode(modeManager),
      ) : null,
      title: const Text('媒体管理器'),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => context.push('/media/new'),
          tooltip: '新增媒体',
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => context.push('/search'),
          tooltip: '搜索',
        ),
      ],
    );
  }
  
  /// 判断是否为移动端
  bool _isMobile() {
    try {
      return Theme.of(context).platform == TargetPlatform.android ||
             Theme.of(context).platform == TargetPlatform.iOS;
    } catch (e) {
      return false;
    }
  }

  Future<void> _toggleMode(BackendModeManager modeManager) async {
    final isPcMode = modeManager.isPcMode;
    final targetMode = !isPcMode; // 切换到相反的模式
    
    // 显示切换提示
    context.showInfo(targetMode ? '正在切换到PC模式...' : '正在切换到独立模式...');
    
    try {
      if (targetMode) {
        // 切换到PC模式：检查PC后端是否可用
        final isAvailable = await modeManager.checkPcBackendAvailability();
        
        if (isAvailable) {
          // 保存用户选择
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('backend_mode', 'pc');
          
          // 获取 PC 后端 URL 并更新 apiBaseUrlProvider
          final pcBackendUrl = prefs.getString('pc_backend_url') ?? 'http://localhost:3000';
          ref.read(apiBaseUrlProvider.notifier).state = pcBackendUrl;
          print('✓ 切换到 PC 模式，API URL 更新为: $pcBackendUrl');
          
          modeManager.setMode(BackendMode.pc);
          if (mounted) {
            context.showSuccess('已切换到PC模式\n数据将在后台加载');
            // 延迟刷新数据，避免阻塞 UI
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                // 清除图片比例缓存
                _cachedIsLandscape = null;
                _lastDetectedItems = null;
                // 刷新媒体列表和插件列表
                ref.invalidate(mediaListProvider);
                ref.invalidate(pluginsProvider);
              }
            });
          }
        } else {
          if (mounted) {
            SnackBarUtils.showWithAction(
              context,
              '无法连接PC后端，请检查网络和服务器设置',
              actionLabel: '去设置',
              onAction: () => context.push('/settings'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            );
          }
        }
      } else {
        // 保存用户选择
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('backend_mode', 'standalone');
        
        // 切换到独立模式时，使用本地服务器地址
        ref.read(apiBaseUrlProvider.notifier).state = 'http://localhost:8080';
        print('✓ 切换到独立模式，API URL 更新为: http://localhost:8080');
        
        // 切换到独立模式
        modeManager.setMode(BackendMode.standalone);
        if (mounted) {
          context.showSuccess('已切换到独立模式\n数据将在后台加载');
          // 延迟刷新数据，避免阻塞 UI
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              // 清除图片比例缓存
              _cachedIsLandscape = null;
              _lastDetectedItems = null;
              // 刷新媒体列表和插件列表
              ref.invalidate(mediaListProvider);
              ref.invalidate(pluginsProvider);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        context.showError('切换失败: $e');
      }
    }
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _toggleSelectionMode,
      ),
      title: Text('已选择 ${_selectedIds.length} 项'),
      actions: [
        TextButton(
          onPressed: () {
            final items = ref.read(mediaListProvider).value ?? [];
            final filteredItems = _selectedMediaType == 'all'
                ? items
                : items.where((item) => item.mediaType.name == _selectedMediaType).toList();
            _selectAll(filteredItems);
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
      selectedIndex: 0,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
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

  Widget _buildWelcomeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '欢迎回来！',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '发现和管理您喜爱的电影和场景',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionCard(
              icon: Icons.filter_list,
              label: '筛选',
              onTap: () => context.go('/filter'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.library_books,
              label: '收藏',
              onTap: () => context.go('/collection'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.person,
              label: '演员',
              onTap: () => context.go('/actors'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicMediaTypeSelector(List<MediaType> existingTypes) {
    final orderedTypes = <MediaType>[];
    for (final type in [MediaType.movie, MediaType.scene, MediaType.anime, MediaType.documentary, MediaType.censored, MediaType.uncensored]) {
      if (existingTypes.contains(type)) {
        orderedTypes.add(type);
      }
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: _selectedMediaType == 'all',
            onSelected: (_) => setState(() => _selectedMediaType = 'all'),
          ),
          ...orderedTypes.map((type) => ChoiceChip(
            label: Text(_getMediaTypeLabel(type)),
            selected: _selectedMediaType == type.name,
            onSelected: (_) => setState(() => _selectedMediaType = type.name),
          )),
        ],
      ),
    );
  }

  String _getMediaTypeLabel(MediaType type) {
    switch (type) {
      case MediaType.movie:
        return '电影';
      case MediaType.scene:
        return '场景';
      case MediaType.anime:
        return '动漫';
      case MediaType.documentary:
        return '纪录片';
      case MediaType.censored:
        return '有码';
      case MediaType.uncensored:
        return '无码';
    }
  }

  /// 检测图片列表是否主要为横图（带缓存）
  Future<bool> _detectIsLandscape(List<MediaItem> items) async {
    if (items.isEmpty) return false;
    
    // 如果数据没变，直接返回缓存结果
    if (_lastDetectedItems != null && 
        _cachedIsLandscape != null &&
        _lastDetectedItems!.length == items.length &&
        _lastDetectedItems!.first.id == items.first.id) {
      return _cachedIsLandscape!;
    }
    
    // 采样前3张图片来判断（减少采样数量）
    final sampleSize = items.length > 3 ? 3 : items.length;
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
          const Duration(milliseconds: 500),  // 减少超时时间到500ms
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
    
    // 缓存结果
    final result = landscapeCount > portraitCount;
    _lastDetectedItems = items;
    _cachedIsLandscape = result;
    
    return result;
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
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
                labelText: '制作公司',
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
