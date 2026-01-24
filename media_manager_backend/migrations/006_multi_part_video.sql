-- 多分段视频支持
-- Migration: 006_multi_part_video

-- 创建 media_files 表用于存储多个文件
CREATE TABLE IF NOT EXISTS media_files (
    id TEXT PRIMARY KEY NOT NULL,
    media_id TEXT NOT NULL,
    file_path TEXT NOT NULL UNIQUE,
    file_size INTEGER NOT NULL CHECK(file_size >= 0),
    part_number INTEGER CHECK(part_number IS NULL OR part_number > 0),
    part_label TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (media_id) REFERENCES media_items(id) ON DELETE CASCADE
);

-- 创建索引以优化查询性能
CREATE INDEX IF NOT EXISTS idx_media_files_media_id ON media_files(media_id);
CREATE INDEX IF NOT EXISTS idx_media_files_part_number ON media_files(media_id, part_number);
CREATE INDEX IF NOT EXISTS idx_media_files_file_path ON media_files(file_path);

-- 迁移现有数据：将 media_items 中的 local_file_path 迁移到 media_files 表
-- 只迁移有本地文件路径的记录
INSERT INTO media_files (id, media_id, file_path, file_size, part_number, part_label)
SELECT 
    lower(hex(randomblob(16))) as id,
    id as media_id,
    local_file_path as file_path,
    COALESCE(file_size, 0) as file_size,
    NULL as part_number,
    NULL as part_label
FROM media_items
WHERE local_file_path IS NOT NULL AND local_file_path != '';

-- 注意：保留 media_items 表中的 local_file_path 和 file_size 字段用于向后兼容
-- local_file_path 将存储第一个文件的路径
-- file_size 将存储所有文件的总大小
