use async_trait::async_trait;
use sqlx::{Pool, Sqlite};
use anyhow::Result;
use chrono::{DateTime, Utc};

use crate::models::{MediaItem, MediaFile, Collection, SearchFilters};

/// 数据库仓库接口
#[async_trait]
pub trait DatabaseRepository: Send + Sync {
    // 媒体项目操作
    async fn get_media_list(&self, limit: i32, offset: i32) -> Result<Vec<MediaItem>>;
    async fn get_media_list_filtered(&self, limit: i32, offset: i32, filters: &MediaListFilters) -> Result<(Vec<MediaItem>, i64)>;
    async fn get_media_by_id(&self, id: &str) -> Result<Option<MediaItem>>;
    async fn insert_media(&self, media: &MediaItem) -> Result<()>;
    async fn update_media(&self, media: &MediaItem) -> Result<()>;
    async fn delete_media(&self, id: &str) -> Result<()>;
    async fn media_exists(&self, id: &str) -> Result<bool>;
    
    // 收藏操作
    async fn get_collections(&self) -> Result<Vec<Collection>>;
    async fn get_collection_by_media_id(&self, media_id: &str) -> Result<Option<Collection>>;
    async fn add_to_collection(&self, collection: &Collection) -> Result<()>;
    async fn update_collection(&self, collection: &Collection) -> Result<()>;
    async fn remove_from_collection(&self, media_id: &str) -> Result<()>;
    async fn is_in_collection(&self, media_id: &str) -> Result<bool>;
    
    // 搜索操作
    async fn search_media(&self, query: &str) -> Result<Vec<MediaItem>>;
    async fn search_media_with_filters(&self, filters: &SearchFilters) -> Result<Vec<MediaItem>>;
    async fn get_media_count(&self) -> Result<i64>;
    async fn get_collection_count(&self) -> Result<i64>;
    
    // 标签操作
    async fn get_all_tags(&self) -> Result<Vec<Tag>>;
    async fn create_tag(&self, tag: &Tag) -> Result<()>;
    async fn delete_tag(&self, tag_id: &str) -> Result<()>;
    async fn get_media_tags(&self, media_id: &str) -> Result<Vec<Tag>>;
    async fn add_media_tag(&self, media_id: &str, tag_id: &str) -> Result<()>;
    async fn remove_media_tag(&self, media_id: &str, tag_id: &str) -> Result<()>;
    
    // 缓存操作
    async fn get_cache(&self, key: &str) -> Result<Option<String>>;
    async fn set_cache(&self, key: &str, value: &str, expires_at: DateTime<Utc>) -> Result<()>;
    async fn delete_cache(&self, key: &str) -> Result<()>;
    
    // 搜索历史
    async fn add_search_history(&self, query: &str, result_count: i32) -> Result<()>;
    async fn get_search_history(&self, limit: i32) -> Result<Vec<SearchHistoryItem>>;
    async fn clear_search_history(&self) -> Result<()>;
    
    // 文件扫描相关
    async fn update_media_local_path(&self, media_id: &str, file_path: &str) -> Result<()>;
    async fn add_ignored_file(&self, id: &str, file_path: &str, file_name: &str, ignored_at: &str, reason: Option<&str>) -> Result<()>;
    async fn get_ignored_files(&self) -> Result<Vec<IgnoredFile>>;
    async fn remove_ignored_file(&self, id: &str) -> Result<()>;
    async fn get_all_media(&self) -> Result<Vec<MediaItem>>;
    
    // 多文件支持
    async fn save_media_files(&self, files: &[MediaFile]) -> Result<()>;
    async fn get_media_files(&self, media_id: &str) -> Result<Vec<MediaFile>>;
    async fn update_media_file_info(&self, media_id: &str, first_file_path: &str, total_size: i64) -> Result<()>;
    async fn delete_media_files(&self, media_id: &str) -> Result<()>;
}

