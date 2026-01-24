import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/backend_mode.dart';
import '../services/local_http_server.dart';
import '../services/app_initializer.dart';
import '../services/api_service.dart';
import '../services/local_file_scanner.dart';
import '../services/local_file_grouper.dart';
import '../services/local_file_matcher.dart';
import '../services/video_thumbnail_service.dart';
import '../services/video_streaming_service.dart';
import '../database/local_database.dart';
import '../repositories/media_repository.dart';
import '../repositories/actor_repository.dart';
import '../repositories/collection_repository.dart';
import '../config/app_config.dart';
import '../models/media_item.dart';
import '../models/actor.dart';

/// 后端模式管理器
final backendModeManagerProvider = Provider<BackendModeManager>((ref) {
  final manager = BackendModeManager();
  // 设置回调函数，从 apiBaseUrlProvider 获取 URL
  manager.setBackendUrlProvider(() => ref.read(apiBaseUrlProvider));
  return manager;
});

/// 本地数据库
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  return LocalDatabase();
});

/// 本地文件扫描器（独立模式）
final localFileScannerProvider = Provider<LocalFileScanner>((ref) {
  return LocalFileScanner();
});

/// 本地文件分组器（独立模式）
final localFileGrouperProvider = Provider<LocalFileGrouper>((ref) {
  return LocalFileGrouper();
});

/// 本地文件匹配器（独立模式）
final localFileMatcherProvider = Provider<LocalFileMatcher>((ref) {
  return LocalFileMatcher();
});

/// 视频缩略图服务
final videoThumbnailServiceProvider = Provider<VideoThumbnailService>((ref) {
  return VideoThumbnailService();
});

/// 视频流服务
final videoStreamingServiceProvider = Provider<VideoStreamingService>((ref) {
  // 监听 API 基础地址的变化
  final baseUrl = ref.watch(apiBaseUrlProvider);
  // 视频流 API 路径已经包含 /api，所以直接使用 baseUrl
  return VideoStreamingService(baseUrl: baseUrl);
});

/// PC API 服务
final pcApiServiceProvider = Provider<ApiService>((ref) {
  // 监听 API 基础地址的变化
  final baseUrl = ref.watch(apiBaseUrlProvider);
  // 添加 /api 路径
  final fullApiUrl = getFullApiUrl(baseUrl);
  return ApiService(baseUrl: fullApiUrl);
});

