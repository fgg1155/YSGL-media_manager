-- Add avatar_url and poster_url fields to actors table
-- avatar_url: 演员头像（用于列表/卡片显示，小图）
-- poster_url: 演员封面（类似海报的竖版图）
-- photo_url: 保留作为演员写真/照片（高质量大图）
-- backdrop_url: 保持不变，背景图（用于详情页背景）

ALTER TABLE actors ADD COLUMN avatar_url TEXT;
ALTER TABLE actors ADD COLUMN poster_url TEXT;
