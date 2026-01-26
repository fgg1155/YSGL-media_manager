import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/actor.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/api_service.dart';
import '../../../core/providers/app_providers.dart';

part 'actor_providers.g.dart';

/// 演员列表状态
@riverpod
class ActorList extends _$ActorList {
  int _currentOffset = 0;
  static const int _pageSize = 20;
  String? _currentQuery;

  @override
  Future<List<Actor>> build() async {
    _currentOffset = 0;
    _currentQuery = null;
    final repository = ref.read(actorRepositoryProvider);
    final response = await repository.getActorList(page: 1, pageSize: _pageSize);
    return response.actors;
  }

  Future<void> refresh() async {
    _currentOffset = 0;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(actorRepositoryProvider);
      final response = await repository.getActorList(
        searchQuery: _currentQuery,
        page: 1,
        pageSize: _pageSize,
      );
      return response.actors;
    });
  }

  Future<void> search(String? query) async {
    _currentQuery = query;
    _currentOffset = 0;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(actorRepositoryProvider);
      final response = await repository.getActorList(
        searchQuery: query,
        page: 1,
        pageSize: _pageSize,
      );
      return response.actors;
    });
  }

  Future<void> loadMore() async {
    if (state.isLoading) return;

    final currentItems = state.value ?? [];
    final currentPage = (currentItems.length / _pageSize).ceil() + 1;

    try {
      final repository = ref.read(actorRepositoryProvider);
      final response = await repository.getActorList(
        searchQuery: _currentQuery,
        page: currentPage,
        pageSize: _pageSize,
      );

      if (response.actors.isNotEmpty) {
        state = AsyncValue.data([...currentItems, ...response.actors]);
      }
    } catch (error, stackTrace) {
      // 保持当前数据，只记录错误
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> deleteActor(String id) async {
    try {
      final repository = ref.read(actorRepositoryProvider);
      await repository.deleteActor(id);

      // 刷新列表以加载新数据（填补删除后的空缺）
      await refresh();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

/// 演员详情状态
@riverpod
class ActorDetail extends _$ActorDetail {
  @override
  Future<Actor?> build(String actorId) async {
    if (actorId.isEmpty) return null;

    final repository = ref.read(actorRepositoryProvider);
    return await repository.getActor(actorId);
  }

  Future<void> refresh() async {
    final actorId = state.value?.id;
    if (actorId == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(actorRepositoryProvider);
      return await repository.getActor(actorId);
    });
  }
}

/// 演员的媒体作品列表
@riverpod
Future<List<MediaItem>> actorMediaList(ActorMediaListRef ref, String actorId) async {
  if (actorId.isEmpty) return [];
  
  final repository = ref.read(actorRepositoryProvider);
  return await repository.getActorMedia(actorId);
}

/// 媒体的演员列表
@riverpod
Future<List<Actor>> mediaActorList(MediaActorListRef ref, String mediaId) async {
  if (mediaId.isEmpty) return [];
  
  final repository = ref.read(actorRepositoryProvider);
  return await repository.getMediaActors(mediaId);
}

/// 创建/更新演员
@riverpod
class ActorMutation extends _$ActorMutation {
  @override
  AsyncValue<Actor?> build() {
    return const AsyncValue.data(null);
  }

  Future<Actor?> createActor(Actor actor) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(actorRepositoryProvider);
      final newActor = await repository.addActor(actor);
      state = AsyncValue.data(newActor);
      // 刷新列表
      ref.invalidate(actorListProvider);
      return newActor;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }

  Future<Actor?> updateActor(Actor actor) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(actorRepositoryProvider);
      await repository.updateActor(actor);
      state = AsyncValue.data(actor);
      // 刷新列表和详情
      ref.invalidate(actorListProvider);
      ref.invalidate(actorDetailProvider(actor.id));
      return actor;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }
}
