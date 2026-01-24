import 'package:uuid/uuid.dart';
import '../models/collection.dart';
import '../services/backend_mode.dart';
import '../services/api_service.dart';
import '../database/local_database.dart';
import '../exceptions/collection_exception.dart';

/// 收藏仓库 - 根据模式自动选择数据源
class CollectionRepository {
  final LocalDatabase _localDb;
  final ApiService _apiService;
  final BackendModeManager _modeManager;
  final _uuid = const Uuid();

  CollectionRepository({
    required LocalDatabase localDb,
    required ApiService apiService,
    required BackendModeManager modeManager,
  })  : _localDb = localDb,
        _apiService = apiService,
        _modeManager = modeManager;

  /// 判断是否为独立模式
  bool get _isStandalone {
    final mode = _modeManager.currentMode;
    return mode == BackendMode.standalone;
  }

  // ==================== Collection Operations ====================

  /// 获取收藏列表
  Future<List<Collection>> getCollections() async {
    try {
      if (_isStandalone) {
        return await _localDb.queryCollections();
      } else {
        return await _apiService.getCollections();
      }
    } catch (e) {
      if (_isStandalone) {
        throw CollectionDatabaseException('Failed to get collections', originalError: e);
      } else {
        throw CollectionNetworkException('Failed to get collections from server', originalError: e);
      }
    }
  }

  /// 获取单个收藏
  Future<Collection?> getCollection(String mediaId) async {
    try {
      if (_isStandalone) {
        return await _localDb.getCollection(mediaId);
      } else {
        try {
          final collections = await _apiService.getCollections();
          return collections.firstWhere(
            (c) => c.mediaId == mediaId,
            orElse: () => throw CollectionNotFoundException(mediaId),
          );
        } on CollectionNotFoundException {
          return null;
        }
      }
    } catch (e) {
      if (e is CollectionNotFoundException) {
        return null;
      }
      if (_isStandalone) {
        throw CollectionDatabaseException('Failed to get collection', originalError: e);
      } else {
        throw CollectionNetworkException('Failed to get collection from server', originalError: e);
      }
    }
  }

  /// 添加收藏
  Future<Collection> addCollection(String mediaId, {WatchStatus? watchStatus}) async {
    try {
      if (_isStandalone) {
        // 检查媒体是否存在
        final media = await _localDb.getMedia(mediaId);
        if (media == null) {
          throw MediaNotFoundException(mediaId);
        }
        
        // 检查是否已收藏
        final existing = await _localDb.getCollection(mediaId);
        if (existing != null) {
          throw CollectionAlreadyExistsException(mediaId);
        }
        
        // 创建收藏
        final now = DateTime.now();
        final collection = Collection(
          id: _uuid.v4(),
          mediaId: mediaId,
          watchStatus: watchStatus ?? WatchStatus.wantToWatch,
          isFavorite: false,
          userTags: const [],
          addedAt: now,
        );
        
        await _localDb.insertCollection(collection);
        return collection;
      } else {
        // PC 模式
        return await _apiService.addToCollection(
          AddToCollectionRequest(
            mediaId: mediaId,
            watchStatus: watchStatus,
          ),
        );
      }
    } on CollectionException {
      rethrow;
    } catch (e) {
      if (_isStandalone) {
        // 检查是否是唯一性约束错误
        if (e.toString().contains('UNIQUE constraint failed')) {
          throw CollectionAlreadyExistsException(mediaId);
        }
        throw CollectionDatabaseException('Failed to add collection', originalError: e);
      } else {
        throw CollectionNetworkException('Failed to add collection to server', originalError: e);
      }
    }
  }

  /// 更新收藏
  Future<Collection> updateCollection(String mediaId, UpdateCollectionRequest request) async {
    try {
      // 验证数据
      if (request.personalRating != null) {
        final rating = request.personalRating!;
        if (rating < 0 || rating > 10) {
          throw InvalidRatingException(rating);
        }
      }
      
      if (request.progress != null) {
        final progress = request.progress!;
        if (progress < 0 || progress > 1) {
          throw InvalidProgressException(progress);
        }
      }
      
      if (_isStandalone) {
        // 获取现有收藏
        final existing = await _localDb.getCollection(mediaId);
        if (existing == null) {
          throw CollectionNotFoundException(mediaId);
        }
        
        // 更新收藏
        final updated = existing.copyWith(
          watchStatus: request.watchStatus ?? existing.watchStatus,
          watchProgress: request.progress ?? existing.watchProgress,
          personalRating: request.personalRating ?? existing.personalRating,
          isFavorite: request.isFavorite ?? existing.isFavorite,
          userTags: request.userTags ?? existing.userTags,
          notes: request.notes ?? existing.notes,
          lastWatched: request.watchStatus != null ? DateTime.now() : existing.lastWatched,
          completedAt: request.watchStatus == WatchStatus.completed ? DateTime.now() : existing.completedAt,
        );
        
        await _localDb.updateCollection(updated);
        return updated;
      } else {
        // PC 模式
        return await _apiService.updateCollectionStatus(mediaId, request);
      }
    } on CollectionException {
      rethrow;
    } catch (e) {
      if (_isStandalone) {
        throw CollectionDatabaseException('Failed to update collection', originalError: e);
      } else {
        throw CollectionNetworkException('Failed to update collection on server', originalError: e);
      }
    }
  }

  /// 删除收藏
  Future<void> removeCollection(String mediaId) async {
    try {
      if (_isStandalone) {
        // 检查是否存在
        final existing = await _localDb.getCollection(mediaId);
        if (existing == null) {
          throw CollectionNotFoundException(mediaId);
        }
        
        await _localDb.deleteCollection(mediaId);
      } else {
        // PC 模式
        await _apiService.removeFromCollection(mediaId);
      }
    } on CollectionException {
      rethrow;
    } catch (e) {
      if (_isStandalone) {
        throw CollectionDatabaseException('Failed to remove collection', originalError: e);
      } else {
        throw CollectionNetworkException('Failed to remove collection from server', originalError: e);
      }
    }
  }

  /// 检查是否已收藏
  Future<bool> isInCollection(String mediaId) async {
    try {
      if (_isStandalone) {
        return await _localDb.isInCollection(mediaId);
      } else {
        final collections = await _apiService.getCollections();
        return collections.any((c) => c.mediaId == mediaId);
      }
    } catch (e) {
      // 如果出错，默认返回 false
      return false;
    }
  }

  /// 获取收藏统计
  Future<CollectionStats> getStats() async {
    try {
      final collections = await getCollections();
      return CollectionStats.fromCollections(collections);
    } catch (e) {
      return CollectionStats.empty();
    }
  }
}

/// 收藏统计
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
