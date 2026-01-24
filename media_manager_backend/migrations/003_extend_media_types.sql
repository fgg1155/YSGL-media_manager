-- Migration: Extend media_type to include Censored and Uncensored
-- Version: 1.0.3

-- SQLite doesn't support ALTER TABLE to modify CHECK constraints
-- We need to recreate the table with the new constraint

-- Step 1: Create new table with updated constraint
CREATE TABLE media_items_new (
    id TEXT PRIMARY KEY NOT NULL,
    external_ids TEXT NOT NULL DEFAULT '{}',
    title TEXT NOT NULL CHECK(length(title) > 0),
    original_title TEXT,
    code TEXT, -- 识别号字段
    year INTEGER CHECK(year IS NULL OR (year >= 1800 AND year <= 2100)),
    media_type TEXT NOT NULL CHECK(media_type IN ('Movie', 'Scene', 'Documentary', 'Anime', 'Censored', 'Uncensored')),
    genres TEXT NOT NULL DEFAULT '[]',
    rating REAL CHECK(rating IS NULL OR (rating >= 0.0 AND rating <= 10.0)),
    vote_count INTEGER CHECK(vote_count IS NULL OR vote_count >= 0),
    poster_url TEXT,
    backdrop_url TEXT,
    overview TEXT,
    runtime INTEGER CHECK(runtime IS NULL OR runtime > 0),
    release_date TEXT,
    cast TEXT DEFAULT '[]',
    crew TEXT DEFAULT '[]',
    language TEXT,
    country TEXT,
    budget INTEGER CHECK(budget IS NULL OR budget >= 0),
    revenue INTEGER CHECK(revenue IS NULL OR revenue >= 0),
    status TEXT CHECK(status IS NULL OR status IN ('Released', 'In Production', 'Post Production', 'Planned', 'Canceled')),
    play_links TEXT DEFAULT '[]',
    download_links TEXT DEFAULT '[]',
    preview_urls TEXT DEFAULT '[]',
    preview_video_urls TEXT DEFAULT '[]',
    studio TEXT,
    series TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Step 2: Copy data from old table (handle TvShow -> Scene mapping)
-- Note: code field is new, so we set it to NULL for existing records
INSERT INTO media_items_new (
    id, external_ids, title, original_title, code, year, media_type, genres, rating, vote_count,
    poster_url, backdrop_url, overview, runtime, release_date, "cast", crew, language, country,
    budget, revenue, status, play_links, download_links, preview_urls, preview_video_urls,
    studio, series, created_at, updated_at
)
SELECT 
    id, external_ids, title, original_title, NULL as code, year,
    CASE 
        WHEN media_type = 'TvShow' THEN 'Scene'
        ELSE media_type 
    END as media_type,
    genres, rating, vote_count, poster_url, backdrop_url, overview, runtime, release_date,
    "cast", crew, language, country, budget, revenue, status, play_links, download_links,
    preview_urls, preview_video_urls, studio, series, created_at, updated_at
FROM media_items;

-- Step 3: Drop old table
DROP TABLE media_items;

-- Step 4: Rename new table
ALTER TABLE media_items_new RENAME TO media_items;

-- Step 5: Recreate indexes
CREATE INDEX idx_media_title ON media_items(title COLLATE NOCASE);
CREATE INDEX idx_media_original_title ON media_items(original_title COLLATE NOCASE);
CREATE INDEX idx_media_code ON media_items(code COLLATE NOCASE);
CREATE INDEX idx_media_year ON media_items(year DESC);
CREATE INDEX idx_media_rating ON media_items(rating DESC);
CREATE INDEX idx_media_type ON media_items(media_type);
CREATE INDEX idx_media_created_at ON media_items(created_at DESC);
CREATE INDEX idx_media_updated_at ON media_items(updated_at DESC);
CREATE INDEX idx_media_release_date ON media_items(release_date DESC);
CREATE INDEX idx_media_language ON media_items(language);

-- Step 6: Recreate triggers
CREATE TRIGGER update_media_items_timestamp 
    AFTER UPDATE ON media_items
    FOR EACH ROW
BEGIN
    UPDATE media_items SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- Step 7: Recreate FTS triggers
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
