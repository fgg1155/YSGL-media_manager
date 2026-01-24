import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/collection.dart';
import '../../../core/repositories/collection_repository.dart';
import '../../../core/services/api_service.dart';
import '../../../core/providers/app_providers.dart';

part 'collection_providers.g.dart';

// Collection list state - 使用 CollectionRepository
@riverpod
class CollectionList extends _$CollectionList {
  @override
  Future<List<Collection>> build() async {
    final repository = ref.read(collectionRepositoryProvider);
    return await repository.getCollections();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(collectionRepositoryProvider);
      return await repository.getCollections();
    });
  }

  Future<void> addToCollection(String mediaId, {WatchStatus? watchStatus}) async {
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final newCollection = await repository.addCollection(mediaId, watchStatus: watchStatus);
      
      final currentItems = state.value ?? [];
      state = AsyncValue.data([newCollection, ...currentItems]);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> removeFromCollection(String mediaId) async {
    try {
      final repository = ref.read(collectionRepositoryProvider);
      await repository.removeCollection(mediaId);
      
      final currentItems = state.value ?? [];
      final filteredItems = currentItems.where((item) => item.mediaId != mediaId).toList();
      
      state = AsyncValue.data(filteredItems);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateStatus(String mediaId, WatchStatus status, {double? progress}) async {
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final request = UpdateCollectionRequest(watchStatus: status, progress: progress);
      final updated = await repository.updateCollection(mediaId, request);
      
      final currentItems = state.value ?? [];
      final updatedItems = currentItems.map((item) {
        if (item.mediaId == mediaId) {
          return updated;
        }
        return item;
      }).toList();
      
      state = AsyncValue.data(updatedItems);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> toggleFavorite(String mediaId) async {
    final currentItems = state.value ?? [];
    final item = currentItems.firstWhere((c) => c.mediaId == mediaId);
    final newFavorite = !item.isFavorite;
    
    // Optimistic update
    final updatedItems = currentItems.map((c) {
      if (c.mediaId == mediaId) {
        return c.copyWith(isFavorite: newFavorite);
      }
      return c;
    }).toList();
    state = AsyncValue.data(updatedItems);
    
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final request = UpdateCollectionRequest(isFavorite: newFavorite);
      await repository.updateCollection(mediaId, request);
    } catch (error, stackTrace) {
      // Rollback on error
      state = AsyncValue.data(currentItems);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateRating(String mediaId, double rating) async {
    final currentItems = state.value ?? [];
    
    // Optimistic update
    final updatedItems = currentItems.map((c) {
      if (c.mediaId == mediaId) {
        return c.copyWith(personalRating: rating);
      }
      return c;
    }).toList();
    state = AsyncValue.data(updatedItems);
    
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final request = UpdateCollectionRequest(personalRating: rating);
      await repository.updateCollection(mediaId, request);
    } catch (error, stackTrace) {
      // Rollback on error
      state = AsyncValue.data(currentItems);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> addTag(String mediaId, String tag) async {
    final currentItems = state.value ?? [];
    final item = currentItems.firstWhere((c) => c.mediaId == mediaId);
    final newTags = [...item.userTags, tag];
    
    // Optimistic update
    final updatedItems = currentItems.map((c) {
      if (c.mediaId == mediaId) {
        return c.copyWith(userTags: newTags);
      }
      return c;
    }).toList();
    state = AsyncValue.data(updatedItems);
    
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final request = UpdateCollectionRequest(userTags: newTags);
      await repository.updateCollection(mediaId, request);
    } catch (error, stackTrace) {
      // Rollback on error
      state = AsyncValue.data(currentItems);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> removeTag(String mediaId, String tag) async {
    final currentItems = state.value ?? [];
    final item = currentItems.firstWhere((c) => c.mediaId == mediaId);
    final newTags = item.userTags.where((t) => t != tag).toList();
    
    // Optimistic update
    final updatedItems = currentItems.map((c) {
      if (c.mediaId == mediaId) {
        return c.copyWith(userTags: newTags);
      }
      return c;
    }).toList();
    state = AsyncValue.data(updatedItems);
    
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final request = UpdateCollectionRequest(userTags: newTags);
      await repository.updateCollection(mediaId, request);
    } catch (error, stackTrace) {
      // Rollback on error
      state = AsyncValue.data(currentItems);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateNotes(String mediaId, String notes) async {
    final currentItems = state.value ?? [];
    
    // Optimistic update
    final updatedItems = currentItems.map((c) {
      if (c.mediaId == mediaId) {
        return c.copyWith(notes: notes);
      }
      return c;
    }).toList();
    state = AsyncValue.data(updatedItems);
    
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final request = UpdateCollectionRequest(notes: notes);
      await repository.updateCollection(mediaId, request);
    } catch (error, stackTrace) {
      // Rollback on error
      state = AsyncValue.data(currentItems);
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

// Collection filter state
@riverpod
class CollectionFilter extends _$CollectionFilter {
  @override
  CollectionFilterState build() {
    return const CollectionFilterState();
  }

  void updateWatchStatus(WatchStatus? status) {
    state = state.copyWith(watchStatus: status);
  }

  void updateFavoriteOnly(bool favoriteOnly) {
    state = state.copyWith(favoriteOnly: favoriteOnly);
  }

  void updateSortBy(CollectionSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void reset() {
    state = const CollectionFilterState();
  }
}

class CollectionFilterState {
  final WatchStatus? watchStatus;
  final bool favoriteOnly;
  final CollectionSortBy sortBy;

  const CollectionFilterState({
    this.watchStatus,
    this.favoriteOnly = false,
    this.sortBy = CollectionSortBy.addedAt,
  });

  CollectionFilterState copyWith({
    WatchStatus? watchStatus,
    bool? favoriteOnly,
    CollectionSortBy? sortBy,
  }) {
    return CollectionFilterState(
      watchStatus: watchStatus ?? this.watchStatus,
      favoriteOnly: favoriteOnly ?? this.favoriteOnly,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  bool get hasFilters {
    return watchStatus != null || favoriteOnly;
  }
}

enum CollectionSortBy {
  addedAt,
  lastWatched,
  rating,
  title,
}

// Filtered collection provider
@riverpod
List<Collection> filteredCollections(FilteredCollectionsRef ref) {
  final collectionsAsync = ref.watch(collectionListProvider);
  final filter = ref.watch(collectionFilterProvider);
  
  return collectionsAsync.when(
    data: (collections) {
      var filtered = collections;
      
      // Apply watch status filter
      if (filter.watchStatus != null) {
        filtered = filtered.where((c) => c.watchStatus == filter.watchStatus).toList();
      }
      
      // Apply favorite filter
      if (filter.favoriteOnly) {
        filtered = filtered.where((c) => c.isFavorite).toList();
      }
      
      // Apply sorting
      switch (filter.sortBy) {
        case CollectionSortBy.addedAt:
          filtered.sort((a, b) => b.addedAt.compareTo(a.addedAt));
          break;
        case CollectionSortBy.lastWatched:
          filtered.sort((a, b) {
            if (a.lastWatched == null && b.lastWatched == null) return 0;
            if (a.lastWatched == null) return 1;
            if (b.lastWatched == null) return -1;
            return b.lastWatched!.compareTo(a.lastWatched!);
          });
          break;
        case CollectionSortBy.rating:
          filtered.sort((a, b) {
            if (a.personalRating == null && b.personalRating == null) return 0;
            if (a.personalRating == null) return 1;
            if (b.personalRating == null) return -1;
            return b.personalRating!.compareTo(a.personalRating!);
          });
          break;
        case CollectionSortBy.title:
          // Note: Would need media title for proper sorting
          break;
      }
      
      return filtered;
    },
    loading: () => [],
    error: (_, __) => [],
  );
}

// Check if media is in collection
@riverpod
bool isInCollection(IsInCollectionRef ref, String mediaId) {
  final collectionsAsync = ref.watch(collectionListProvider);
  
  return collectionsAsync.when(
    data: (collections) => collections.any((c) => c.mediaId == mediaId),
    loading: () => false,
    error: (_, __) => false,
  );
}

// Get collection for specific media
@riverpod
Collection? getCollectionForMedia(GetCollectionForMediaRef ref, String mediaId) {
  final collectionsAsync = ref.watch(collectionListProvider);
  
  return collectionsAsync.when(
    data: (collections) {
      try {
        return collections.firstWhere((c) => c.mediaId == mediaId);
      } catch (_) {
        return null;
      }
    },
    loading: () => null,
    error: (_, __) => null,
  );
}

// Get all unique tags from collections
@riverpod
List<String> allTags(AllTagsRef ref) {
  final collectionsAsync = ref.watch(collectionListProvider);
  
  return collectionsAsync.when(
    data: (collections) {
      final tags = <String>{};
      for (final collection in collections) {
        tags.addAll(collection.userTags);
      }
      return tags.toList()..sort();
    },
    loading: () => [],
    error: (_, __) => [],
  );
}

// Get collections by tag
@riverpod
List<Collection> collectionsByTag(CollectionsByTagRef ref, String tag) {
  final collectionsAsync = ref.watch(collectionListProvider);
  
  return collectionsAsync.when(
    data: (collections) {
      return collections.where((c) => c.userTags.contains(tag)).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
}

// Collection statistics
@riverpod
CollectionStats collectionStats(CollectionStatsRef ref) {
  final collectionsAsync = ref.watch(collectionListProvider);
  
  return collectionsAsync.when(
    data: (collections) => CollectionStats.fromCollections(collections),
    loading: () => CollectionStats.empty(),
    error: (_, __) => CollectionStats.empty(),
  );
}

class CollectionStats {
  final int total;
  final int watching;
  final int completed;
  final int wantToWatch;
  final int onHold;
  final int dropped;
  final int favorites;
  final double averageRating;

  const CollectionStats({
    required this.total,
    required this.watching,
    required this.completed,
    required this.wantToWatch,
    required this.onHold,
    required this.dropped,
    required this.favorites,
    required this.averageRating,
  });

  factory CollectionStats.empty() => const CollectionStats(
    total: 0,
    watching: 0,
    completed: 0,
    wantToWatch: 0,
    onHold: 0,
    dropped: 0,
    favorites: 0,
    averageRating: 0,
  );

  factory CollectionStats.fromCollections(List<Collection> collections) {
    if (collections.isEmpty) return CollectionStats.empty();

    final ratings = collections
        .where((c) => c.personalRating != null)
        .map((c) => c.personalRating!)
        .toList();
    
    final avgRating = ratings.isEmpty 
        ? 0.0 
        : ratings.reduce((a, b) => a + b) / ratings.length;

    return CollectionStats(
      total: collections.length,
      watching: collections.where((c) => c.watchStatus == WatchStatus.watching).length,
      completed: collections.where((c) => c.watchStatus == WatchStatus.completed).length,
      wantToWatch: collections.where((c) => c.watchStatus == WatchStatus.wantToWatch).length,
      onHold: collections.where((c) => c.watchStatus == WatchStatus.onHold).length,
      dropped: collections.where((c) => c.watchStatus == WatchStatus.dropped).length,
      favorites: collections.where((c) => c.isFavorite).length,
      averageRating: avgRating,
    );
  }
}