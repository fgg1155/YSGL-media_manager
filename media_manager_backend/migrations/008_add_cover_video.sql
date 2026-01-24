-- Add cover_video_url field to media_items table
-- cover_video_url: 封面视频（短小的视频缩略图，用于悬停播放）
-- 例如：https://videothumb.gammacdn.com/500x281/254796.mp4

ALTER TABLE media_items ADD COLUMN cover_video_url TEXT;
