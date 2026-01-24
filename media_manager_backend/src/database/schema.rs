use sqlx::{Pool, Sqlite, Row};
use anyhow::Result;

/// 验证数据库schema完整性
pub async fn verify_schema(pool: &Pool<Sqlite>) -> Result<()> {
    // 检查所有必需的表是否存在
    let required_tables = vec![
        "media_items",
        "collections", 
        "user_settings",
        "sync_status",
        "api_cache",
        "search_history",
        "tags",
        "media_tags",
        "media_search_fts",
    ];

    for table in required_tables {
        let exists = sqlx::query("SELECT name FROM sqlite_master WHERE type='table' AND name=?")
            .bind(table)
            .fetch_optional(pool)
            .await?;
            
        if exists.is_none() {
            return Err(anyhow::anyhow!("Required table '{}' does not exist", table));
        }
    }

    // 检查关键索引是否存在
    let required_indexes = vec![
        "idx_media_title",
        "idx_media_year", 
        "idx_media_rating",
        "idx_collection_media_id",
        "idx_collection_added_at",
    ];

    for index in required_indexes {
        let exists = sqlx::query("SELECT name FROM sqlite_master WHERE type='index' AND name=?")
            .bind(index)
            .fetch_optional(pool)
            .await?;
            
        if exists.is_none() {
            return Err(anyhow::anyhow!("Required index '{}' does not exist", index));
        }
    }

    // 验证外键约束是否启用
    let foreign_keys_enabled: i32 = sqlx::query("PRAGMA foreign_keys")
        .fetch_one(pool)
        .await?
        .get(0);
        
    if foreign_keys_enabled != 1 {
        tracing::warn!("Foreign key constraints are not enabled");
    }

    tracing::info!("Database schema verification completed successfully");
    Ok(())
}

/// 获取数据库统计信息
pub async fn get_database_stats(pool: &Pool<Sqlite>) -> Result<DatabaseStats> {
    let media_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM media_items")
        .fetch_one(pool)
        .await?;

    let collection_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM collections")
        .fetch_one(pool)
        .await?;

    let tag_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM tags")
        .fetch_one(pool)
        .await?;

    let cache_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM api_cache")
        .fetch_one(pool)
        .await?;

    // 获取数据库文件大小
    let db_size: i64 = sqlx::query_scalar("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
        .fetch_one(pool)
        .await?;

    Ok(DatabaseStats {
        media_count,
        collection_count,
        tag_count,
        cache_count,
        database_size_bytes: db_size,
    })
}

/// 清理过期的缓存数据
pub async fn cleanup_expired_cache(pool: &Pool<Sqlite>) -> Result<u64> {
    let result = sqlx::query("DELETE FROM api_cache WHERE expires_at < datetime('now')")
        .execute(pool)
        .await?;

    tracing::info!("Cleaned up {} expired cache entries", result.rows_affected());
    Ok(result.rows_affected())
}

/// 数据库统计信息
#[derive(Debug)]
pub struct DatabaseStats {
    pub media_count: i64,
    pub collection_count: i64,
    pub tag_count: i64,
    pub cache_count: i64,
    pub database_size_bytes: i64,
}

impl DatabaseStats {
    pub fn database_size_mb(&self) -> f64 {
        self.database_size_bytes as f64 / (1024.0 * 1024.0)
    }
}