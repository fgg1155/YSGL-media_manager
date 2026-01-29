-- Migration: 010_add_scraper_name
-- 添加 scraper_name 字段用于缓存统计和管理
-- 记录媒体是由哪个刮削器刮削的

-- 添加 scraper_name 字段
ALTER TABLE media_items ADD COLUMN scraper_name TEXT;

-- 为现有数据设置默认值（未知来源）
UPDATE media_items SET scraper_name = 'unknown' WHERE scraper_name IS NULL;

-- 创建索引以优化按刮削器查询
CREATE INDEX idx_media_scraper_name ON media_items(scraper_name);
