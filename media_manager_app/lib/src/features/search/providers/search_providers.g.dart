// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$searchResultsHash() => r'e1f9496eb9f505d31f3e5cf50e8e48e63420583c';

/// See also [SearchResults].
@ProviderFor(SearchResults)
final searchResultsProvider =
    AutoDisposeAsyncNotifierProvider<SearchResults, List<MediaItem>?>.internal(
  SearchResults.new,
  name: r'searchResultsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$searchResultsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchResults = AutoDisposeAsyncNotifier<List<MediaItem>?>;
String _$searchSuggestionsHash() => r'4cccef778d14562d2696758b8bb7b81e19d67225';

/// See also [SearchSuggestions].
@ProviderFor(SearchSuggestions)
final searchSuggestionsProvider = AutoDisposeAsyncNotifierProvider<
    SearchSuggestions, List<SearchSuggestion>>.internal(
  SearchSuggestions.new,
  name: r'searchSuggestionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$searchSuggestionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchSuggestions = AutoDisposeAsyncNotifier<List<SearchSuggestion>>;
String _$trendingSearchesHash() => r'8aaccbcae1717336aa9156ad423655a423bdc1a9';

/// See also [TrendingSearches].
@ProviderFor(TrendingSearches)
final trendingSearchesProvider =
    AutoDisposeAsyncNotifierProvider<TrendingSearches, List<String>>.internal(
  TrendingSearches.new,
  name: r'trendingSearchesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trendingSearchesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TrendingSearches = AutoDisposeAsyncNotifier<List<String>>;
String _$searchHistoryHash() => r'8dd0ed138273b8380f367bde7d06606de5882c07';

/// See also [SearchHistory].
@ProviderFor(SearchHistory)
final searchHistoryProvider =
    AutoDisposeNotifierProvider<SearchHistory, List<String>>.internal(
  SearchHistory.new,
  name: r'searchHistoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$searchHistoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchHistory = AutoDisposeNotifier<List<String>>;
String _$searchFiltersHash() => r'ce58d8ce6d3e7673e8d34abb86d2436aceb85c4c';

/// See also [SearchFilters].
@ProviderFor(SearchFilters)
final searchFiltersProvider =
    AutoDisposeNotifierProvider<SearchFilters, SearchFiltersState>.internal(
  SearchFilters.new,
  name: r'searchFiltersProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$searchFiltersHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchFilters = AutoDisposeNotifier<SearchFiltersState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
