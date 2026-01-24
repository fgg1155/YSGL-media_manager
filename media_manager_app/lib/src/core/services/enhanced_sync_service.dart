import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/media_item.dart';
import '../models/actor.dart';
import '../models/sync_models.dart';
import '../database/local_database.dart';
import '../providers/app_providers.dart';
import 'api_service.dart';
import 'sync_queue.dart';
import 'backend_mode.dart';

/// Enhanced sync service with full Media and Actor synchronization
class EnhancedSyncService extends StateNotifier<SyncState> {
  final LocalDatabase _localDb;
  final ApiService _apiService;
  final SyncQueue _syncQueue;
  final BackendModeManager _modeManager;
  final Connectivity _connectivity;
  
  Timer? _autoSyncTimer;
  StreamSubscription? _connectivitySubscription;
  
  static const _autoSyncInterval = Duration(minutes: 15);

  EnhancedSyncService({
    required LocalDatabase localDb,
    required ApiService apiService,
    required SyncQueue syncQueue,
    required BackendModeManager modeManager,
    Connectivity? connectivity,
  })  : _localDb = localDb,
        _apiService = apiService,
        _syncQueue = syncQueue,
        _modeManager = modeManager,
        _connectivity = connectivity ?? Connectivity(),
        super(const SyncState()) {
    _initialize();
  }