/// 本地 HTTP 服务器
final localHttpServerProvider = Provider<LocalHttpServer>((ref) {
  final localDb = ref.watch(localDatabaseProvider);
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final actorRepo = ref.watch(actorRepositoryProvider);
  final thumbnailService = ref.watch(videoThumbnailServiceProvider);
  
  return LocalHttpServer(
    port: 8080,
    database: localDb,
    thumbnailService: thumbnailService,
    onMediaReceived: (data) async {
      try {
        print('📥 ========== 开始处理媒体数据 ==========');
        print('📥 收到的原始数据: $data');
        print('📥 标题: ${data['title']}');
        
        // 使用类似后端的方式处理数据
        // 生成必需字段
        final now = DateTime.now();
        // 使用 UUID 而不是时间戳
        final uuid = const Uuid();
        final id = data['code'] ?? uuid.v4();
        
        print('📥 生成的 ID: $id');
        
        // 处理 cast 字段 - 保持为对象数组格式
        List<Map<String, dynamic>> castList = [];
        if (data['cast'] != null) {
          final castData = data['cast'] as List<dynamic>;
          for (var item in castData) {
            if (item is Map) {
              castList.add({
                'name': item['name']?.toString() ?? '',
                'role': item['role']?.toString() ?? 'Actor',
                'character': item['character']?.toString(),
              });
            } else if (item is String) {
              // 如果是字符串，转换为对象格式
              castList.add({
                'name': item,
                'role': 'Actor',
                'character': null,
              });
            }
          }
        }
        print('📥 处理后的演员列表: $castList');
        
        // 处理 crew 字段 - 保持为对象数组格式
        List<Map<String, dynamic>> crewList = [];
        if (data['crew'] != null) {
          final crewData = data['crew'] as List<dynamic>;
          for (var item in crewData) {
            if (item is Map) {
              crewList.add({
                'name': item['name']?.toString() ?? '',
                'role': item['role']?.toString() ?? 'Crew',
                'character': item['character']?.toString(),
              });
            } else if (item is String) {
              crewList.add({
                'name': item,
                'role': 'Crew',
                'character': null,
              });
            }
          }
        }
        
        // 处理 play_links - 保持为对象数组格式
        List<Map<String, dynamic>> playLinksList = [];
        if (data['play_links'] != null) {
          final playLinksData = data['play_links'] as List<dynamic>;
          for (var item in playLinksData) {
            if (item is Map) {
              playLinksList.add({
                'name': item['name']?.toString() ?? '',
                'url': item['url']?.toString() ?? '',
                'quality': item['quality']?.toString(),
              });
            }
          }
        }
        
        // 处理 download_links - 保持为对象数组格式
        List<Map<String, dynamic>> downloadLinksList = [];
        if (data['download_links'] != null) {
          final downloadLinksData = data['download_links'] as List<dynamic>;
          for (var item in downloadLinksData) {
            if (item is Map) {
              downloadLinksList.add({
                'name': item['name']?.toString() ?? '',
                'url': item['url']?.toString() ?? '',
                'link_type': item['link_type']?.toString() ?? 'other',
                'size': item['size']?.toString(),
                'password': item['password']?.toString(),
              });
            }
          }
        }
        
        // 构建完整的 MediaItem 数据
        final mediaData = <String, dynamic>{
          'id': id,
          'code': data['code'],
          'title': data['title'] ?? '',
          'original_title': data['original_title'],
          'year': data['year'],
          'media_type': data['media_type'] ?? 'Movie',
          'genres': (data['genres'] as List<dynamic>?)?.cast<String>() ?? <String>[],
          'rating': data['rating'],
          'vote_count': data['vote_count'],
          'poster_url': data['poster_url'],
          'backdrop_url': data['backdrop_url'],
          'overview': data['overview'] ?? data['description'],  // 支持 description 字段
          'runtime': data['runtime'],
          'release_date': data['release_date'],
          'cast': castList,
          'crew': crewList,
          'language': data['language'],
          'country': data['country'],
          'budget': data['budget'],
          'revenue': data['revenue'],
          'status': data['status'],
          'external_ids': (data['external_ids'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? <String, dynamic>{},
          'play_links': playLinksList,
          'download_links': downloadLinksList,
          'preview_urls': (data['preview_urls'] as List<dynamic>?)?.cast<String>() ?? <String>[],
          'preview_video_urls': (data['preview_video_urls'] as List<dynamic>?)?.cast<String>() ?? <String>[],
          'studio': data['studio'],
          'series': data['series'],
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'last_synced_at': null,
          'is_synced': false,
          'sync_version': null,
        };
        
        print('📥 构建的完整数据: $mediaData');
        
        // 将 JSON 数据转换为 MediaItem
        print('📥 开始转换为 MediaItem...');
        final media = MediaItem.fromJson(mediaData);
        print('✓ MediaItem 转换成功');
        print('  - ID: ${media.id}');
        print('  - 标题: ${media.title}');
        print('  - 类型: ${media.mediaType}');
        print('  - 演员数量: ${media.cast.length}');
        print('  - 下载链接数量: ${media.downloadLinks.length}');
        
        // 保存到数据库（通过 Repository）
        print('📥 开始保存到数据库...');
        final savedMedia = await mediaRepo.addMedia(media);
        print('✓ 数据库保存成功');
        print('  - 保存的 ID: ${savedMedia.id}');
        print('  - 保存的标题: ${savedMedia.title}');
        
        print('✓ ========== 媒体保存完成 ==========');
      } catch (e, stackTrace) {
        print('✗ ========== 保存失败 ==========');
        print('✗ 错误: $e');
        print('✗ 堆栈跟踪: $stackTrace');
      }
    },
    onActorReceived: (data) async {
      try {
        print('📥 Received actor from userscript: ${data['name']}');
        
        // 使用类似后端的方式处理数据
        // 生成必需字段
        final now = DateTime.now();
        // 使用 UUID 而不是时间戳
        final uuid = const Uuid();
        final id = data['name'] ?? uuid.v4();
        
        // 构建完整的 Actor 数据
        final actorData = {
          'id': id,
          'name': data['name'] ?? '',
          'photo_url': data['photo_url'],
          'backdrop_url': data['backdrop_url'],
          'biography': data['biography'],
          'birth_date': data['birth_date'],
          'nationality': data['nationality'],
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'work_count': null,
          'last_synced_at': null,
          'is_synced': false,
          'sync_version': null,
        };
        
        // 将 JSON 数据转换为 Actor
        final actor = Actor.fromJson(actorData);
        
        // 保存到数据库（通过 Repository）
        await actorRepo.addActor(actor);
        
        print('✓ Actor saved: ${actor.name}');
      } catch (e, stackTrace) {
        print('✗ Failed to save actor: $e');
        print('Stack trace: $stackTrace');
      }
    },
  );
});

/// 应用初始化器
final appInitializerProvider = Provider<AppInitializer>((ref) {
  return AppInitializer(
    modeManager: ref.watch(backendModeManagerProvider),
    localServer: ref.watch(localHttpServerProvider),
    onBackendUrlChanged: (url) {
      print('🔄 onBackendUrlChanged 被调用: $url');
      // 更新 apiBaseUrlProvider
      ref.read(apiBaseUrlProvider.notifier).state = url;
      print('✓ apiBaseUrlProvider 已更新为: $url');
    },
  );
});

/// 当前后端模式
final currentBackendModeProvider = FutureProvider<BackendMode>((ref) async {
  final modeManager = ref.watch(backendModeManagerProvider);
  return await modeManager.autoSelectMode();
});

/// 媒体仓库
final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
    localDb: ref.watch(localDatabaseProvider),
    apiService: ref.watch(pcApiServiceProvider),
    modeManager: ref.watch(backendModeManagerProvider),
  );
});

/// 演员仓库
final actorRepositoryProvider = Provider<ActorRepository>((ref) {
  return ActorRepository(
    localDb: ref.watch(localDatabaseProvider),
    apiService: ref.watch(pcApiServiceProvider),
    modeManager: ref.watch(backendModeManagerProvider),
  );
});

/// 收藏仓库
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return CollectionRepository(
    localDb: ref.watch(localDatabaseProvider),
    apiService: ref.watch(pcApiServiceProvider),
    modeManager: ref.watch(backendModeManagerProvider),
  );
});
