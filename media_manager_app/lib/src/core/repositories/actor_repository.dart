import 'package:uuid/uuid.dart';
import '../models/actor.dart';
import '../models/media_item.dart';
import '../services/backend_mode.dart';
import '../services/api_service.dart';
import '../database/local_database.dart';

/// 演员仓库 - 根据模式自动选择数据源
class ActorRepository {
  final LocalDatabase _localDb;
  final ApiService _apiService;
  final BackendModeManager _modeManager;
  final _uuid = const Uuid();

  ActorRepository({
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

  // ==================== Actor Operations ====================

  /// 添加演员
  Future<Actor> addActor(Actor actor) async {
    if (_isStandalone) {
      // 独立模式：保存到本地数据库
      final id = actor.id.isEmpty ? _uuid.v4() : actor.id;
      final now = DateTime.now();
      final actorWithId = Actor(
        id: id,
        name: actor.name,
        avatarUrl: actor.avatarUrl,
        photoUrls: actor.photoUrls,
        posterUrl: actor.posterUrl,
        backdropUrl: actor.backdropUrl,
        biography: actor.biography,
        birthDate: actor.birthDate,
        nationality: actor.nationality,
        createdAt: actor.createdAt.year == 1970 ? now : actor.createdAt,
        updatedAt: now,
      );
      await _localDb.insertActor(actorWithId);
      return actorWithId;
    } else {
      // PC 模式：调用后端 API
      final request = CreateActorRequest(
        name: actor.name,
        avatarUrl: actor.avatarUrl,
        photoUrl: actor.photoUrls?.join(','),  // 将列表转换为逗号分隔的字符串
        posterUrl: actor.posterUrl,
        backdropUrl: actor.backdropUrl,
        biography: actor.biography,
        birthDate: actor.birthDate,
        nationality: actor.nationality,
      );
      return await _apiService.createActor(request);
    }
  }

  /// 获取演员详情
  Future<Actor?> getActor(String id) async {
    if (_isStandalone) {
      return await _localDb.getActor(id);
    } else {
      try {
        final response = await _apiService.getActor(id);
        return response.toActor();
      } catch (e) {
        print('Failed to get actor from PC backend: $e');
        return null;
      }
    }
  }

  /// 搜索演员
  Future<List<Actor>> searchActors(String query) async {
    if (_isStandalone) {
      return await _localDb.queryActors(searchQuery: query);
    } else {
      try {
        return await _apiService.searchActors(query);
      } catch (e) {
        print('Failed to search actors from PC backend: $e');
        return [];
      }
    }
  }

  /// 获取演员列表
  Future<ActorListResult> getActorList({
    String? searchQuery,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (_isStandalone) {
      // 独立模式：从本地数据库查询
      final offset = (page - 1) * pageSize;
      final actors = await _localDb.queryActors(
        searchQuery: searchQuery,
        limit: pageSize,
        offset: offset,
      );
      
      // 简单估算总数（实际应该有专门的 count 方法）
      final total = actors.length < pageSize ? offset + actors.length : (page + 1) * pageSize;
      
      return ActorListResult(
        actors: actors,
        total: total,
        page: page,
        pageSize: pageSize,
      );
    } else {
      // PC 模式：调用后端 API
      try {
        final response = await _apiService.getActors(
          query: searchQuery,
          limit: pageSize,
          offset: (page - 1) * pageSize,
        );
        return ActorListResult(
          actors: response.actors,
          total: response.total,
          page: page,
          pageSize: pageSize,
        );
      } catch (e) {
        print('Failed to get actor list from PC backend: $e');
        return ActorListResult.empty();
      }
    }
  }

  /// 更新演员
  Future<void> updateActor(Actor actor) async {
    if (_isStandalone) {
      final updatedActor = actor.copyWith(
        updatedAt: DateTime.now(),
        isSynced: false,  // 本地修改后标记为未同步
      );
      await _localDb.updateActor(updatedActor);
      print('📝 演员已更新（独立模式）: ${actor.name}');
      print('  - isSynced 设置为 false');
    } else {
      final request = UpdateActorRequest(
        name: actor.name,
        avatarUrl: actor.avatarUrl,
        photoUrl: actor.photoUrls?.join(','),  // 将列表转换为逗号分隔的字符串
        posterUrl: actor.posterUrl,
        backdropUrl: actor.backdropUrl,
        biography: actor.biography,
        birthDate: actor.birthDate,
        nationality: actor.nationality,
      );
      await _apiService.updateActor(actor.id, request);
    }
  }

  /// 删除演员
  Future<void> deleteActor(String id) async {
    print('🗑️ ActorRepository.deleteActor called with id: $id');
    print('   _isStandalone: $_isStandalone');
    print('   currentMode: ${_modeManager.currentMode}');
    
    if (_isStandalone) {
      print('   Using local database');
      await _localDb.deleteActor(id);
    } else {
      print('   Using API service');
      await _apiService.deleteActor(id);
    }
    print('✅ Actor deleted successfully');
  }

  // ==================== Relationship Operations ====================

  /// 关联演员到媒体
  Future<void> linkToMedia(String actorId, String mediaId) async {
    if (_isStandalone) {
      await _localDb.linkMediaActor(mediaId, actorId);
    } else {
      final request = AddActorToMediaRequest(actorId: actorId);
      await _apiService.addActorToMedia(mediaId, request);
    }
  }

  /// 取消演员和媒体的关联
  Future<void> unlinkFromMedia(String actorId, String mediaId) async {
    if (_isStandalone) {
      await _localDb.unlinkMediaActor(mediaId, actorId);
    } else {
      await _apiService.removeActorFromMedia(mediaId, actorId);
    }
  }

  /// 获取演员的所有媒体
  Future<List<MediaItem>> getActorMedia(String actorId) async {
    if (_isStandalone) {
      return await _localDb.getActorMedia(actorId);
    } else {
      try {
        // PC 模式：通过 getActor 获取演员详情，其中包含作品列表
        final response = await _apiService.getActor(actorId);
        // 将 ActorFilmography 转换为 MediaItem
        return response.filmography.map((film) => MediaItem(
          id: film.mediaId,
          title: film.title,
          mediaType: MediaType.movie, // 默认类型
          posterUrl: film.posterUrl,
          releaseDate: film.year != null ? '${film.year}-01-01' : null,
          externalIds: const ExternalIds(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )).toList();
      } catch (e) {
        print('Failed to get actor media from PC backend: $e');
        return [];
      }
    }
  }

  /// 获取媒体的所有演员
  Future<List<Actor>> getMediaActors(String mediaId) async {
    if (_isStandalone) {
      return await _localDb.getMediaActors(mediaId);
    } else {
      try {
        final mediaActors = await _apiService.getActorsForMedia(mediaId);
        // 将 MediaActor 转换为 Actor
        return mediaActors.map((ma) => Actor(
          id: ma.id,
          name: ma.name,
          avatarUrl: ma.avatarUrl,
          photoUrls: ma.photoUrl != null ? [ma.photoUrl!] : null,  // 单个URL转换为列表
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )).toList();
      } catch (e) {
        print('Failed to get media actors from PC backend: $e');
        return [];
      }
    }
  }

  // ==================== Actor Scraping Operations ====================
  // 注意：所有刮削功能已迁移到插件UI系统
  // 通过 Media_Scraper 插件的 UI manifest 调用
}

/// 演员列表结果
class ActorListResult {
  final List<Actor> actors;
  final int total;
  final int page;
  final int pageSize;

  const ActorListResult({
    required this.actors,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory ActorListResult.empty() {
    return const ActorListResult(
      actors: [],
      total: 0,
      page: 1,
      pageSize: 20,
    );
  }
}