/// 媒体列表筛选条件
#[derive(Debug, Clone, Default)]
pub struct MediaListFilters {
    pub media_type: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
    pub keyword: Option<String>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub sort_by: String,
    pub sort_order: String,
}

/// SQLite 数据库仓库实现
#[derive(Clone)]
pub struct SqliteRepository {
    pool: Pool<Sqlite>,
}

impl SqliteRepository {
    pub fn new(pool: Pool<Sqlite>) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DatabaseRepository for SqliteRepository {
    async fn get_media_list(&self, limit: i32, offset: i32) -> Result<Vec<MediaItem>> {
        let media_items = sqlx::query_as::<_, MediaItem>(
            "SELECT * FROM media_items ORDER BY created_at DESC LIMIT ? OFFSET ?"
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;
        
        Ok(media_items)
    }
    
    async fn get_media_list_filtered(&self, limit: i32, offset: i32, filters: &MediaListFilters) -> Result<(Vec<MediaItem>, i64)> {
        // 构建 WHERE 子句
        let mut conditions = Vec::new();
        
        if filters.media_type.is_some() {
            conditions.push("media_type = ?");
        }
        if filters.studio.is_some() {
            conditions.push("studio = ?");
        }
        if filters.series.is_some() {
            conditions.push("series = ?");
        }
        if filters.year.is_some() {
            conditions.push("year = ?");
        }
        if filters.genre.is_some() {
            conditions.push("genres LIKE ?");
        }
        if filters.keyword.as_ref().map(|k| !k.is_empty()).unwrap_or(false) {
            conditions.push("(code LIKE ? OR title LIKE ? OR original_title LIKE ? OR overview LIKE ?)");
        }
        
        let where_clause = if conditions.is_empty() {
            String::new()
        } else {
            format!("WHERE {}", conditions.join(" AND "))
        };
        
        // 排序
        let sort_column = match filters.sort_by.as_str() {
            "year" => "year",
            "rating" => "rating",
            "title" => "title",
            "release_date" => "release_date",
            _ => "created_at",
        };
        let sort_order = if filters.sort_order.to_lowercase() == "asc" { "ASC" } else { "DESC" };
        
        // 查询数据
        let query = format!(
            "SELECT * FROM media_items {} ORDER BY {} {} NULLS LAST LIMIT ? OFFSET ?",
            where_clause, sort_column, sort_order
        );
        
        let count_query = format!(
            "SELECT COUNT(*) as count FROM media_items {}",
            where_clause
        );
        
        // 构建动态查询 - 数据查询
        let mut query_builder = sqlx::query_as::<_, MediaItem>(&query);
        
        if let Some(ref media_type) = filters.media_type {
            query_builder = query_builder.bind(media_type);
        }
        if let Some(ref studio) = filters.studio {
            query_builder = query_builder.bind(studio);
        }
        if let Some(ref series) = filters.series {
            query_builder = query_builder.bind(series);
        }
        if let Some(year) = filters.year {
            query_builder = query_builder.bind(year);
        }
        if let Some(ref genre) = filters.genre {
            let like_pattern = format!("%{}%", genre);
            query_builder = query_builder.bind(like_pattern);
        }
        if let Some(ref keyword) = filters.keyword {
            if !keyword.is_empty() {
                let like_pattern = format!("%{}%", keyword);
                query_builder = query_builder.bind(like_pattern.clone()); // code
                query_builder = query_builder.bind(like_pattern.clone()); // title
                query_builder = query_builder.bind(like_pattern.clone()); // original_title
                query_builder = query_builder.bind(like_pattern);         // overview
            }
        }
        query_builder = query_builder.bind(limit).bind(offset);
        
        let media_list = query_builder.fetch_all(&self.pool).await?;
        
        // 构建动态查询 - 计数查询
        let mut count_builder = sqlx::query_scalar::<_, i64>(&count_query);
        
        if let Some(ref media_type) = filters.media_type {
            count_builder = count_builder.bind(media_type);
        }
        if let Some(ref studio) = filters.studio {
            count_builder = count_builder.bind(studio);
        }
        if let Some(ref series) = filters.series {
            count_builder = count_builder.bind(series);
        }
        if let Some(year) = filters.year {
            count_builder = count_builder.bind(year);
        }
        if let Some(ref genre) = filters.genre {
            let like_pattern = format!("%{}%", genre);
            count_builder = count_builder.bind(like_pattern);
        }
        if let Some(ref keyword) = filters.keyword {
            if !keyword.is_empty() {
                let like_pattern = format!("%{}%", keyword);
                count_builder = count_builder.bind(like_pattern.clone()); // code
                count_builder = count_builder.bind(like_pattern.clone()); // title
                count_builder = count_builder.bind(like_pattern.clone()); // original_title
                count_builder = count_builder.bind(like_pattern);         // overview
            }
        }
        
        let total_count = count_builder.fetch_one(&self.pool).await?;
        
        Ok((media_list, total_count))
    }
    
    async fn get_media_by_id(&self, id: &str) -> Result<Option<MediaItem>> {
        let media_item = sqlx::query_as::<_, MediaItem>(
            "SELECT * FROM media_items WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(media_item)
    }
    
    async fn insert_media(&self, media: &MediaItem) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO media_items (
                id, code, external_ids, title, original_title, year, media_type,
                genres, rating, vote_count, poster_url, backdrop_url, overview,
                runtime, release_date, cast, crew, language, country,
                budget, revenue, status, play_links, download_links,
                preview_urls, preview_video_urls, cover_video_url, studio, series, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#
        )
        .bind(&media.id)
        .bind(&media.code)
        .bind(&media.external_ids)
        .bind(&media.title)
        .bind(&media.original_title)
        .bind(media.year)
        .bind(&media.media_type)
        .bind(&media.genres)
        .bind(media.rating)
        .bind(media.vote_count)
        .bind(&media.poster_url)
        .bind(&media.backdrop_url)
        .bind(&media.overview)
        .bind(media.runtime)
        .bind(&media.release_date)
        .bind(&media.cast)
        .bind(&media.crew)
        .bind(&media.language)
        .bind(&media.country)
        .bind(media.budget)
        .bind(media.revenue)
        .bind(&media.status)
        .bind(&media.play_links)
        .bind(&media.download_links)
        .bind(&media.preview_urls)
        .bind(&media.preview_video_urls)
        .bind(&media.cover_video_url)
        .bind(&media.studio)
        .bind(&media.series)
        .bind(&media.created_at)
        .bind(&media.updated_at)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn update_media(&self, media: &MediaItem) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE media_items SET
                code = ?, external_ids = ?, title = ?, original_title = ?, year = ?, media_type = ?,
                genres = ?, rating = ?, vote_count = ?, poster_url = ?, backdrop_url = ?,
                overview = ?, runtime = ?, release_date = ?, cast = ?, crew = ?,
                language = ?, country = ?, budget = ?, revenue = ?, status = ?,
                play_links = ?, download_links = ?, preview_urls = ?, preview_video_urls = ?,
                cover_video_url = ?, studio = ?, series = ?, updated_at = datetime('now')
            WHERE id = ?
            "#
        )
        .bind(&media.code)
        .bind(&media.external_ids)
        .bind(&media.title)
        .bind(&media.original_title)
        .bind(media.year)
        .bind(&media.media_type)
        .bind(&media.genres)
        .bind(media.rating)
        .bind(media.vote_count)
        .bind(&media.poster_url)
        .bind(&media.backdrop_url)
        .bind(&media.overview)
        .bind(media.runtime)
        .bind(&media.release_date)
        .bind(&media.cast)
        .bind(&media.crew)
        .bind(&media.language)
        .bind(&media.country)
        .bind(media.budget)
        .bind(media.revenue)
        .bind(&media.status)
        .bind(&media.play_links)
        .bind(&media.download_links)
        .bind(&media.preview_urls)
        .bind(&media.preview_video_urls)
        .bind(&media.cover_video_url)
        .bind(&media.studio)
        .bind(&media.series)
        .bind(&media.id)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn delete_media(&self, id: &str) -> Result<()> {
        // 先删除关联的收藏记录
        sqlx::query("DELETE FROM collections WHERE media_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        
        // 删除关联的演员记录
        sqlx::query("DELETE FROM actor_media WHERE media_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        
        // 删除关联的标签记录
        sqlx::query("DELETE FROM media_tags WHERE media_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        
        // 删除关联的文件记录
        sqlx::query("DELETE FROM media_files WHERE media_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        
        // 最后删除媒体本身
        sqlx::query("DELETE FROM media_items WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn media_exists(&self, id: &str) -> Result<bool> {
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM media_items WHERE id = ?")
            .bind(id)
            .fetch_one(&self.pool)
            .await?;
        
        Ok(count > 0)
    }
    
    async fn get_collections(&self) -> Result<Vec<Collection>> {
        let collections = sqlx::query_as::<_, Collection>(
            "SELECT * FROM collections ORDER BY added_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(collections)
    }
    
    async fn get_collection_by_media_id(&self, media_id: &str) -> Result<Option<Collection>> {
        let collection = sqlx::query_as::<_, Collection>(
            "SELECT * FROM collections WHERE media_id = ?"
        )
        .bind(media_id)
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(collection)
    }
    
    async fn add_to_collection(&self, collection: &Collection) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO collections (
                id, media_id, user_tags, personal_rating, watch_status,
                watch_progress, notes, is_favorite, added_at, last_watched, completed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#
        )
        .bind(&collection.id)
        .bind(&collection.media_id)
        .bind(&collection.user_tags)
        .bind(collection.personal_rating)
        .bind(&collection.watch_status)
        .bind(collection.watch_progress)
        .bind(&collection.notes)
        .bind(collection.is_favorite)
        .bind(&collection.added_at)
        .bind(&collection.last_watched)
        .bind(&collection.completed_at)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn update_collection(&self, collection: &Collection) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE collections SET
                user_tags = ?, personal_rating = ?, watch_status = ?,
                watch_progress = ?, notes = ?, is_favorite = ?,
                last_watched = ?, completed_at = ?
            WHERE id = ?
            "#
        )
        .bind(&collection.user_tags)
        .bind(collection.personal_rating)
        .bind(&collection.watch_status)
        .bind(collection.watch_progress)
        .bind(&collection.notes)
        .bind(collection.is_favorite)
        .bind(&collection.last_watched)
        .bind(&collection.completed_at)
        .bind(&collection.id)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn remove_from_collection(&self, media_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM collections WHERE media_id = ?")
            .bind(media_id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn is_in_collection(&self, media_id: &str) -> Result<bool> {
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM collections WHERE media_id = ?")
            .bind(media_id)
            .fetch_one(&self.pool)
            .await?;
        
        Ok(count > 0)
    }
    
    async fn search_media(&self, query: &str) -> Result<Vec<MediaItem>> {
        use crate::database::FullTextSearchBuilder;
        
        let search_builder = FullTextSearchBuilder::new(query)
            .with_ranking()
            .with_limit(50);
            
        let media_items = search_builder
            .build()
            .build_query_as::<MediaItem>()
            .fetch_all(&self.pool)
            .await?;
        
        Ok(media_items)
    }
    
    async fn search_media_with_filters(&self, filters: &SearchFilters) -> Result<Vec<MediaItem>> {
        use crate::database::MediaQueryBuilder;
        
        let query_builder = MediaQueryBuilder::new()
            .with_filters(filters)
            .with_collection_filters(filters)
            .with_sorting(filters)
            .with_pagination(filters);
            
        let media_items = query_builder
            .build()
            .build_query_as::<MediaItem>()
            .fetch_all(&self.pool)
            .await?;
        
        Ok(media_items)
    }
    
    async fn get_media_count(&self) -> Result<i64> {
        let count = sqlx::query_scalar("SELECT COUNT(*) FROM media_items")
            .fetch_one(&self.pool)
            .await?;
        
        Ok(count)
    }
    
    async fn get_collection_count(&self) -> Result<i64> {
        let count = sqlx::query_scalar("SELECT COUNT(*) FROM collections")
            .fetch_one(&self.pool)
            .await?;
        
        Ok(count)
    }
    
    // 其他方法的实现...
    async fn get_all_tags(&self) -> Result<Vec<Tag>> {
        let tags = sqlx::query_as::<_, Tag>(
            "SELECT id, name, color, description, usage_count, created_at FROM tags ORDER BY usage_count DESC, name"
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(tags)
    }
    
    async fn create_tag(&self, tag: &Tag) -> Result<()> {
        sqlx::query(
            "INSERT INTO tags (id, name, color, description, usage_count, created_at) VALUES (?, ?, ?, ?, ?, ?)"
        )
        .bind(&tag.id)
        .bind(&tag.name)
        .bind(&tag.color)
        .bind(&tag.description)
        .bind(tag.usage_count)
        .bind(&tag.created_at)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn delete_tag(&self, tag_id: &str) -> Result<()> {
        // 先删除媒体标签关联
        sqlx::query("DELETE FROM media_tags WHERE tag_id = ?")
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
            
        // 再删除标签
        sqlx::query("DELETE FROM tags WHERE id = ?")
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn get_media_tags(&self, media_id: &str) -> Result<Vec<Tag>> {
        let tags = sqlx::query_as::<_, Tag>(
            r#"
            SELECT t.id, t.name, t.color, t.description, t.usage_count, t.created_at
            FROM tags t
            JOIN media_tags mt ON t.id = mt.tag_id
            WHERE mt.media_id = ?
            ORDER BY t.name
            "#
        )
        .bind(media_id)
        .fetch_all(&self.pool)
        .await?;
        
        Ok(tags)
    }
    
    async fn add_media_tag(&self, media_id: &str, tag_id: &str) -> Result<()> {
        // 添加媒体标签关联
        sqlx::query("INSERT OR IGNORE INTO media_tags (media_id, tag_id) VALUES (?, ?)")
            .bind(media_id)
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
            
        // 增加标签使用计数
        sqlx::query("UPDATE tags SET usage_count = usage_count + 1 WHERE id = ?")
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn remove_media_tag(&self, media_id: &str, tag_id: &str) -> Result<()> {
        // 删除媒体标签关联
        let result = sqlx::query("DELETE FROM media_tags WHERE media_id = ? AND tag_id = ?")
            .bind(media_id)
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
            
        // 如果删除成功，减少标签使用计数
        if result.rows_affected() > 0 {
            sqlx::query("UPDATE tags SET usage_count = MAX(0, usage_count - 1) WHERE id = ?")
                .bind(tag_id)
                .execute(&self.pool)
                .await?;
        }
        
        Ok(())
    }
    
    async fn get_cache(&self, key: &str) -> Result<Option<String>> {
        let value = sqlx::query_scalar(
            "SELECT cache_value FROM api_cache WHERE cache_key = ? AND expires_at > datetime('now')"
        )
        .bind(key)
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(value)
    }
    
    async fn set_cache(&self, key: &str, value: &str, expires_at: DateTime<Utc>) -> Result<()> {
        sqlx::query(
            "INSERT OR REPLACE INTO api_cache (cache_key, cache_value, expires_at) VALUES (?, ?, ?)"
        )
        .bind(key)
        .bind(value)
        .bind(expires_at.format("%Y-%m-%d %H:%M:%S").to_string())
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn delete_cache(&self, key: &str) -> Result<()> {
        sqlx::query("DELETE FROM api_cache WHERE cache_key = ?")
            .bind(key)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn add_search_history(&self, query: &str, result_count: i32) -> Result<()> {
        sqlx::query(
            "INSERT INTO search_history (id, query, result_count) VALUES (?, ?, ?)"
        )
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(query)
        .bind(result_count)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn get_search_history(&self, limit: i32) -> Result<Vec<SearchHistoryItem>> {
        let history = sqlx::query_as::<_, SearchHistoryItem>(
            "SELECT id, query, result_count, searched_at FROM search_history ORDER BY searched_at DESC LIMIT ?"
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        
        Ok(history)
    }
    
    async fn clear_search_history(&self) -> Result<()> {
        sqlx::query("DELETE FROM search_history")
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn update_media_local_path(&self, media_id: &str, file_path: &str) -> Result<()> {
        // 获取文件大小
        let file_size = std::fs::metadata(file_path)
            .map(|m| m.len() as i64)
            .unwrap_or(0);
        
        sqlx::query(
            r#"
            UPDATE media_items 
            SET local_file_path = ?, 
                file_size = ?, 
                last_scanned_at = datetime('now')
            WHERE id = ?
            "#
        )
        .bind(file_path)
        .bind(file_size)
        .bind(media_id)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn add_ignored_file(&self, id: &str, file_path: &str, file_name: &str, ignored_at: &str, reason: Option<&str>) -> Result<()> {
        sqlx::query(
            "INSERT OR REPLACE INTO ignored_files (id, file_path, file_name, ignored_at, reason) VALUES (?, ?, ?, ?, ?)"
        )
        .bind(id)
        .bind(file_path)
        .bind(file_name)
        .bind(ignored_at)
        .bind(reason)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn get_ignored_files(&self) -> Result<Vec<IgnoredFile>> {
        let files = sqlx::query_as::<_, IgnoredFile>(
            "SELECT id, file_path, file_name, ignored_at, reason FROM ignored_files ORDER BY ignored_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(files)
    }
    
    async fn remove_ignored_file(&self, id: &str) -> Result<()> {
        sqlx::query("DELETE FROM ignored_files WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    async fn get_all_media(&self) -> Result<Vec<MediaItem>> {
        let media_items = sqlx::query_as::<_, MediaItem>(
            "SELECT * FROM media_items ORDER BY created_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(media_items)
    }
    
    async fn save_media_files(&self, files: &[MediaFile]) -> Result<()> {
        if files.is_empty() {
            return Ok(());
        }
        
        // 批量插入文件记录
        for file in files {
            sqlx::query(
                r#"
                INSERT INTO media_files (id, media_id, file_path, file_size, part_number, part_label, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                "#
            )
            .bind(&file.id)
            .bind(&file.media_id)
            .bind(&file.file_path)
            .bind(file.file_size)
            .bind(file.part_number)
            .bind(&file.part_label)
            .bind(&file.created_at)
            .execute(&self.pool)
            .await?;
        }
        
        Ok(())
    }
    
    async fn get_media_files(&self, media_id: &str) -> Result<Vec<MediaFile>> {
        let files = sqlx::query_as::<_, MediaFile>(
            r#"
            SELECT id, media_id, file_path, file_size, part_number, part_label, created_at
            FROM media_files
            WHERE media_id = ?
            ORDER BY part_number ASC NULLS LAST, part_label ASC
            "#
        )
        .bind(media_id)
        .fetch_all(&self.pool)
        .await?;
        
        Ok(files)
    }
    
    async fn update_media_file_info(&self, media_id: &str, first_file_path: &str, total_size: i64) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE media_items 
            SET local_file_path = ?, 
                file_size = ?, 
                last_scanned_at = datetime('now')
            WHERE id = ?
            "#
        )
        .bind(first_file_path)
        .bind(total_size)
        .bind(media_id)
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    async fn delete_media_files(&self, media_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM media_files WHERE media_id = ?")
            .bind(media_id)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
}

// 辅助数据结构
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Tag {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub description: Option<String>,
    pub usage_count: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct SearchHistoryItem {
    pub id: String,
    pub query: String,
    pub result_count: i32,
    pub searched_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize)]
pub struct IgnoredFile {
    pub id: String,
    pub file_path: String,
    pub file_name: String,
    pub ignored_at: String,
    pub reason: Option<String>,
}