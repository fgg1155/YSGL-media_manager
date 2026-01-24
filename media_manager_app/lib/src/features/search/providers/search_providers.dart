import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/media_item.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/backend_mode.dart';
import '../../../core/providers/app_providers.dart';

part 'search_providers.g.dart';

// Search query state
final searchQueryProvider = StateProvider<String>((ref) => '');

// Search results state
@riverpod
class SearchResults extends _$SearchResults {
  @override
  Future<List<MediaItem>?> build() async {
    return null;
  }

  Future<void> search(String query, {String? mediaType}) async {
    if (query.trim().isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(mediaRepositoryProvider);
      return await repository.searchMedia(query);
    });
  }

  Future<void> advancedSearch(AdvancedSearchRequest request) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.advancedSearch(request);
      return response.results;
    });
  }

  void clear() {
    state = const AsyncValue.data(null);
  }
}

// Search suggestions state - 暂时使用 API 服务
@riverpod
class SearchSuggestions extends _$SearchSuggestions {
  @override
  Future<List<SearchSuggestion>> build() async {
    return [];
  }

  Future<void> getSuggestions(String query) async {
    if (query.length < 2) {
      state = const AsyncValue.data([]);
      return;
    }

    state = await AsyncValue.guard(() async {
      final apiService = ref.read(apiServiceProvider);
      return await apiService.getSearchSuggestions(query);
    });
  }

  void clear() {
    state = const AsyncValue.data([]);
  }
}

// Trending searches state - 根据模式选择数据源
@riverpod
class TrendingSearches extends _$TrendingSearches {
  @override
  Future<List<String>> build() async {
    final modeManager = ref.read(backendModeManagerProvider);
    
    // 独立模式：返回默认热门搜索
    if (modeManager.isStandaloneMode) {
      return _getDefaultTrendingSearches();
    }
    
    // PC模式：从API获取
    try {
      final apiService = ref.read(apiServiceProvider);
      return await apiService.getTrendingSearches();
    } catch (e) {
      // API失败时返回默认值
      return _getDefaultTrendingSearches();
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final modeManager = ref.read(backendModeManagerProvider);
      
      // 独立模式：返回默认热门搜索
      if (modeManager.isStandaloneMode) {
        return _getDefaultTrendingSearches();
      }
      
      // PC模式：从API获取
      final apiService = ref.read(apiServiceProvider);
      return await apiService.getTrendingSearches();
    });
  }
  
  List<String> _getDefaultTrendingSearches() {
    return [
      'Marvel',
      'Star Wars',
      'Netflix',
      'Action',
      'Comedy',
      'Drama',
      'Thriller',
      'Romance',
    ];
  }
}

// Search history state (local)
@riverpod
class SearchHistory extends _$SearchHistory {
  @override
  List<String> build() {
    return [];
  }

  void addSearch(String query) {
    if (query.trim().isEmpty) return;
    
    final currentHistory = state;
    final updatedHistory = [
      query,
      ...currentHistory.where((item) => item != query),
    ].take(10).toList();
    
    state = updatedHistory;
  }

  void removeSearch(String query) {
    state = state.where((item) => item != query).toList();
  }

  void clearHistory() {
    state = [];
  }
}

// Search filters state
@riverpod
class SearchFilters extends _$SearchFilters {
  @override
  SearchFiltersState build() {
    return const SearchFiltersState();
  }

  void updateMediaType(MediaType? mediaType) {
    state = state.copyWith(mediaType: mediaType);
  }

  void updateSource(String source) {
    state = state.copyWith(source: source);
  }

  void updateYearRange(int? yearFrom, int? yearTo) {
    state = state.copyWith(yearFrom: yearFrom, yearTo: yearTo);
  }

  void updateRatingRange(double? ratingMin, double? ratingMax) {
    state = state.copyWith(ratingMin: ratingMin, ratingMax: ratingMax);
  }

  void updateGenre(String? genre) {
    state = state.copyWith(genre: genre);
  }

  void reset() {
    state = const SearchFiltersState();
  }
}

class SearchFiltersState {
  final MediaType? mediaType;
  final String source;
  final int? yearFrom;
  final int? yearTo;
  final double? ratingMin;
  final double? ratingMax;
  final String? genre;

  const SearchFiltersState({
    this.mediaType,
    this.source = 'local',  // 默认只搜索本地
    this.yearFrom,
    this.yearTo,
    this.ratingMin,
    this.ratingMax,
    this.genre,
  });

  SearchFiltersState copyWith({
    MediaType? mediaType,
    String? source,
    int? yearFrom,
    int? yearTo,
    double? ratingMin,
    double? ratingMax,
    String? genre,
  }) {
    return SearchFiltersState(
      mediaType: mediaType ?? this.mediaType,
      source: source ?? this.source,
      yearFrom: yearFrom ?? this.yearFrom,
      yearTo: yearTo ?? this.yearTo,
      ratingMin: ratingMin ?? this.ratingMin,
      ratingMax: ratingMax ?? this.ratingMax,
      genre: genre ?? this.genre,
    );
  }

  bool get hasFilters {
    return mediaType != null ||
        source != 'all' ||
        yearFrom != null ||
        yearTo != null ||
        ratingMin != null ||
        ratingMax != null ||
        genre != null;
  }

  AdvancedSearchRequest toRequest(String query) {
    return AdvancedSearchRequest(
      query: query,
      mediaType: mediaType,
      yearFrom: yearFrom,
      yearTo: yearTo,
      ratingMin: ratingMin,
      ratingMax: ratingMax,
      genre: genre,
      source: source,
    );
  }
}