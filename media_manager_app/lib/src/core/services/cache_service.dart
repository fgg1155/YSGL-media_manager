import 'dart:async';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// LRU Cache implementation for in-memory caching
class LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  LruCache({this.maxSize = 100});

  V? get(K key) {
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value; // Move to end (most recently used)
    }
    return value;
  }

  void put(K key, V value) {
    _cache.remove(key);
    _cache[key] = value;
    
    // Evict oldest entries if over capacity
    while (_cache.length > maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  void remove(K key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
  }

  int get length => _cache.length;
  bool containsKey(K key) => _cache.containsKey(key);
}

/// Cache entry with expiration
class CacheEntry<T> {
  final T data;
  final DateTime createdAt;
  final Duration ttl;

  CacheEntry({
    required this.data,
    required this.ttl,
  }) : createdAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) > ttl;
}

/// Application cache service
class CacheService {
  // Memory caches with different TTLs
  final LruCache<String, CacheEntry<dynamic>> _shortTermCache = LruCache(maxSize: 50);
  final LruCache<String, CacheEntry<dynamic>> _mediumTermCache = LruCache(maxSize: 100);
  final LruCache<String, CacheEntry<dynamic>> _longTermCache = LruCache(maxSize: 200);

  // TTL configurations
  static const shortTtl = Duration(minutes: 5);
  static const mediumTtl = Duration(minutes: 30);
  static const longTtl = Duration(hours: 2);

  // Get from short-term cache (search results, suggestions)
  T? getShortTerm<T>(String key) {
    final entry = _shortTermCache.get(key);
    if (entry != null && !entry.isExpired) {
      return entry.data as T;
    }
    if (entry?.isExpired == true) {
      _shortTermCache.remove(key);
    }
    return null;
  }

  void putShortTerm<T>(String key, T data) {
    _shortTermCache.put(key, CacheEntry(data: data, ttl: shortTtl));
  }

  // Get from medium-term cache (popular content, trending)
  T? getMediumTerm<T>(String key) {
    final entry = _mediumTermCache.get(key);
    if (entry != null && !entry.isExpired) {
      return entry.data as T;
    }
    if (entry?.isExpired == true) {
      _mediumTermCache.remove(key);
    }
    return null;
  }

  void putMediumTerm<T>(String key, T data) {
    _mediumTermCache.put(key, CacheEntry(data: data, ttl: mediumTtl));
  }

  // Get from long-term cache (media details)
  T? getLongTerm<T>(String key) {
    final entry = _longTermCache.get(key);
    if (entry != null && !entry.isExpired) {
      return entry.data as T;
    }
    if (entry?.isExpired == true) {
      _longTermCache.remove(key);
    }
    return null;
  }

  void putLongTerm<T>(String key, T data) {
    _longTermCache.put(key, CacheEntry(data: data, ttl: longTtl));
  }

  // Clear all caches
  void clearAll() {
    _shortTermCache.clear();
    _mediumTermCache.clear();
    _longTermCache.clear();
  }

  // Clear specific cache
  void clearShortTerm() => _shortTermCache.clear();
  void clearMediumTerm() => _mediumTermCache.clear();
  void clearLongTerm() => _longTermCache.clear();

  // Get cache statistics
  MemoryCacheStats getStats() {
    return MemoryCacheStats(
      shortTermSize: _shortTermCache.length,
      mediumTermSize: _mediumTermCache.length,
      longTermSize: _longTermCache.length,
    );
  }
}

class MemoryCacheStats {
  final int shortTermSize;
  final int mediumTermSize;
  final int longTermSize;

  const MemoryCacheStats({
    required this.shortTermSize,
    required this.mediumTermSize,
    required this.longTermSize,
  });

  int get totalSize => shortTermSize + mediumTermSize + longTermSize;
}

/// Debouncer for search input
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 300)});

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
  }
}

/// Throttler for rate limiting
class Throttler {
  final Duration interval;
  DateTime? _lastRun;

  Throttler({this.interval = const Duration(milliseconds: 100)});

  bool shouldRun() {
    final now = DateTime.now();
    if (_lastRun == null || now.difference(_lastRun!) >= interval) {
      _lastRun = now;
      return true;
    }
    return false;
  }

  void run(void Function() action) {
    if (shouldRun()) {
      action();
    }
  }
}

/// Pagination helper
class PaginationController {
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;

  int get currentPage => _currentPage;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  void reset() {
    _currentPage = 1;
    _hasMore = true;
    _isLoading = false;
  }

  void startLoading() {
    _isLoading = true;
  }

  void finishLoading({required bool hasMore}) {
    _isLoading = false;
    _hasMore = hasMore;
    if (hasMore) {
      _currentPage++;
    }
  }

  bool canLoadMore() => hasMore && !isLoading;
}

// Provider
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService();
});

final debouncerProvider = Provider.family<Debouncer, String>((ref, key) {
  return Debouncer();
});
