use sqlx::{sqlite::{SqlitePoolOptions, SqliteConnectOptions}, Pool, Sqlite};
use anyhow::Result;
use std::str::FromStr;

pub mod schema;
pub mod repository;
pub mod query_builder;
pub mod actor_repository;
pub mod studio_repository;

pub use repository::{DatabaseRepository, SqliteRepository};
pub use query_builder::{MediaQueryBuilder, FullTextSearchBuilder};
pub use actor_repository::*;
pub use studio_repository::*;

#[derive(Clone)]
pub struct Database {
    pool: Pool<Sqlite>,
    repository: SqliteRepository,
}

impl Database {
    pub async fn new() -> Result<Self> {
        // 支持环境变量配置，默认使用相对路径 ./media_manager.db
        let database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "sqlite:./media_manager.db?mode=rwc".to_string());
        
        tracing::info!("🗄️  Connecting to database: {}", database_url);
        
        // 配置 SQLite 连接选项
        let connect_options = SqliteConnectOptions::from_str(&database_url)?
            .busy_timeout(std::time::Duration::from_secs(30));  // 设置忙等待超时
        
        // 创建连接池，限制最大连接数为1以避免锁定问题
        let pool = SqlitePoolOptions::new()
            .max_connections(1)  // SQLite 单写入者，限制为1个连接
            .connect_with(connect_options)
            .await?;
        
        // Run migrations
        tracing::info!("Running database migrations...");
        sqlx::migrate!("./migrations").run(&pool).await?;
        
        // Verify schema integrity
        schema::verify_schema(&pool).await?;
        
        // Clean up expired cache entries
        schema::cleanup_expired_cache(&pool).await?;
        
        // Log database statistics
        let stats = schema::get_database_stats(&pool).await?;
        tracing::info!(
            "Database initialized - Media: {}, Collections: {}, Tags: {}, Size: {:.2} MB",
            stats.media_count,
            stats.collection_count, 
            stats.tag_count,
            stats.database_size_mb()
        );
        
        let repository = SqliteRepository::new(pool.clone());
        
        Ok(Self { pool, repository })
    }
    
    pub fn pool(&self) -> &Pool<Sqlite> {
        &self.pool
    }
    
    pub fn repository(&self) -> &SqliteRepository {
        &self.repository
    }
    
    /// 获取数据库统计信息
    pub async fn get_stats(&self) -> Result<schema::DatabaseStats> {
        schema::get_database_stats(&self.pool).await
    }
    
    /// 清理过期缓存
    pub async fn cleanup_cache(&self) -> Result<u64> {
        schema::cleanup_expired_cache(&self.pool).await
    }
    
    /// 验证数据库完整性
    pub async fn verify_integrity(&self) -> Result<()> {
        schema::verify_schema(&self.pool).await
    }
}