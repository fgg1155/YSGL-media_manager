-- 厂商和系列层级管理
-- Version: 1.1.0

-- 厂商表
CREATE TABLE IF NOT EXISTS studios (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE CHECK(length(name) > 0),
    logo_url TEXT,
    description TEXT,
    media_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 系列表（关联厂商）
CREATE TABLE IF NOT EXISTS series (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK(length(name) > 0),
    studio_id TEXT,  -- 可为空，表示未分类厂商
    description TEXT,
    cover_url TEXT,
    media_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (studio_id) REFERENCES studios(id) ON DELETE SET NULL
);

-- 系列名在同一厂商下唯一（允许不同厂商有同名系列）
CREATE UNIQUE INDEX IF NOT EXISTS idx_series_name_studio ON series(name, COALESCE(studio_id, ''));

-- 添加外键字段到 media_items（保留原有文本字段用于兼容）
-- SQLite 不支持 ALTER TABLE ADD CONSTRAINT，所以我们用触发器来维护关系

-- 厂商索引
CREATE INDEX IF NOT EXISTS idx_studios_name ON studios(name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_studios_media_count ON studios(media_count DESC);

-- 系列索引
CREATE INDEX IF NOT EXISTS idx_series_name ON series(name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_series_studio_id ON series(studio_id);
CREATE INDEX IF NOT EXISTS idx_series_media_count ON series(media_count DESC);

-- 媒体表的厂商和系列索引
CREATE INDEX IF NOT EXISTS idx_media_studio ON media_items(studio COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_media_series ON media_items(series COLLATE NOCASE);

-- 更新厂商时间戳触发器
CREATE TRIGGER IF NOT EXISTS update_studios_timestamp 
    AFTER UPDATE ON studios
    FOR EACH ROW
BEGIN
    UPDATE studios SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- 更新系列时间戳触发器
CREATE TRIGGER IF NOT EXISTS update_series_timestamp 
    AFTER UPDATE ON series
    FOR EACH ROW
BEGIN
    UPDATE series SET updated_at = datetime('now') WHERE id = NEW.id;
END;