  /// Initialize sync service
  Future<void> _initialize() async {
    // Web 平台不需要同步功能
    if (kIsWeb) {
      state = state.copyWith(
        status: SyncStatus.idle,
        hasPendingChanges: false,
      );
      return;
    }
    
    // Load pending changes count
    final pendingCount = await _syncQueue.count();
    state = state.copyWith(
      hasPendingChanges: pendingCount > 0,
    );
    
    // Start auto-sync timer
    _startAutoSync();
    
    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      _onConnectivityChanged(result);
    });
  }

  /// Start auto-sync timer
  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) async {
      // 检查是否有来自 PC 的同步请求
      try {
        final syncRequest = await _apiService.checkSyncRequest();
        if (syncRequest['requested'] == true) {
          print('📱 收到 PC 端的同步请求，开始同步...');
          await syncAll();
          // 通知后端同步完成
          await _apiService.completeSync('mobile-device');
        }
      } catch (e) {
        // 忽略检查错误（可能是网络问题）
      }
      
      // 原有的自动同步逻辑
      if (state.hasPendingChanges && !state.isSyncing) {
        syncAll();
      }
    });
  }

  /// Handle connectivity changes
  Future<void> _onConnectivityChanged(ConnectivityResult result) async {
    if (result != ConnectivityResult.none) {
      // Network restored, trigger sync if there are pending changes
      if (state.hasPendingChanges && !state.isSyncing) {
        await Future.delayed(const Duration(seconds: 2)); // Wait a bit for connection to stabilize
        syncAll();
      }
    }
  }

  /// Sync all data (push + pull)
  Future<SyncResult> syncAll() async {
    // Web 平台：触发移动端同步
    if (kIsWeb) {
      try {
        // 调用后端 API 触发同步请求
        await _apiService.triggerSync();
        
        state = state.copyWith(
          status: SyncStatus.success,
          lastSyncTime: DateTime.now(),
        );
        
        return SyncResult(
          success: true,
          itemsPushed: 0,
          itemsPulled: 0,
          conflicts: 0,
          errors: const [],
          syncTime: DateTime.now(),
        );
      } catch (e) {
        state = state.copyWith(
          status: SyncStatus.error,
          errorMessage: '触发同步失败: $e',
        );
        return SyncResult.error('触发同步失败: $e');
      }
    }
    
    if (state.isSyncing) {
      return SyncResult.error('Sync already in progress');
    }

    // 移动端：检查是否有同步请求
    try {
      final syncRequest = await _apiService.checkSyncRequest();
      if (syncRequest['requested'] == true) {
        print('📱 收到同步请求，开始同步...');
      }
    } catch (e) {
      print('检查同步请求失败: $e');
    }

    // Check if we're in standalone mode
    final mode = _modeManager.currentMode;
    if (mode == BackendMode.standalone) {
      return SyncResult.error('Cannot sync in standalone mode');
    }

    // Check network connectivity
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      state = state.copyWith(status: SyncStatus.offline);
      return SyncResult.error('No network connection');
    }

    state = state.copyWith(
      status: SyncStatus.syncing,
      errorMessage: null,
    );

    try {
      // First, push local changes
      final pushResult = await pushToPC();
      
      // Then, pull remote changes
      final pullResult = await pullFromPC();
      
      // Combine results
      final combinedResult = SyncResult(
        success: pushResult.success && pullResult.success,
        itemsPushed: pushResult.itemsPushed,
        itemsPulled: pullResult.itemsPulled,
        conflicts: pushResult.conflicts + pullResult.conflicts,
        errors: [...pushResult.errors, ...pullResult.errors],
        syncTime: DateTime.now(),
      );

      state = state.copyWith(
        status: combinedResult.success ? SyncStatus.success : SyncStatus.error,
        lastSyncTime: combinedResult.syncTime,
        errorMessage: combinedResult.errors.isNotEmpty ? combinedResult.errors.first : null,
        hasPendingChanges: false,
      );

      print('📊 同步状态更新:');
      print('  - 状态: ${state.status}');
      print('  - 上次同步时间: ${state.lastSyncTime}');
      print('  - 待同步更改: ${state.hasPendingChanges}');

      // 移动端：通知后端同步完成
      if (!kIsWeb) {
        try {
          await _apiService.completeSync('mobile-device');
          print('✓ 已通知后端同步完成');
        } catch (e) {
          print('通知后端同步完成失败: $e');
        }
      }

      return combinedResult;
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
      return SyncResult.error(e.toString());
    }
  }

  /// Push local changes to PC backend
  Future<SyncResult> pushToPC() async {
    var itemsPushed = 0;
    var conflicts = 0;
    final errors = <String>[];

    try {
      // Get unsynced media
      final unsyncedMedia = await _localDb.getUnsyncedMedia();
      print('📤 开始推送本地更改到 PC...');
      print('  - 找到 ${unsyncedMedia.length} 个未同步的媒体');
      
      for (final media in unsyncedMedia) {
        try {
          print('  处理媒体: ${media.title} (${media.id})');
          
          // Check if media exists on PC
          try {
            final remoteMedia = await _apiService.getMediaDetail(media.id);
            
            // Media exists, check timestamps
            if (media.updatedAt.isAfter(remoteMedia.updatedAt)) {
              // Local is newer, update PC
              print('    → 本地更新，推送到 PC');
              await _updateMediaOnPC(media);
              itemsPushed++;
            } else if (media.updatedAt.isBefore(remoteMedia.updatedAt)) {
              // Remote is newer, will be handled by pull
              print('    → PC 端更新，跳过（将在拉取时处理）');
              print('    ⚠️  检测到冲突：本地 ${media.updatedAt} vs 远程 ${remoteMedia.updatedAt}');
              conflicts++;
            } else {
              // Timestamps are equal
              print('    → 时间戳相同，标记为已同步');
              print('    ⚠️  检测到时间戳相同的冲突');
              conflicts++;
            }
          } catch (e) {
            // Media doesn't exist on PC (404 error), create it
            print('    → PC 端不存在，创建新媒体');
            await _createMediaOnPC(media);
            itemsPushed++;
          }
          
          // Mark as synced
          await _localDb.markMediaSynced(media.id, DateTime.now());
          print('    ✓ 已标记为同步');
        } catch (e) {
          final errorMsg = 'Failed to sync media ${media.id}: $e';
          print('    ✗ $errorMsg');
          errors.add(errorMsg);
        }
      }

      // Get unsynced actors
      final unsyncedActors = await _localDb.getUnsyncedActors();
      print('  - 找到 ${unsyncedActors.length} 个未同步的演员');
      
      for (final actor in unsyncedActors) {
        try {
          print('  处理演员: ${actor.name} (${actor.id})');
          
          // Check if actor exists on PC
          try {
            final remoteActor = await _apiService.getActor(actor.id);
            
            // Actor exists, check timestamps
            final remoteActorObj = remoteActor.toActor();
            if (actor.updatedAt.isAfter(remoteActorObj.updatedAt)) {
              // Local is newer, update PC
              print('    → 本地更新，推送到 PC');
              await _updateActorOnPC(actor);
              itemsPushed++;
            } else if (actor.updatedAt.isBefore(remoteActorObj.updatedAt)) {
              // Remote is newer, will be handled by pull
              print('    → PC 端更新，跳过（将在拉取时处理）');
              print('    ⚠️  检测到冲突：本地 ${actor.updatedAt} vs 远程 ${remoteActorObj.updatedAt}');
              conflicts++;
            } else {
              // Timestamps are equal
              print('    → 时间戳相同，标记为已同步');
              print('    ⚠️  检测到时间戳相同的冲突');
              conflicts++;
            }
          } catch (e) {
            // Actor doesn't exist on PC (404 error), create it
            print('    → PC 端不存在，创建新演员');
            await _createActorOnPC(actor);
            itemsPushed++;
          }
          
          // Mark as synced
          await _localDb.markActorSynced(actor.id, DateTime.now());
          print('    ✓ 已标记为同步');
        } catch (e) {
          final errorMsg = 'Failed to sync actor ${actor.id}: $e';
          print('    ✗ $errorMsg');
          errors.add(errorMsg);
        }
      }

      print('📤 推送完成: 成功 $itemsPushed 个，冲突 $conflicts 个，错误 ${errors.length} 个');
      
      return SyncResult(
        success: errors.isEmpty,
        itemsPushed: itemsPushed,
        itemsPulled: 0,
        conflicts: conflicts,
        errors: errors,
        syncTime: DateTime.now(),
      );
    } catch (e) {
      print('✗ 推送同步失败: $e');
      return SyncResult.error('Push sync failed: $e');
    }
  }

  /// Pull remote changes from PC backend
  /// Pull remote changes from PC backend
  Future<SyncResult> pullFromPC() async {
    var itemsPulled = 0;
    final errors = <String>[];

    try {
      print('📥 开始从 PC 拉取数据...');
      
      // Get last sync time
      final lastSync = state.lastSyncTime ?? DateTime(2000);
      print('  - 上次同步时间: $lastSync');
      
      // Fetch media modified since last sync
      final mediaResponse = await _apiService.getMediaList(
        page: 1,
        limit: 1000, // Fetch a large batch
      );
      
      print('  - 从 PC 获取到 ${mediaResponse.items.length} 个媒体');
      
      for (final remoteMedia in mediaResponse.items) {
        if (remoteMedia.updatedAt.isAfter(lastSync)) {
          try {
            print('  处理媒体: ${remoteMedia.title} (${remoteMedia.id})');
            
            // 检查本地是否已存在相同 ID 的媒体
            final localMedia = await _localDb.getMedia(remoteMedia.id);
            
            if (localMedia == null) {
              // Media doesn't exist locally, insert it
              print('    → 本地不存在，插入新媒体');
              await _localDb.insertMedia(remoteMedia.copyWith(isSynced: true));
              itemsPulled++;
            } else {
              // Media exists, check timestamps
              print('    → 本地已存在，比较时间戳');
              print('      本地: ${localMedia.updatedAt}');
              print('      远程: ${remoteMedia.updatedAt}');
              
              if (remoteMedia.updatedAt.isAfter(localMedia.updatedAt)) {
                // Remote is newer, update local
                print('    → 远程更新，更新本地数据');
                await _localDb.updateMedia(remoteMedia.copyWith(isSynced: true));
                itemsPulled++;
              } else {
                print('    → 本地更新或相同，跳过');
              }
            }
          } catch (e) {
            final errorMsg = 'Failed to pull media ${remoteMedia.id}: $e';
            print('    ✗ $errorMsg');
            errors.add(errorMsg);
          }
        }
      }

      // Fetch actors (similar logic)
      final actorsResponse = await _apiService.getActors(limit: 1000);
      print('  - 从 PC 获取到 ${actorsResponse.actors.length} 个演员');
      
      for (final remoteActor in actorsResponse.actors) {
        if (remoteActor.updatedAt.isAfter(lastSync)) {
          try {
            print('  处理演员: ${remoteActor.name} (${remoteActor.id})');
            
            // 检查本地是否已存在相同 ID 的演员
            final localActor = await _localDb.getActor(remoteActor.id);
            
            if (localActor == null) {
              // Actor doesn't exist locally, insert it
              print('    → 本地不存在，插入新演员');
              await _localDb.insertActor(remoteActor.copyWith(isSynced: true));
              itemsPulled++;
            } else {
              // Actor exists, check timestamps
              print('    → 本地已存在，比较时间戳');
              print('      本地: ${localActor.updatedAt}');
              print('      远程: ${remoteActor.updatedAt}');
              
              if (remoteActor.updatedAt.isAfter(localActor.updatedAt)) {
                // Remote is newer, update local
                print('    → 远程更新，更新本地数据');
                await _localDb.updateActor(remoteActor.copyWith(isSynced: true));
                itemsPulled++;
              } else {
                print('    → 本地更新或相同，跳过');
              }
            }
          } catch (e) {
            final errorMsg = 'Failed to pull actor ${remoteActor.id}: $e';
            print('    ✗ $errorMsg');
            errors.add(errorMsg);
          }
        }
      }

      print('📥 拉取完成: 成功 $itemsPulled 个，错误 ${errors.length} 个');

      return SyncResult(
        success: errors.isEmpty,
        itemsPushed: 0,
        itemsPulled: itemsPulled,
        conflicts: 0,
        errors: errors,
        syncTime: DateTime.now(),
      );
    } catch (e) {
      return SyncResult.error('Pull sync failed: $e');
    }
  }

  /// Create media on PC backend
  Future<void> _createMediaOnPC(MediaItem media) async {
    try {
      print('🔍 准备创建媒体到 PC:');
      print('  - 标题: ${media.title}');
      print('  - ID: ${media.id}');
      print('  - ID 类型: ${media.id.runtimeType}');
      print('  - ID 长度: ${media.id.length}');
      
      final request = CreateMediaRequest(
        id: media.id,  // ← 包含客户端 ID
        title: media.title,
        originalTitle: media.originalTitle,
        code: media.code,
        mediaType: media.mediaType,  // MediaType 是必需的，不会为 null
        year: media.year,
        releaseDate: media.releaseDate,
        overview: media.overview,
        genres: media.genres,
        rating: media.rating,
        runtime: media.runtime,
        posterUrl: media.posterUrl,
        backdropUrl: media.backdropUrl,
        studio: media.studio,
        series: media.series,
        playLinks: media.playLinks,
        downloadLinks: media.downloadLinks,
      );
      final response = await _apiService.createMedia(request);
      
      // 验证 PC 后端返回的 ID 与本地 ID 一致
      if (response.id != media.id) {
        throw Exception(
          'ID mismatch: expected ${media.id}, got ${response.id}'
        );
      }
      
      print('✓ 成功创建媒体到 PC: ${media.title} (${media.id})');
    } catch (e) {
      print('✗ 创建媒体到 PC 失败: ${media.title} (${media.id})');
      print('  错误详情: $e');
      rethrow;
    }
  }

  /// Update media on PC backend
  Future<void> _updateMediaOnPC(MediaItem media) async {
    try {
      final request = UpdateMediaRequest(
        title: media.title,
        originalTitle: media.originalTitle,
        code: media.code,
        mediaType: media.mediaType.name,
        year: media.year,
        releaseDate: media.releaseDate,
        overview: media.overview,
        genres: media.genres,
        rating: media.rating,
        runtime: media.runtime,
        posterUrl: media.posterUrl,
        backdropUrl: media.backdropUrl,
        studio: media.studio,
        series: media.series,
        playLinks: media.playLinks,
        downloadLinks: media.downloadLinks,
      );
      await _apiService.updateMedia(media.id, request);
      print('✓ 成功更新媒体到 PC: ${media.title} (${media.id})');
    } catch (e) {
      print('✗ 更新媒体到 PC 失败: ${media.title} (${media.id})');
      print('  错误详情: $e');
      rethrow;
    }
  }

  /// Create actor on PC backend
  Future<void> _createActorOnPC(Actor actor) async {
    try {
      final request = CreateActorRequest(
        id: actor.id,  // ← 包含客户端 ID
        name: actor.name,
        photoUrl: actor.photoUrls?.join(','),  // 将列表转换为逗号分隔的字符串
        backdropUrl: actor.backdropUrl,
        biography: actor.biography,
        birthDate: actor.birthDate,
        nationality: actor.nationality,
      );
      final response = await _apiService.createActor(request);
      
      // 验证 PC 后端返回的 ID 与本地 ID 一致
      if (response.id != actor.id) {
        throw Exception(
          'ID mismatch: expected ${actor.id}, got ${response.id}'
        );
      }
      
      print('✓ 成功创建演员到 PC: ${actor.name} (${actor.id})');
    } catch (e) {
      print('✗ 创建演员到 PC 失败: ${actor.name} (${actor.id})');
      print('  错误详情: $e');
      rethrow;
    }
  }

  /// Update actor on PC backend
  Future<void> _updateActorOnPC(Actor actor) async {
    final request = UpdateActorRequest(
      name: actor.name,
      photoUrl: actor.photoUrls?.join(','),  // 将列表转换为逗号分隔的字符串
      backdropUrl: actor.backdropUrl,
      biography: actor.biography,
      birthDate: actor.birthDate,
      nationality: actor.nationality,
    );
    await _apiService.updateActor(actor.id, request);
  }

  /// Get last sync time
  DateTime? getLastSyncTime() => state.lastSyncTime;

  /// Check if there are pending changes
  Future<bool> hasPendingChanges() async {
    final count = await _syncQueue.count();
    return count > 0;
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

/// Sync state
class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncTime;
  final bool hasPendingChanges;
  final String? errorMessage;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncTime,
    this.hasPendingChanges = false,
    this.errorMessage,
  });

  bool get isSyncing => status == SyncStatus.syncing;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncTime,
    bool? hasPendingChanges,
    String? errorMessage,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      hasPendingChanges: hasPendingChanges ?? this.hasPendingChanges,
      errorMessage: errorMessage,
    );
  }
}

/// Provider for enhanced sync service
final enhancedSyncServiceProvider = StateNotifierProvider<EnhancedSyncService, SyncState>((ref) {
  final modeManager = ref.watch(backendModeManagerProvider);
  
  // Web 平台使用 PC 模式，不需要本地数据库和同步
  // 创建一个禁用的同步服务
  final localDb = LocalDatabase();
  final apiService = ref.watch(apiServiceProvider);
  final syncQueue = SyncQueue(localDb: localDb);
  
  return EnhancedSyncService(
    localDb: localDb,
    apiService: apiService,
    syncQueue: syncQueue,
    modeManager: modeManager,
  );
});
