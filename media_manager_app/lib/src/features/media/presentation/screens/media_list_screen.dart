import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/services/api_service.dart';
import '../../../../shared/widgets/media_card.dart';
import '../../providers/media_providers.dart';

class MediaListScreen extends ConsumerStatefulWidget {
  const MediaListScreen({super.key});

  @override
  ConsumerState<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends ConsumerState<MediaListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaList = ref.watch(mediaListProvider);
    final filters = ref.watch(mediaFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: filters.hasFilters,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _showFilterSheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索标题...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(mediaFiltersProvider.notifier).updateKeyword(null);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onChanged: (value) {
                ref.read(mediaFiltersProvider.notifier).updateKeyword(value.isEmpty ? null : value);
              },
            ),
          ),
          // 筛选标签
          if (filters.hasFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (filters.mediaType != null)
                    _buildFilterChip(
                      label: _getMediaTypeLabel(filters.mediaType!),
                      onRemove: () => ref.read(mediaFiltersProvider.notifier).updateMediaType(null),
                    ),
                  if (filters.studio != null)
                    _buildFilterChip(
                      label: '制作商: ${filters.studio}',
                      onRemove: () => ref.read(mediaFiltersProvider.notifier).updateStudio(null),
                    ),
                  if (filters.series != null)
                    _buildFilterChip(
                      label: '系列: ${filters.series}',
                      onRemove: () => ref.read(mediaFiltersProvider.notifier).updateSeries(null),
                    ),
                  if (filters.year != null)
                    _buildFilterChip(
                      label: '年份: ${filters.year}',
                      onRemove: () => ref.read(mediaFiltersProvider.notifier).updateYear(null),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ref.read(mediaFiltersProvider.notifier).reset(),
                    child: const Text('清除全部'),
                  ),
                ],
              ),
            ),
          // 媒体列表
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(mediaListProvider.notifier).refresh(),
              child: mediaList.when(
                data: (items) {
                  if (items.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  
                  // 根据筛选的媒体类型选择合适的网格布局
                  final isLandscapeType = filters.mediaType == 'Scene' || 
                                          filters.mediaType == 'Uncensored';
                  
                  if (isLandscapeType) {
                    // 场景和无码：使用横图网格
                    return MasonryMediaGridLandscape(
                      items: items,
                      isLoading: false,
                    );
                  } else {
                    // 其他类型：使用竖图网格
                    return MasonryMediaGridPortrait(
                      items: items,
                      isLoading: false,
                    );
                  }
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('错误: $error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.read(mediaListProvider.notifier).refresh(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/search'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: onRemove,
        visualDensity: VisualDensity.compact,
      ),
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '收藏中暂无媒体',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '搜索并添加电影或场景',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search),
            label: const Text('搜索媒体'),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _MediaFilterSheet(
          ref: ref,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _MediaFilterSheet extends ConsumerWidget {
  final WidgetRef ref;
  final ScrollController scrollController;

  const _MediaFilterSheet({required this.ref, required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(mediaFiltersProvider);
    final filterOptionsAsync = ref.watch(filterOptionsNotifierProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '筛选',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      ref.read(mediaFiltersProvider.notifier).reset();
                    },
                    child: const Text('重置'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          
          // 筛选内容
          Expanded(
            child: filterOptionsAsync.when(
              data: (options) => ListView(
                controller: scrollController,
                children: [
                  // 媒体类型
                  _buildSectionTitle(context, '媒体类型'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('全部'),
                        selected: filters.mediaType == null,
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateMediaType(null);
                        },
                      ),
                      ...options.mediaTypes.map((type) => FilterChip(
                        label: Text(_getMediaTypeLabel(type)),
                        selected: filters.mediaType == type,
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateMediaType(
                            filters.mediaType == type ? null : type,
                          );
                        },
                      )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 制作商
                  if (options.studios.isNotEmpty) ...[
                    _buildSectionTitle(context, '制作商'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('全部'),
                          selected: filters.studio == null,
                          onSelected: (_) {
                            ref.read(mediaFiltersProvider.notifier).updateStudio(null);
                          },
                        ),
                        ...options.studios.map((studio) => FilterChip(
                          label: Text(studio),
                          selected: filters.studio == studio,
                          onSelected: (_) {
                            ref.read(mediaFiltersProvider.notifier).updateStudio(
                              filters.studio == studio ? null : studio,
                            );
                          },
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // 系列
                  if (options.series.isNotEmpty) ...[
                    _buildSectionTitle(context, '系列'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('全部'),
                          selected: filters.series == null,
                          onSelected: (_) {
                            ref.read(mediaFiltersProvider.notifier).updateSeries(null);
                          },
                        ),
                        ...options.series.map((s) => FilterChip(
                          label: Text(s),
                          selected: filters.series == s,
                          onSelected: (_) {
                            ref.read(mediaFiltersProvider.notifier).updateSeries(
                              filters.series == s ? null : s,
                            );
                          },
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // 年份
                  if (options.years.isNotEmpty) ...[
                    _buildSectionTitle(context, '年份'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('全部'),
                          selected: filters.year == null,
                          onSelected: (_) {
                            ref.read(mediaFiltersProvider.notifier).updateYear(null);
                          },
                        ),
                        ...options.years.map((year) => FilterChip(
                          label: Text(year.toString()),
                          selected: filters.year == year,
                          onSelected: (_) {
                            ref.read(mediaFiltersProvider.notifier).updateYear(
                              filters.year == year ? null : year,
                            );
                          },
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // 排序
                  _buildSectionTitle(context, '排序'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('添加时间'),
                        selected: filters.sortBy == 'created_at',
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateSortBy('created_at');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('年份'),
                        selected: filters.sortBy == 'year',
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateSortBy('year');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('评分'),
                        selected: filters.sortBy == 'rating',
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateSortBy('rating');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('标题'),
                        selected: filters.sortBy == 'title',
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateSortBy('title');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('降序'),
                        selected: filters.sortOrder == 'desc',
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateSortOrder('desc');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('升序'),
                        selected: filters.sortOrder == 'asc',
                        onSelected: (_) {
                          ref.read(mediaFiltersProvider.notifier).updateSortOrder('asc');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
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
}
