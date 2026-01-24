import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/models/collection.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../media/providers/media_providers.dart';
import '../../providers/collection_providers.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionListProvider);
    final filter = ref.watch(collectionFilterProvider);
    final filteredItems = ref.watch(filteredCollectionsProvider);
    final currentRoute = GoRouterState.of(context).uri.toString();
    final isOnCollectionPage = currentRoute == '/collection';

    return PopScope(
      canPop: !isOnCollectionPage, // 只在收藏页时禁止直接返回
      onPopInvoked: (didPop) {
        // 只在收藏页时拦截返回，其他情况允许正常返回
        if (!isOnCollectionPage) return;
        // 左滑无反应，用户应该使用底部导航栏切换页面
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // 移除自动返回按钮
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            icon: Icon(filter.hasFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: () => _showFilterSheet(context, ref),
          ),
          PopupMenuButton<CollectionSortBy>(
            icon: const Icon(Icons.sort),
            onSelected: (sortBy) {
              ref.read(collectionFilterProvider.notifier).updateSortBy(sortBy);
            },
            itemBuilder: (context) => [
              _buildSortMenuItem(CollectionSortBy.addedAt, '添加日期', filter.sortBy),
              _buildSortMenuItem(CollectionSortBy.lastWatched, '最近观看', filter.sortBy),
              _buildSortMenuItem(CollectionSortBy.rating, '评分', filter.sortBy),
              _buildSortMenuItem(CollectionSortBy.title, '标题', filter.sortBy),
            ],
          ),
        ],
      ),
      body: collectionsAsync.when(
        data: (collections) {
          if (collections.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return RefreshIndicator(
            onRefresh: () => ref.read(collectionListProvider.notifier).refresh(),
            child: CustomScrollView(
              slivers: [
                // Stats header
                SliverToBoxAdapter(
                  child: _buildStatsHeader(context, collections),
                ),
                
                // Filter chips
                if (filter.hasFilters)
                  SliverToBoxAdapter(
                    child: _buildActiveFilters(context, ref, filter),
                  ),
                
                // Collection grid - 瀑布流布局
                SliverPadding(
                  padding: const EdgeInsets.all(8),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      int crossAxisCount;
                      if (width > 1200) {
                        crossAxisCount = 5;
                      } else if (width > 900) {
                        crossAxisCount = 4;
                      } else if (width > 600) {
                        crossAxisCount = 3;
                      } else {
                        crossAxisCount = 2;
                      }
                      
                      return SliverMasonryGrid.count(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childCount: filteredItems.length,
                        itemBuilder: (context, index) => _CollectionItemCard(
                          collection: filteredItems[index],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载收藏失败'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.read(collectionListProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/filter');
              break;
            case 2:
              // Already on collection
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
      ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '收藏为空',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '开始添加电影和场景',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search),
            label: const Text('搜索内容'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(BuildContext context, List<Collection> collections) {
    final watching = collections.where((c) => c.watchStatus == WatchStatus.watching).length;
    final completed = collections.where((c) => c.watchStatus == WatchStatus.completed).length;
    final favorites = collections.where((c) => c.isFavorite).length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(label: '总计', value: collections.length.toString()),
          _StatItem(label: '在看', value: watching.toString()),
          _StatItem(label: '已完成', value: completed.toString()),
          _StatItem(label: '收藏', value: favorites.toString()),
        ],
      ),
    );
  }

  Widget _buildActiveFilters(BuildContext context, WidgetRef ref, CollectionFilterState filter) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (filter.watchStatus != null)
            Chip(
              label: Text(_getStatusText(filter.watchStatus!)),
              onDeleted: () {
                ref.read(collectionFilterProvider.notifier).updateWatchStatus(null);
              },
            ),
          if (filter.favoriteOnly)
            Chip(
              label: const Text('收藏'),
              onDeleted: () {
                ref.read(collectionFilterProvider.notifier).updateFavoriteOnly(false);
              },
            ),
          TextButton(
            onPressed: () => ref.read(collectionFilterProvider.notifier).reset(),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<CollectionSortBy> _buildSortMenuItem(
    CollectionSortBy value,
    String label,
    CollectionSortBy current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (value == current)
            const Icon(Icons.check, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final filter = ref.read(collectionFilterProvider);
    
    showModalBottomSheet(
      context: context,
      builder: (context) => _FilterSheet(initialFilter: filter),
    );
  }

  String _getStatusText(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return '想看';
      case WatchStatus.watching:
        return '在看';
      case WatchStatus.completed:
        return '已完成';
      case WatchStatus.onHold:
        return '搁置';
      case WatchStatus.dropped:
        return '弃看';
    }
  }
}


class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

class _CollectionItemCard extends ConsumerStatefulWidget {
  final Collection collection;

  const _CollectionItemCard({required this.collection});

  @override
  ConsumerState<_CollectionItemCard> createState() => _CollectionItemCardState();
}

class _CollectionItemCardState extends ConsumerState<_CollectionItemCard> {
  double _aspectRatio = 0.67; // 默认竖版 2:3

  void _detectImageAspectRatio(String? posterUrl) {
    if (posterUrl == null) return;
    final proxiedUrl = getProxiedImageUrl(posterUrl);
    final imageProvider = CachedNetworkImageProvider(proxiedUrl);
    imageProvider.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) {
          final width = info.image.width.toDouble();
          final height = info.image.height.toDouble();
          setState(() => _aspectRatio = width / height);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaDetailProvider(widget.collection.mediaId));

    return mediaAsync.when(
      data: (media) {
        if (media == null) {
          return const Card(child: Center(child: Icon(Icons.error_outline, color: Colors.grey)));
        }
        
        // 检测图片比例
        if (media.posterUrl != null) {
          _detectImageAspectRatio(media.posterUrl);
        }
        
        return AspectRatio(
          aspectRatio: _aspectRatio,
          child: GestureDetector(
            onTap: () => context.push('/media/${widget.collection.mediaId}'),
            onLongPress: () => _showOptionsSheet(context),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面图
                  media.posterUrl != null
                      ? CachedNetworkImage(
                          imageUrl: getProxiedImageUrl(media.posterUrl),
                          fit: BoxFit.cover,
                          memCacheWidth: 400,  // 收藏页面图片缓存优化
                          memCacheHeight: 600,
                          placeholder: (_, __) => Container(color: Colors.grey[800]),
                          errorWidget: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                  
                  // 渐变遮罩
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                        ),
                      ),
                    ),
                  ),
                  
                  // 状态标签
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusColor(widget.collection.watchStatus),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getStatusShortText(widget.collection.watchStatus),
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  
                  // 收藏图标
                  if (widget.collection.isFavorite)
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.favorite, color: Colors.red, size: 14),
                      ),
                    ),
                  
                  // 进度条
                  if (widget.collection.watchProgress != null && widget.collection.watchProgress! > 0)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(
                        value: widget.collection.watchProgress,
                        backgroundColor: Colors.black38,
                        minHeight: 3,
                      ),
                    ),
                  
                  // 标题和评分
                  Positioned(
                    left: 8, right: 8, bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          media.title,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.collection.personalRating != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star, size: 12, color: Colors.amber),
                              const SizedBox(width: 2),
                              Text(
                                widget.collection.personalRating!.toStringAsFixed(1),
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 10),
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
        );
      },
      loading: () => const AspectRatio(
        aspectRatio: 0.67,
        child: Card(child: Center(child: CircularProgressIndicator())),
      ),
      error: (_, __) => const AspectRatio(
        aspectRatio: 0.67,
        child: Card(child: Center(child: Icon(Icons.error_outline, color: Colors.grey))),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Icon(Icons.movie, size: 48, color: Colors.grey),
    );
  }

  Color _getStatusColor(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch: return Colors.blue;
      case WatchStatus.watching: return Colors.green;
      case WatchStatus.completed: return Colors.purple;
      case WatchStatus.onHold: return Colors.orange;
      case WatchStatus.dropped: return Colors.red;
    }
  }

  String _getStatusShortText(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch: return '想看';
      case WatchStatus.watching: return '在看';
      case WatchStatus.completed: return '完成';
      case WatchStatus.onHold: return '搁置';
      case WatchStatus.dropped: return '弃看';
    }
  }

  void _showOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑状态'),
              onTap: () {
                Navigator.pop(context);
                _showStatusDialog(context);
              },
            ),
            ListTile(
              leading: Icon(
                widget.collection.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: widget.collection.isFavorite ? Colors.red : null,
              ),
              title: Text(widget.collection.isFavorite ? '取消收藏' : '添加收藏'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('从收藏中移除'),
              onTap: () {
                Navigator.pop(context);
                _showRemoveDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更新状态'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: WatchStatus.values.map((status) {
            return RadioListTile<WatchStatus>(
              title: Text(_getStatusFullText(status)),
              value: status,
              groupValue: widget.collection.watchStatus,
              onChanged: (value) {
                if (value != null) {
                  ref.read(collectionListProvider.notifier).updateStatus(widget.collection.mediaId, value);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getStatusFullText(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch: return '想看';
      case WatchStatus.watching: return '在看';
      case WatchStatus.completed: return '已完成';
      case WatchStatus.onHold: return '搁置';
      case WatchStatus.dropped: return '弃看';
    }
  }

  void _showRemoveDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从收藏中移除'),
        content: const Text('确定要移除此项目吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              ref.read(collectionListProvider.notifier).removeFromCollection(widget.collection.mediaId);
              Navigator.pop(context);
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  final CollectionFilterState initialFilter;

  const _FilterSheet({required this.initialFilter});

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late WatchStatus? _selectedStatus;
  late bool _favoriteOnly;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialFilter.watchStatus;
    _favoriteOnly = widget.initialFilter.favoriteOnly;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '筛选',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedStatus = null;
                      _favoriteOnly = false;
                    });
                  },
                  child: const Text('重置'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Text('观看状态', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _selectedStatus == null,
                  onSelected: (_) => setState(() => _selectedStatus = null),
                ),
                ...WatchStatus.values.map((status) => FilterChip(
                  label: Text(_getStatusText(status)),
                  selected: _selectedStatus == status,
                  onSelected: (_) => setState(() => _selectedStatus = status),
                )),
              ],
            ),
            const SizedBox(height: 16),
            
            SwitchListTile(
              title: const Text('仅显示收藏'),
              value: _favoriteOnly,
              onChanged: (value) => setState(() => _favoriteOnly = value),
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  ref.read(collectionFilterProvider.notifier).updateWatchStatus(_selectedStatus);
                  ref.read(collectionFilterProvider.notifier).updateFavoriteOnly(_favoriteOnly);
                  Navigator.pop(context);
                },
                child: const Text('应用'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return '想看';
      case WatchStatus.watching:
        return '在看';
      case WatchStatus.completed:
        return '完成';
      case WatchStatus.onHold:
        return '搁置';
      case WatchStatus.dropped:
        return '弃看';
    }
  }
}
