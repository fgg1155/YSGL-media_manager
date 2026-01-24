import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/media_item.dart';
import '../../../core/services/api_service.dart';
import '../../../core/providers/app_providers.dart';

export '../../../core/services/api_service.dart' show BatchDeleteResponse, BatchEditResponse, BatchEditUpdates;

part 'media_providers.g.dart';

// Media list state
@riverpod
class MediaList extends _$MediaList {
  @override
  Future<List<MediaItem>> build() async {
    final repository = ref.read(mediaRepositoryProvider);
    // 监听筛选条件变化，但只在筛选条件实际改变时重建
    final filters = ref.watch(mediaFiltersProvider);
    
    final response = await repository.getMediaList(
      mediaType: filters.mediaType,
      studio: filters.studio,
      series: filters.series,
      keyword: filters.keyword,
      sortBy: filters.sortBy,
      sortOrder: filters.sortOrder,
      page: 1,
    );
    return response.items;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(mediaRepositoryProvider);
      final filters = ref.read(mediaFiltersProvider);
      
      final response = await repository.getMediaList(
        mediaType: filters.mediaType,
        studio: filters.studio,
        series: filters.series,
        keyword: filters.keyword,
        sortBy: filters.sortBy,
        sortOrder: filters.sortOrder,
        page: 1,
      );
      return response.items;
    });
  }

  Future<void> loadMore({int page = 2}) async {
    if (state.isLoading) return;
    
    final currentItems = state.value ?? [];
    
    try {
      final repository = ref.read(mediaRepositoryProvider);
      final filters = ref.read(mediaFiltersProvider);
      
      final response = await repository.getMediaList(
        page: page,
        mediaType: filters.mediaType,
        studio: filters.studio,
        series: filters.series,
        keyword: filters.keyword,
        sortBy: filters.sortBy,
        sortOrder: filters.sortOrder,
      );
      
      state = AsyncValue.data([...currentItems, ...response.items]);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> addMedia(MediaItem media) async {
    try {
      final repository = ref.read(mediaRepositoryProvider);
      final newMedia = await repository.addMedia(media);
      
      final currentItems = state.value ?? [];
      state = AsyncValue.data([newMedia, ...currentItems]);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateMedia(MediaItem media) async {
    try {
      final repository = ref.read(mediaRepositoryProvider);
      await repository.updateMedia(media);
      
      final currentItems = state.value ?? [];
      final updatedItems = currentItems.map((item) {
        return item.id == media.id ? media : item;
      }).toList();
      
      state = AsyncValue.data(updatedItems);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> deleteMedia(String id) async {
    try {
      final repository = ref.read(mediaRepositoryProvider);
      await repository.deleteMedia(id);
      
      final currentItems = state.value ?? [];
      final filteredItems = currentItems.where((item) => item.id != id).toList();
      
      state = AsyncValue.data(filteredItems);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// 批量删除媒体
  Future<void> batchDeleteMedia(List<String> ids) async {
    final repository = ref.read(mediaRepositoryProvider);
    await repository.batchDeleteMedia(ids);
    
    // 从列表中移除已删除的项
    final currentItems = state.value ?? [];
    final deletedIds = ids.toSet();
    final filteredItems = currentItems.where((item) => !deletedIds.contains(item.id)).toList();
    state = AsyncValue.data(filteredItems);
  }

  /// 批量编辑媒体 - 暂不支持，需要刷新列表
  Future<void> batchEditMedia(List<String> ids) async {
    // 刷新列表以获取更新后的数据
    await refresh();
  }
}

// Media detail state
@riverpod
class MediaDetail extends _$MediaDetail {
  @override
  Future<MediaItem?> build(String mediaId) async {
    if (mediaId.isEmpty) return null;
    
    final repository = ref.read(mediaRepositoryProvider);
    return await repository.getMedia(mediaId);
  }

  Future<void> refresh() async {
    final mediaId = state.value?.id;
    if (mediaId == null) return;
    
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(mediaRepositoryProvider);
      return await repository.getMedia(mediaId);
    });
  }
}

// Popular content state - 暂时使用 API 服务（需要 TMDB 支持）
@riverpod
class PopularContent extends _$PopularContent {
  @override
  Future<List<MediaItem>> build({String mediaType = 'movie'}) async {
    final apiService = ref.read(apiServiceProvider);
    return await apiService.getPopularContent(mediaType: mediaType);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final apiService = ref.read(apiServiceProvider);
      return await apiService.getPopularContent();
    });
  }

  Future<void> changeMediaType(String mediaType) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final apiService = ref.read(apiServiceProvider);
      return await apiService.getPopularContent(mediaType: mediaType);
    });
  }
}

