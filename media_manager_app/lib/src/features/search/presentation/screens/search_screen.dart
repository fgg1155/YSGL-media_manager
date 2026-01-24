import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../shared/widgets/media_card.dart';
import '../../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 如果有初始查询,设置到输入框并执行搜索
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      // 延迟执行搜索,确保widget已经构建完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onSearch(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      ref.read(searchResultsProvider.notifier).clear();
      return;
    }
    
    final filters = ref.read(searchFiltersProvider);
    ref.read(searchResultsProvider.notifier).search(
      query,
      mediaType: filters.mediaType?.name,
    );
    
    ref.read(searchHistoryProvider.notifier).addSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchResultsProvider);
    final searchHistory = ref.watch(searchHistoryProvider);
    final trendingSearches = ref.watch(trendingSearchesProvider);
    final filters = ref.watch(searchFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: filters.hasFilters,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '搜索电影和场景...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchResultsProvider.notifier).clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: (value) => setState(() {}),
              onSubmitted: _onSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: searchResults.when(
              data: (results) {
                if (results == null) {
                  return _buildSearchSuggestions(searchHistory, trendingSearches);
                }
                if (results.isEmpty) {
                  return _buildEmptyResults();
                }
                return _buildSearchResults(results);
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
                      onPressed: () => _onSearch(_searchController.text),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestions(List<String> history, AsyncValue<List<String>> trending) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (history.isNotEmpty) ...[
          _buildSectionHeader('最近搜索', onClear: () {
            ref.read(searchHistoryProvider.notifier).clearHistory();
          }),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: history.map((query) => InputChip(
              label: Text(query),
              onPressed: () {
                _searchController.text = query;
                _onSearch(query);
              },
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                ref.read(searchHistoryProvider.notifier).removeSearch(query);
              },
            )).toList(),
          ),
          const SizedBox(height: 24),
        ],
        _buildSectionHeader('热门搜索'),
        trending.when(
          data: (searches) {
            if (searches.isEmpty) {
              return const Text('暂无热门搜索');
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: searches.map((query) => ActionChip(
                label: Text(query),
                avatar: const Icon(Icons.trending_up, size: 16),
                onPressed: () {
                  _searchController.text = query;
                  _onSearch(query);
                },
              )).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('加载热门搜索失败: $error'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onClear}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (onClear != null) TextButton(onPressed: onClear, child: const Text('清除')),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('未找到结果', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('尝试不同的关键词或筛选条件', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<MediaItem> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('${results.length} 个结果', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ),
        Expanded(
          // 通过检测图片比例自动选择网格布局
          child: FutureBuilder<bool>(
            future: _detectIsLandscape(results),
            builder: (context, snapshot) {
              final isLandscape = snapshot.data ?? false;
              
              if (isLandscape) {
                return MasonryMediaGridLandscape(
                  items: results,
                  isLoading: false,
                );
              } else {
                return MasonryMediaGridPortrait(
                  items: results,
                  isLoading: false,
                );
              }
            },
          ),
        ),
      ],
    );
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

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => const _FilterSheet());
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(searchFiltersProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('筛选', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(onPressed: () => ref.read(searchFiltersProvider.notifier).reset(), child: const Text('重置')),
                ],
              ),
              const SizedBox(height: 16),
              Text('媒体类型', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('全部'), selected: filters.mediaType == null, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(null)),
                  ChoiceChip(label: const Text('电影'), selected: filters.mediaType == MediaType.movie, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(MediaType.movie)),
                  ChoiceChip(label: const Text('场景'), selected: filters.mediaType == MediaType.scene, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(MediaType.scene)),
                  ChoiceChip(label: const Text('动漫'), selected: filters.mediaType == MediaType.anime, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(MediaType.anime)),
                  ChoiceChip(label: const Text('纪录片'), selected: filters.mediaType == MediaType.documentary, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(MediaType.documentary)),
                  ChoiceChip(label: const Text('有码'), selected: filters.mediaType == MediaType.censored, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(MediaType.censored)),
                  ChoiceChip(label: const Text('无码'), selected: filters.mediaType == MediaType.uncensored, onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateMediaType(MediaType.uncensored)),
                ],
              ),
              const SizedBox(height: 16),
              Text('来源', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('全部'), selected: filters.source == 'all', onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateSource('all')),
                  ChoiceChip(label: const Text('本地'), selected: filters.source == 'local', onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateSource('local')),
                  ChoiceChip(label: const Text('TMDB'), selected: filters.source == 'tmdb', onSelected: (_) => ref.read(searchFiltersProvider.notifier).updateSource('tmdb')),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('应用筛选')),
            ],
          ),
        );
      },
    );
  }
}
