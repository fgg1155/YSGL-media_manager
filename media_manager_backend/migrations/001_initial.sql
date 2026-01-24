-- Initial database schema for Media Manager
-- Version: 1.0.0

-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- 影视条目表
CREATE TABLE media_items (
    id TEXT PRIMARY KEY NOT NULL,
    external_ids TEXT NOT NULL DEFAULT '{}', -- JSON格式存储外部ID
    title TEXT NOT NULL CHECK(length(title) > 0),
    original_title TEXT,
    year INTEGER CHECK(year IS NULL OR (year >= 1800 AND year <= 2100)),
    media_type TEXT NOT NULL CHECK(media_type IN ('Movie', 'TvShow', 'Documentary', 'Anime')),
    genres TEXT NOT NULL DEFAULT '[]', -- JSON数组
    rating REAL CHECK(rating IS NULL OR (rating >= 0.0 AND rating <= 10.0)),
    vote_count INTEGER CHECK(vote_count IS NULL OR vote_count >= 0),
    poster_url TEXT,
    backdrop_url TEXT,
    overview TEXT,
    runtime INTEGER CHECK(runtime IS NULL OR runtime > 0), -- 分钟
    release_date TEXT, -- ISO 8601 format: YYYY-MM-DD
    cast TEXT DEFAULT '[]', -- JSON数组
    crew TEXT DEFAULT '[]', -- JSON数组
    language TEXT, -- ISO 639-1 language code
    country TEXT, -- ISO 3166-1 country code
    budget INTEGER CHECK(budget IS NULL OR budget >= 0),
    revenue INTEGER CHECK(revenue IS NULL OR revenue >= 0),
    status TEXT CHECK(status IS NULL OR status IN ('Released', 'In Production', 'Post Production', 'Planned', 'Canceled')),
    play_links TEXT DEFAULT '[]', -- JSON数组: 播放链接
    download_links TEXT DEFAULT '[]', -- JSON数组: 下载链接
    preview_urls TEXT DEFAULT '[]', -- JSON数组: 预览图片URL
    preview_video_urls TEXT DEFAULT '[]', -- JSON数组: 预览视频URL
    studio TEXT, -- 制作公司/工作室
    series TEXT, -- 系列名称
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 收藏表
CREATE TABLE collections (
    id TEXT PRIMARY KEY NOT NULL,
    media_id TEXT NOT NULL,
    user_tags TEXT NOT NULL DEFAULT '[]', -- JSON数组
    personal_rating REAL CHECK(personal_rating IS NULL OR (personal_rating >= 0.0 AND personal_rating <= 10.0)),
    watch_status TEXT NOT NULL DEFAULT 'WantToWatch' CHECK(watch_status IN ('WantToWatch', 'Watching', 'Completed', 'OnHold', 'Dropped')),
    watch_progress REAL CHECK(watch_progress IS NULL OR (watch_progress >= 0.0 AND watch_progress <= 1.0)),
    notes TEXT,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    added_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_watched TEXT,
    completed_at TEXT,
    FOREIGN KEY (media_id) REFERENCES media_items(id) ON DELETE CASCADE,
    UNIQUE(media_id) -- 确保每个媒体项目只能被收藏一次
);

-- 用户设置表
CREATE TABLE user_settings (
    key TEXT PRIMARY KEY NOT NULL CHECK(length(key) > 0),
    value TEXT NOT NULL,
    description TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 同步状态表
CREATE TABLE sync_status (
    device_id TEXT PRIMARY KEY NOT NULL CHECK(length(device_id) > 0),
    device_name TEXT,
    last_sync TEXT NOT NULL DEFAULT (datetime('now')),
    sync_version INTEGER NOT NULL DEFAULT 1 CHECK(sync_version > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 缓存表 - 用于存储外部API响应
CREATE TABLE api_cache (
    cache_key TEXT PRIMARY KEY NOT NULL,
    cache_value TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 搜索历史表
CREATE TABLE search_history (
    id TEXT PRIMARY KEY NOT NULL,
    query TEXT NOT NULL CHECK(length(query) > 0),
    result_count INTEGER NOT NULL DEFAULT 0,
    searched_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 演员表
CREATE TABLE actors (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK(length(name) > 0),
    photo_url TEXT,
    biography TEXT,
    birth_date TEXT,
    nationality TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 演员-媒体关联表
CREATE TABLE actor_media (
    id TEXT PRIMARY KEY NOT NULL,
    actor_id TEXT NOT NULL,
    media_id TEXT NOT NULL,
    character_name TEXT,
    role TEXT NOT NULL DEFAULT 'cast' CHECK(role IN ('cast', 'crew')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (actor_id) REFERENCES actors(id) ON DELETE CASCADE,
    FOREIGN KEY (media_id) REFERENCES media_items(id) ON DELETE CASCADE,
    UNIQUE(actor_id, media_id, role)
);

-- 标签表 - 用于管理用户自定义标签
CREATE TABLE tags (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE CHECK(length(name) > 0),
    color TEXT, -- 十六进制颜色代码
    description TEXT,
    usage_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 媒体标签关联表
CREATE TABLE media_tags (
    media_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (media_id, tag_id),
    FOREIGN KEY (media_id) REFERENCES media_items(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- 性能优化索引
-- 媒体项目索引
CREATE INDEX idx_media_title ON media_items(title COLLATE NOCASE);
CREATE INDEX idx_media_original_title ON media_items(original_title COLLATE NOCASE);
CREATE INDEX idx_media_year ON media_items(year DESC);
CREATE INDEX idx_media_rating ON media_items(rating DESC);
CREATE INDEX idx_media_type ON media_items(media_type);
CREATE INDEX idx_media_created_at ON media_items(created_at DESC);
CREATE INDEX idx_media_updated_at ON media_items(updated_at DESC);
CREATE INDEX idx_media_release_date ON media_items(release_date DESC);
CREATE INDEX idx_media_language ON media_items(language);

-- 收藏索引
CREATE INDEX idx_collection_media_id ON collections(media_id);
CREATE INDEX idx_collection_added_at ON collections(added_at DESC);
CREATE INDEX idx_collection_watch_status ON collections(watch_status);
CREATE INDEX idx_collection_personal_rating ON collections(personal_rating DESC);
CREATE INDEX idx_collection_is_favorite ON collections(is_favorite);
CREATE INDEX idx_collection_last_watched ON collections(last_watched DESC);

-- 同步状态索引
CREATE INDEX idx_sync_last_sync ON sync_status(last_sync DESC);
CREATE INDEX idx_sync_is_active ON sync_status(is_active);

-- 缓存索引
CREATE INDEX idx_cache_expires_at ON api_cache(expires_at);

-- 搜索历史索引
CREATE INDEX idx_search_history_searched_at ON search_history(searched_at DESC);
CREATE INDEX idx_search_history_query ON search_history(query COLLATE NOCASE);

-- 标签索引
CREATE INDEX idx_tags_name ON tags(name COLLATE NOCASE);
CREATE INDEX idx_tags_usage_count ON tags(usage_count DESC);

-- 演员索引
CREATE INDEX idx_actors_name ON actors(name COLLATE NOCASE);
CREATE INDEX idx_actor_media_actor_id ON actor_media(actor_id);
CREATE INDEX idx_actor_media_media_id ON actor_media(media_id);

-- 媒体标签关联索引
CREATE INDEX idx_media_tags_media_id ON media_tags(media_id);
CREATE INDEX idx_media_tags_tag_id ON media_tags(tag_id);

-- 全文搜索索引 (FTS5) - 独立表模式，避免 content table 兼容性问题
CREATE VIRTUAL TABLE media_search_fts USING fts5(
    media_id,
    title,
    original_title,
    overview
);

-- FTS5 触发器 - 保持搜索索引同步
CREATE TRIGGER media_search_fts_insert AFTER INSERT ON media_items BEGIN
    INSERT INTO media_search_fts(media_id, title, original_title, overview)
    VALUES (new.id, new.title, new.original_title, new.overview);
END;

CREATE TRIGGER media_search_fts_delete AFTER DELETE ON media_items BEGIN
    DELETE FROM media_search_fts WHERE media_id = old.id;
END;

CREATE TRIGGER media_search_fts_update AFTER UPDATE ON media_items BEGIN
    UPDATE media_search_fts SET 
        title = new.title,
        original_title = new.original_title,
        overview = new.overview
    WHERE media_id = new.id;
END;

-- 更新时间戳触发器
CREATE TRIGGER update_media_items_timestamp 
    AFTER UPDATE ON media_items
    FOR EACH ROW
BEGIN
    UPDATE media_items SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER update_user_settings_timestamp 
    AFTER UPDATE ON user_settings
    FOR EACH ROW
BEGIN
    UPDATE user_settings SET updated_at = datetime('now') WHERE key = NEW.key;
END;

-- 插入默认设置
INSERT INTO user_settings (key, value, description) VALUES
    ('theme', 'system', 'App theme preference: light, dark, or system'),
    ('language', 'zh-CN', 'App language preference'),
    ('sync_enabled', 'true', 'Enable data synchronization'),
    ('auto_backup', 'true', 'Enable automatic database backup'),
    ('search_history_enabled', 'true', 'Enable search history tracking'),
    ('default_sort', 'added_date_desc', 'Default sorting for media lists'),
    ('items_per_page', '20', 'Number of items to display per page');

-- 插入默认标签
INSERT INTO tags (id, name, color, description) VALUES
    ('tag_001', '想看', '#2196F3', '计划观看的内容'),
    ('tag_002', '在看', '#4CAF50', '正在观看的内容'),
    ('tag_003', '看过', '#9E9E9E', '已经观看完成的内容'),
    ('tag_004', '推荐', '#FF9800', '值得推荐给他人的内容'),
    ('tag_005', '收藏', '#F44336', '特别喜欢的内容');