// TMDB details state - 暂时使用 API 服务（需要 TMDB 支持）
@riverpod
class TmdbDetails extends _$TmdbDetails {
  @override
  Future<MediaItem?> build({required int tmdbId, required String mediaType}) async {
    final apiService = ref.read(apiServiceProvider);
    return await apiService.getTmdbDetails(tmdbId: tmdbId, mediaType: mediaType);
  }

  Future<MediaItem?> saveTmdbMedia() async {
    final mediaItem = state.value;
    if (mediaItem == null) return null;
    
    try {
      final repository = ref.read(mediaRepositoryProvider);
      final savedMedia = await repository.addMedia(mediaItem);
      
      // Refresh media list to include the new item
      ref.invalidate(mediaListProvider);
      
      return savedMedia;
    } catch (error) {
      rethrow;
    }
  }
}

// Media filters state
@riverpod
class MediaFilters extends _$MediaFilters {
  @override
  MediaFiltersState build() {
    return const MediaFiltersState();
  }

  void updateMediaType(String? mediaType) {
    state = state.copyWith(mediaType: mediaType, clearMediaType: mediaType == null);
  }

  void updateStudio(String? studio) {
    state = state.copyWith(studio: studio, clearStudio: studio == null);
  }

  void updateSeries(String? series) {
    state = state.copyWith(series: series, clearSeries: series == null);
  }

  void updateKeyword(String? keyword) {
    state = state.copyWith(keyword: keyword, clearKeyword: keyword == null || keyword.isEmpty);
  }

  void updateYear(int? year) {
    state = state.copyWith(year: year, clearYear: year == null);
  }

  void updateGenre(String? genre) {
    state = state.copyWith(genre: genre, clearGenre: genre == null);
  }

  void updateSortBy(String sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void updateSortOrder(String sortOrder) {
    state = state.copyWith(sortOrder: sortOrder);
  }

  void reset() {
    state = const MediaFiltersState();
  }
}

class MediaFiltersState {
  final String? mediaType;
  final String? studio;
  final String? series;
  final String? keyword;
  final int? year;
  final String? genre;
  final String sortBy;
  final String sortOrder;

  const MediaFiltersState({
    this.mediaType,
    this.studio,
    this.series,
    this.keyword,
    this.year,
    this.genre,
    this.sortBy = 'created_at',
    this.sortOrder = 'desc',
  });

  MediaFiltersState copyWith({
    String? mediaType,
    String? studio,
    String? series,
    String? keyword,
    int? year,
    String? genre,
    String? sortBy,
    String? sortOrder,
    bool clearMediaType = false,
    bool clearStudio = false,
    bool clearSeries = false,
    bool clearKeyword = false,
    bool clearYear = false,
    bool clearGenre = false,
  }) {
    return MediaFiltersState(
      mediaType: clearMediaType ? null : (mediaType ?? this.mediaType),
      studio: clearStudio ? null : (studio ?? this.studio),
      series: clearSeries ? null : (series ?? this.series),
      keyword: clearKeyword ? null : (keyword ?? this.keyword),
      year: clearYear ? null : (year ?? this.year),
      genre: clearGenre ? null : (genre ?? this.genre),
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  bool get hasFilters {
    return mediaType != null ||
        studio != null ||
        series != null ||
        (keyword != null && keyword!.isNotEmpty) ||
        year != null ||
        genre != null;
  }
}

/// 筛选选项 Provider - 使用 Repository（支持独立模式和 PC 模式）
@riverpod
class FilterOptionsNotifier extends _$FilterOptionsNotifier {
  @override
  Future<FilterOptions> build() async {
    final repository = ref.read(mediaRepositoryProvider);
    return await repository.getFilterOptions();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(mediaRepositoryProvider);
      return await repository.getFilterOptions();
    });
  }
}