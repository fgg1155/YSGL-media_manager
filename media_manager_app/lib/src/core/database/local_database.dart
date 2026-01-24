import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/media_item.dart';
import '../models/actor.dart';
import '../models/collection.dart';

/// 本地数据库（独立模式）
class LocalDatabase {
  static Database? _database;
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'media_manager.db');

    return await openDatabase(
      path,
      version: 5,  // 增加版本号以添加演员图片字段
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // 启用外键约束
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 媒体表（扩展字段）
    await db.execute('''
      CREATE TABLE media (
        id TEXT PRIMARY KEY,
        code TEXT,
        title TEXT NOT NULL,
        original_title TEXT,
        year INTEGER,
        media_type TEXT NOT NULL,
        genres TEXT,
        rating REAL,
        vote_count INTEGER,
        poster_url TEXT,
        backdrop_url TEXT,
        overview TEXT,
        runtime INTEGER,
        release_date TEXT,
        cast TEXT,
        crew TEXT,
        language TEXT,
        country TEXT,
        budget INTEGER,
        revenue INTEGER,
        status TEXT,
        external_ids TEXT,
        play_links TEXT,
        download_links TEXT,
        preview_urls TEXT,
        preview_video_urls TEXT,
        studio TEXT,
        series TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_synced_at TEXT,
        is_synced INTEGER DEFAULT 0,
        sync_version TEXT
      )
    ''');

    // 演员表
    await db.execute('''
      CREATE TABLE actors (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar_url TEXT,
        photo_url TEXT,
        poster_url TEXT,
        backdrop_url TEXT,
        biography TEXT,
        birth_date TEXT,
        nationality TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_synced_at TEXT,
        is_synced INTEGER DEFAULT 0,
        sync_version TEXT
      )
    ''');

    // 媒体-演员关联表
    await db.execute('''
      CREATE TABLE media_actors (
        media_id TEXT NOT NULL,
        actor_id TEXT NOT NULL,
        PRIMARY KEY (media_id, actor_id),
        FOREIGN KEY (media_id) REFERENCES media(id) ON DELETE CASCADE,
        FOREIGN KEY (actor_id) REFERENCES actors(id) ON DELETE CASCADE
      )
    ''');

    // 收藏表
    await db.execute('''
      CREATE TABLE collections (
        id TEXT PRIMARY KEY,
        media_id TEXT NOT NULL UNIQUE,
        watch_status TEXT NOT NULL,
        watch_progress REAL,
        personal_rating REAL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        user_tags TEXT,
        notes TEXT,
        added_at TEXT NOT NULL,
        last_watched TEXT,
        completed_at TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (media_id) REFERENCES media(id) ON DELETE CASCADE
      )
    ''');

    // 创建索引
    await db.execute('CREATE INDEX idx_media_title ON media(title)');
    await db.execute('CREATE INDEX idx_media_type ON media(media_type)');
    await db.execute('CREATE INDEX idx_media_studio ON media(studio)');
    await db.execute('CREATE INDEX idx_media_synced ON media(is_synced)');
    await db.execute('CREATE INDEX idx_media_updated ON media(updated_at)');
    await db.execute('CREATE INDEX idx_actor_name ON actors(name)');
    await db.execute('CREATE INDEX idx_actor_synced ON actors(is_synced)');
    await db.execute('CREATE UNIQUE INDEX idx_collections_media_id ON collections(media_id)');
    await db.execute('CREATE INDEX idx_collections_watch_status ON collections(watch_status)');
    await db.execute('CREATE INDEX idx_collections_is_favorite ON collections(is_favorite)');
    await db.execute('CREATE INDEX idx_collections_added_at ON collections(added_at)');

    print('✓ Local database initialized');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 添加 collections 表
      await db.execute('''
        CREATE TABLE collections (
          id TEXT PRIMARY KEY,
          media_id TEXT NOT NULL UNIQUE,
          watch_status TEXT NOT NULL,
          watch_progress REAL,
          personal_rating REAL,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          user_tags TEXT,
          notes TEXT,
          added_at TEXT NOT NULL,
          last_watched TEXT,
          completed_at TEXT,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (media_id) REFERENCES media(id) ON DELETE CASCADE
        )
      ''');
      
      await db.execute('CREATE UNIQUE INDEX idx_collections_media_id ON collections(media_id)');
      await db.execute('CREATE INDEX idx_collections_watch_status ON collections(watch_status)');
      await db.execute('CREATE INDEX idx_collections_is_favorite ON collections(is_favorite)');
      await db.execute('CREATE INDEX idx_collections_added_at ON collections(added_at)');
      
      print('✓ Collections table created (migration v1 -> v2)');
    }
    
    if (oldVersion < 3) {
      // 添加同步字段
      await db.execute('ALTER TABLE media ADD COLUMN last_synced_at TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN is_synced INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE media ADD COLUMN sync_version TEXT');
      
      await db.execute('ALTER TABLE actors ADD COLUMN last_synced_at TEXT');
      await db.execute('ALTER TABLE actors ADD COLUMN is_synced INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE actors ADD COLUMN sync_version TEXT');
      
      // 添加同步索引
      await db.execute('CREATE INDEX idx_media_synced ON media(is_synced)');
      await db.execute('CREATE INDEX idx_media_updated ON media(updated_at)');
      await db.execute('CREATE INDEX idx_actor_synced ON actors(is_synced)');
      
      print('✓ Sync fields added (migration v2 -> v3)');
    }
    
    if (oldVersion < 4) {
      // 添加缺失的媒体字段
      await db.execute('ALTER TABLE media ADD COLUMN cast TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN crew TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN budget INTEGER');
      await db.execute('ALTER TABLE media ADD COLUMN revenue INTEGER');
      await db.execute('ALTER TABLE media ADD COLUMN status TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN external_ids TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN play_links TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN download_links TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN preview_urls TEXT');
      await db.execute('ALTER TABLE media ADD COLUMN preview_video_urls TEXT');
      
      print('✓ Extended media fields added (migration v3 -> v4)');
    }
    
    if (oldVersion < 5) {
      // 添加演员图片字段
      await db.execute('ALTER TABLE actors ADD COLUMN avatar_url TEXT');
      await db.execute('ALTER TABLE actors ADD COLUMN poster_url TEXT');
      
      print('✓ Actor image fields added (migration v4 -> v5)');
    }
  }

  // ==================== Media CRUD ====================

  /// 插入媒体
  Future<String> insertMedia(MediaItem media) async {
    final db = await database;
    await db.insert(
      'media',
      _mediaToMap(media),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return media.id;
  }

  /// 获取单个媒体
  Future<MediaItem?> getMedia(String id) async {
    final db = await database;
    final results = await db.query(
      'media',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (results.isEmpty) return null;
    return _mapToMedia(results.first);
  }

  /// 查询媒体列表
  Future<List<MediaItem>> queryMedia({
    String? mediaType,
    String? searchQuery,
    String? studio,
    String? series,
    String? sortBy,
    String? sortOrder,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];
    
    if (mediaType != null) {
      whereClause = 'media_type = ?';
      whereArgs.add(mediaType);
    }
    
    if (searchQuery != null && searchQuery.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += '(title LIKE ? OR code LIKE ?)';
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }
    
    if (studio != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'studio = ?';
      whereArgs.add(studio);
    }
    
    if (series != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'series = ?';
      whereArgs.add(series);
    }
    
    // 构建排序子句
    final sortColumn = sortBy ?? 'created_at';
    final sortDirection = (sortOrder?.toUpperCase() ?? 'DESC');
    final orderByClause = '$sortColumn $sortDirection';
    
    final results = await db.query(
      'media',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    
    return results.map(_mapToMedia).toList();
  }

  /// 更新媒体
  Future<void> updateMedia(MediaItem media) async {
    final db = await database;
    await db.update(
      'media',
      _mediaToMap(media),
      where: 'id = ?',
      whereArgs: [media.id],
    );
  }

  /// 删除媒体
  Future<void> deleteMedia(String id) async {
    final db = await database;
    
    // 使用事务确保数据一致性
    await db.transaction((txn) async {
      // 删除媒体
      await txn.delete(
        'media',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      // 删除相关的收藏记录
      await txn.delete(
        'collections',
        where: 'media_id = ?',
        whereArgs: [id],
      );
      
      // 删除相关的演员-媒体关系
      await txn.delete(
        'media_actors',
        where: 'media_id = ?',
        whereArgs: [id],
      );
    });
  }

  /// 获取媒体总数
  Future<int> getMediaCount({String? mediaType}) async {
    final db = await database;
    final result = await db.query(
      'media',
      columns: ['COUNT(*) as count'],
      where: mediaType != null ? 'media_type = ?' : null,
      whereArgs: mediaType != null ? [mediaType] : null,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== Actor CRUD ====================

  /// 插入演员
  Future<String> insertActor(Actor actor) async {
    final db = await database;
    await db.insert(
      'actors',
      _actorToMap(actor),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return actor.id;
  }

  /// 获取单个演员
  Future<Actor?> getActor(String id) async {
    final db = await database;
    final results = await db.query(
      'actors',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (results.isEmpty) return null;
    return _mapToActor(results.first);
  }

  /// 查询演员列表
  Future<List<Actor>> queryActors({
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    
    final results = await db.query(
      'actors',
      where: searchQuery != null && searchQuery.isNotEmpty ? 'name LIKE ?' : null,
      whereArgs: searchQuery != null && searchQuery.isNotEmpty ? ['%$searchQuery%'] : null,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    
    return results.map(_mapToActor).toList();
  }

  /// 更新演员
  Future<void> updateActor(Actor actor) async {
    final db = await database;
    await db.update(
      'actors',
      _actorToMap(actor),
      where: 'id = ?',
      whereArgs: [actor.id],
    );
  }

  /// 删除演员
  Future<void> deleteActor(String id) async {
    final db = await database;
    
    // 使用事务确保数据一致性
    await db.transaction((txn) async {
      // 删除演员
      await txn.delete(
        'actors',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      // 删除相关的演员-媒体关系
      await txn.delete(
        'media_actors',
        where: 'actor_id = ?',
        whereArgs: [id],
      );
    });
  }

  // ==================== Relationship Management ====================

  /// 关联媒体和演员
  Future<void> linkMediaActor(String mediaId, String actorId) async {
    final db = await database;
    await db.insert(
      'media_actors',
      {'media_id': mediaId, 'actor_id': actorId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 取消关联
  Future<void> unlinkMediaActor(String mediaId, String actorId) async {
    final db = await database;
    await db.delete(
      'media_actors',
      where: 'media_id = ? AND actor_id = ?',
      whereArgs: [mediaId, actorId],
    );
  }

  /// 获取媒体的所有演员
  Future<List<Actor>> getMediaActors(String mediaId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT a.* FROM actors a
      INNER JOIN media_actors ma ON a.id = ma.actor_id
      WHERE ma.media_id = ?
      ORDER BY a.name ASC
    ''', [mediaId]);
    
    return results.map(_mapToActor).toList();
  }

  /// 获取演员的所有媒体
  Future<List<MediaItem>> getActorMedia(String actorId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT m.* FROM media m
      INNER JOIN media_actors ma ON m.id = ma.media_id
      WHERE ma.actor_id = ?
      ORDER BY m.created_at DESC
    ''', [actorId]);
    
    return results.map(_mapToMedia).toList();
  }

  // ==================== Helper Methods ====================

  /// MediaItem 转 Map
  Map<String, dynamic> _mediaToMap(MediaItem media) {
    return {
      'id': media.id,
      'code': media.code,
      'title': media.title,
      'original_title': media.originalTitle,
      'year': media.year,
      'media_type': media.mediaType.name,
      'genres': jsonEncode(media.genres),  // 改为JSON格式，与PC端一致
      'rating': media.rating,
      'vote_count': media.voteCount,
      'poster_url': media.posterUrl,
      'backdrop_url': media.backdropUrl,
      'overview': media.overview,
      'runtime': media.runtime,
      'release_date': media.releaseDate,
      'cast': jsonEncode(media.cast.map((p) => p.toJson()).toList()),
      'crew': jsonEncode(media.crew.map((p) => p.toJson()).toList()),
      'language': media.language,
      'country': media.country,
      'budget': media.budget,
      'revenue': media.revenue,
      'status': media.status,
      'external_ids': jsonEncode(media.externalIds.toJson()),
      'play_links': jsonEncode(media.playLinks.map((l) => l.toJson()).toList()),
      'download_links': jsonEncode(media.downloadLinks.map((l) => l.toJson()).toList()),
      'preview_urls': jsonEncode(media.previewUrls),
      'preview_video_urls': jsonEncode(media.previewVideoUrls),
      'studio': media.studio,
      'series': media.series,
      'created_at': media.createdAt.toIso8601String(),
      'updated_at': media.updatedAt.toIso8601String(),
      'last_synced_at': media.lastSyncedAt?.toIso8601String(),
      'is_synced': media.isSynced ? 1 : 0,
      'sync_version': media.syncVersion,
    };
  }

  /// Map 转 MediaItem
  MediaItem _mapToMedia(Map<String, dynamic> map) {
    // 解析 genres - 支持两种格式：JSON数组或逗号分隔
    List<String> genres = [];
    if (map['genres'] != null && (map['genres'] as String).isNotEmpty) {
      final genresStr = map['genres'] as String;
      try {
        // 尝试作为JSON数组解析
        if (genresStr.startsWith('[')) {
          final genresJson = jsonDecode(genresStr) as List<dynamic>;
          genres = genresJson.cast<String>();
        } else {
          // 回退到逗号分隔格式（向后兼容）
          genres = genresStr.split(',').where((s) => s.isNotEmpty).toList();
        }
      } catch (e) {
        print('Error parsing genres: $e');
        // 回退到逗号分隔格式
        genres = genresStr.split(',').where((s) => s.isNotEmpty).toList();
      }
    }
    
    // 解析 cast
    List<Person> cast = [];
    if (map['cast'] != null && (map['cast'] as String).isNotEmpty) {
      try {
        final castJson = jsonDecode(map['cast'] as String) as List<dynamic>;
        cast = castJson.map((e) => Person.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        print('Error parsing cast: $e');
      }
    }
    
    // 解析 crew
    List<Person> crew = [];
    if (map['crew'] != null && (map['crew'] as String).isNotEmpty) {
      try {
        final crewJson = jsonDecode(map['crew'] as String) as List<dynamic>;
        crew = crewJson.map((e) => Person.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        print('Error parsing crew: $e');
      }
    }
    
    // 解析 external_ids
    ExternalIds externalIds = const ExternalIds();
    if (map['external_ids'] != null && (map['external_ids'] as String).isNotEmpty) {
      try {
        final idsJson = jsonDecode(map['external_ids'] as String) as Map<String, dynamic>;
        externalIds = ExternalIds.fromJson(idsJson);
      } catch (e) {
        print('Error parsing external_ids: $e');
      }
    }
    
    // 解析 play_links
    List<PlayLink> playLinks = [];
    if (map['play_links'] != null && (map['play_links'] as String).isNotEmpty) {
      try {
        final linksJson = jsonDecode(map['play_links'] as String) as List<dynamic>;
        playLinks = linksJson.map((e) => PlayLink.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        print('Error parsing play_links: $e');
      }
    }
    
    // 解析 download_links
    List<DownloadLink> downloadLinks = [];
    if (map['download_links'] != null && (map['download_links'] as String).isNotEmpty) {
      try {
        final linksJson = jsonDecode(map['download_links'] as String) as List<dynamic>;
        downloadLinks = linksJson.map((e) => DownloadLink.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        print('Error parsing download_links: $e');
      }
    }
    
    // 解析 preview_urls
    List<String> previewUrls = [];
    if (map['preview_urls'] != null && (map['preview_urls'] as String).isNotEmpty) {
      try {
        final urlsJson = jsonDecode(map['preview_urls'] as String) as List<dynamic>;
        previewUrls = urlsJson.cast<String>();
      } catch (e) {
        print('Error parsing preview_urls: $e');
      }
    }
    
    // 解析 preview_video_urls
    List<String> previewVideoUrls = [];
    if (map['preview_video_urls'] != null && (map['preview_video_urls'] as String).isNotEmpty) {
      try {
        final urlsJson = jsonDecode(map['preview_video_urls'] as String) as List<dynamic>;
        previewVideoUrls = urlsJson.cast<String>();
      } catch (e) {
        print('Error parsing preview_video_urls: $e');
      }
    }
    
    return MediaItem(
      id: map['id'] as String,
      code: map['code'] as String?,
      title: map['title'] as String,
      originalTitle: map['original_title'] as String?,
      year: map['year'] as int?,
      mediaType: MediaType.values.firstWhere(
        (e) => e.name == map['media_type'],
        orElse: () => MediaType.movie,
      ),
      genres: genres,
      rating: map['rating'] as double?,
      voteCount: map['vote_count'] as int?,
      posterUrl: map['poster_url'] as String?,
      backdropUrl: (map['backdrop_url'] as String?)?.isNotEmpty == true 
          ? [map['backdrop_url'] as String]
          : [],
      overview: map['overview'] as String?,
      runtime: map['runtime'] as int?,
      releaseDate: map['release_date'] as String?,
      cast: cast,
      crew: crew,
      language: map['language'] as String?,
      country: map['country'] as String?,
      budget: map['budget'] as int?,
      revenue: map['revenue'] as int?,
      status: map['status'] as String?,
      externalIds: externalIds,
      playLinks: playLinks,
      downloadLinks: downloadLinks,
      previewUrls: previewUrls,
      previewVideoUrls: previewVideoUrls,
      studio: map['studio'] as String?,
      series: map['series'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastSyncedAt: map['last_synced_at'] != null 
          ? DateTime.parse(map['last_synced_at'] as String) 
          : null,
      isSynced: (map['is_synced'] as int?) == 1,
      syncVersion: map['sync_version'] as String?,
    );
  }

  /// Actor 转 Map
  Map<String, dynamic> _actorToMap(Actor actor) {
    return {
      'id': actor.id,
      'name': actor.name,
      'avatar_url': actor.avatarUrl,
      'photo_url': actor.photoUrls != null && actor.photoUrls!.isNotEmpty
          ? jsonEncode(actor.photoUrls)
          : null,
      'poster_url': actor.posterUrl,
      'backdrop_url': actor.backdropUrl,
      'biography': actor.biography,
      'birth_date': actor.birthDate,
      'nationality': actor.nationality,
      'created_at': actor.createdAt.toIso8601String(),
      'updated_at': actor.updatedAt.toIso8601String(),
      'last_synced_at': actor.lastSyncedAt?.toIso8601String(),
      'is_synced': actor.isSynced ? 1 : 0,
      'sync_version': actor.syncVersion,
    };
  }

  /// Map 转 Actor
  Actor _mapToActor(Map<String, dynamic> map) {
    // 解析 photo_url（可能是 JSON 数组或单个字符串）
    List<String>? photoUrls;
    final photoUrlValue = map['photo_url'];
    if (photoUrlValue != null && photoUrlValue is String && photoUrlValue.isNotEmpty) {
      try {
        // 尝试解析为 JSON 数组
        final decoded = jsonDecode(photoUrlValue);
        if (decoded is List) {
          photoUrls = decoded.cast<String>();
        } else if (decoded is String) {
          photoUrls = [decoded];
        }
      } catch (e) {
        // 如果不是 JSON，当作单个 URL
        photoUrls = [photoUrlValue];
      }
    }
    
    return Actor(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatar_url'] as String?,
      photoUrls: photoUrls,
      posterUrl: map['poster_url'] as String?,
      backdropUrl: map['backdrop_url'] as String?,
      biography: map['biography'] as String?,
      birthDate: map['birth_date'] as String?,
      nationality: map['nationality'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastSyncedAt: map['last_synced_at'] != null 
          ? DateTime.parse(map['last_synced_at'] as String) 
          : null,
      isSynced: (map['is_synced'] as int?) == 1,
      syncVersion: map['sync_version'] as String?,
    );
  }

  // ==================== Collection CRUD ====================

  /// 插入收藏
  Future<String> insertCollection(Collection collection) async {
    final db = await database;
    await db.insert(
      'collections',
      _collectionToMap(collection),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return collection.id;
  }

  /// 获取单个收藏（通过 media_id）
  Future<Collection?> getCollection(String mediaId) async {
    final db = await database;
    final results = await db.query(
      'collections',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    
    if (results.isEmpty) return null;
    return _mapToCollection(results.first);
  }

  /// 查询收藏列表
  Future<List<Collection>> queryCollections({
    WatchStatus? watchStatus,
    bool? isFavorite,
    String? sortBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];
    
    if (watchStatus != null) {
      whereClause = 'watch_status = ?';
      whereArgs.add(_watchStatusToString(watchStatus));
    }
    
    if (isFavorite != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'is_favorite = ?';
      whereArgs.add(isFavorite ? 1 : 0);
    }
    
    final results = await db.query(
      'collections',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: sortBy ?? 'added_at DESC',
      limit: limit,
      offset: offset,
    );
    
    return results.map(_mapToCollection).toList();
  }

  /// 更新收藏
  Future<void> updateCollection(Collection collection) async {
    final db = await database;
    await db.update(
      'collections',
      _collectionToMap(collection),
      where: 'media_id = ?',
      whereArgs: [collection.mediaId],
    );
  }

  /// 删除收藏（通过 media_id）
  Future<void> deleteCollection(String mediaId) async {
    final db = await database;
    await db.delete(
      'collections',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
  }

  /// 获取收藏总数
  Future<int> getCollectionCount({WatchStatus? watchStatus}) async {
    final db = await database;
    final result = await db.query(
      'collections',
      columns: ['COUNT(*) as count'],
      where: watchStatus != null ? 'watch_status = ?' : null,
      whereArgs: watchStatus != null ? [_watchStatusToString(watchStatus)] : null,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 检查是否已收藏
  Future<bool> isInCollection(String mediaId) async {
    final db = await database;
    final result = await db.query(
      'collections',
      columns: ['COUNT(*) as count'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  /// Collection 转 Map
  Map<String, dynamic> _collectionToMap(Collection collection) {
    return {
      'id': collection.id,
      'media_id': collection.mediaId,
      'watch_status': _watchStatusToString(collection.watchStatus),
      'watch_progress': collection.watchProgress,
      'personal_rating': collection.personalRating,
      'is_favorite': collection.isFavorite ? 1 : 0,
      'user_tags': jsonEncode(collection.userTags),
      'notes': collection.notes,
      'added_at': collection.addedAt.toIso8601String(),
      'last_watched': collection.lastWatched?.toIso8601String(),
      'completed_at': collection.completedAt?.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Map 转 Collection
  Collection _mapToCollection(Map<String, dynamic> map) {
    return Collection(
      id: map['id'] as String,
      mediaId: map['media_id'] as String,
      watchStatus: _stringToWatchStatus(map['watch_status'] as String),
      watchProgress: map['watch_progress'] as double?,
      personalRating: map['personal_rating'] as double?,
      isFavorite: (map['is_favorite'] as int) == 1,
      userTags: (jsonDecode(map['user_tags'] as String? ?? '[]') as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      notes: map['notes'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
      lastWatched: map['last_watched'] != null 
          ? DateTime.parse(map['last_watched'] as String) 
          : null,
      completedAt: map['completed_at'] != null 
          ? DateTime.parse(map['completed_at'] as String) 
          : null,
    );
  }

  /// WatchStatus 转 String
  String _watchStatusToString(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return 'WantToWatch';
      case WatchStatus.watching:
        return 'Watching';
      case WatchStatus.completed:
        return 'Completed';
      case WatchStatus.onHold:
        return 'OnHold';
      case WatchStatus.dropped:
        return 'Dropped';
    }
  }

  /// String 转 WatchStatus
  WatchStatus _stringToWatchStatus(String status) {
    switch (status) {
      case 'WantToWatch':
        return WatchStatus.wantToWatch;
      case 'Watching':
        return WatchStatus.watching;
      case 'Completed':
        return WatchStatus.completed;
      case 'OnHold':
        return WatchStatus.onHold;
      case 'Dropped':
        return WatchStatus.dropped;
      default:
        return WatchStatus.wantToWatch;
    }
  }

  /// 事务支持
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  // ==================== Sync Support ====================

  /// 获取未同步的媒体
  Future<List<MediaItem>> getUnsyncedMedia() async {
    final db = await database;
    final results = await db.query(
      'media',
      where: 'is_synced = 0',
      orderBy: 'updated_at DESC',
    );
    return results.map(_mapToMedia).toList();
  }

  /// 获取未同步的演员
  Future<List<Actor>> getUnsyncedActors() async {
    final db = await database;
    final results = await db.query(
      'actors',
      where: 'is_synced = 0',
      orderBy: 'updated_at DESC',
    );
    return results.map(_mapToActor).toList();
  }

  /// 标记媒体为已同步
  Future<void> markMediaSynced(String id, DateTime syncTime) async {
    final db = await database;
    await db.update(
      'media',
      {
        'is_synced': 1,
        'last_synced_at': syncTime.toIso8601String(),
        'sync_version': syncTime.millisecondsSinceEpoch.toString(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 标记演员为已同步
  Future<void> markActorSynced(String id, DateTime syncTime) async {
    final db = await database;
    await db.update(
      'actors',
      {
        'is_synced': 1,
        'last_synced_at': syncTime.toIso8601String(),
        'sync_version': syncTime.millisecondsSinceEpoch.toString(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 清空所有数据（用于测试）
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('collections');
    await db.delete('media_actors');
    await db.delete('media');
    await db.delete('actors');
  }

  // ==================== Filter Options ====================

  /// 获取所有不同的媒体类型
  Future<List<String>> getDistinctMediaTypes() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT media_type FROM media
      WHERE media_type IS NOT NULL AND media_type != ''
      ORDER BY media_type ASC
    ''');
    return results.map((row) => row['media_type'] as String).toList();
  }

  /// 获取所有不同的制作商
  Future<List<String>> getDistinctStudios() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT studio FROM media
      WHERE studio IS NOT NULL AND studio != ''
      ORDER BY studio ASC
    ''');
    return results.map((row) => row['studio'] as String).toList();
  }

  /// 获取所有不同的系列
  Future<List<String>> getDistinctSeries() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT series FROM media
      WHERE series IS NOT NULL AND series != ''
      ORDER BY series ASC
    ''');
    return results.map((row) => row['series'] as String).toList();
  }

  /// 获取所有不同的年份
  Future<List<int>> getDistinctYears() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT year FROM media
      WHERE year IS NOT NULL
      ORDER BY year DESC
    ''');
    return results.map((row) => row['year'] as int).toList();
  }

  /// 获取所有不同的类型/流派
  Future<List<String>> getDistinctGenres() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT genres FROM media
      WHERE genres IS NOT NULL AND genres != ''
    ''');
    
    // 解析逗号分隔的类型列表
    final genresSet = <String>{};
    for (final row in results) {
      final genresStr = row['genres'] as String;
      final genres = genresStr.split(',').where((g) => g.isNotEmpty);
      genresSet.addAll(genres);
    }
    
    final genresList = genresSet.toList()..sort();
    return genresList;
  }
}
