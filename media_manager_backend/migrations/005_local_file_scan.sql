-- 添加本地文件扫描相关字段
-- Migration: 005_local_file_scan

-- 为 media_items 表添加本地文件路径字段
ALTER TABLE media_items ADD COLUMN local_file_path TEXT;
ALTER TABLE media_items ADD COLUMN file_size INTEGER;
ALTER TABLE media_items ADD COLUMN last_scanned_at TEXT;
ALTER TABLE media_items ADD COLUMN is_local_only INTEGER DEFAULT 0;

-- 创建扫描历史表
CREATE TABLE IF NOT EXISTS scan_history (
    id TEXT PRIMARY KEY,
    scan_path TEXT NOT NULL,
    scanned_at TEXT NOT NULL,
    total_files INTEGER NOT NULL DEFAULT 0,
    matched_files INTEGER NOT NULL DEFAULT 0,
    created_files INTEGER NOT NULL DEFAULT 0,
    ignored_files INTEGER NOT NULL DEFAULT 0
);

-- 创建忽略文件列表表
CREATE TABLE IF NOT EXISTS ignored_files (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL UNIQUE,
    file_name TEXT NOT NULL,
    ignored_at TEXT NOT NULL,
    reason TEXT
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_media_local_file_path ON media_items(local_file_path);
CREATE INDEX IF NOT EXISTS idx_ignored_files_path ON ignored_files(file_path);
