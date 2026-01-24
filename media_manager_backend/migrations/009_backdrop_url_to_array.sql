-- Migration: 009_backdrop_url_to_array
-- Convert backdrop_url from single string to JSON array

-- Step 1: Add temporary column
ALTER TABLE media_items ADD COLUMN backdrop_url_new TEXT DEFAULT '[]';

-- Step 2: Migrate data
UPDATE media_items 
SET backdrop_url_new = CASE 
    WHEN backdrop_url IS NOT NULL AND backdrop_url != '' THEN '["' || backdrop_url || '"]'
    ELSE '[]'
END;

-- Step 3: Drop old column
ALTER TABLE media_items DROP COLUMN backdrop_url;

-- Step 4: Rename new column
ALTER TABLE media_items RENAME COLUMN backdrop_url_new TO backdrop_url;
