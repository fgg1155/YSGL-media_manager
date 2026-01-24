use std::sync::Arc;
use anyhow::Result;
use chrono::Utc;

use crate::database::{DatabaseRepository, SqliteRepository};
use crate::models::{MediaItem, Collection, SearchFilters, MediaType, WatchStatus};

/// 数据库服务层，封装业务逻辑
pub struct DatabaseService {
    repository: Arc<dyn DatabaseRepository>,
}

impl DatabaseService {
    pub fn new(repository: SqliteRepository) -> Self {
        Self {
            repository: Arc::new(repository),
        }
    }
    
    /// 创建新的媒体项目
    pub async fn create_media(&self, title: String, media_type: MediaType) -> Result<MediaItem> {
        let media = MediaItem::new(title, media_type)
            .map_err(|e| anyhow::anyhow!("Validation error: {:?}", e))?;
        
        // 检查是否已存在相同标题的媒体
        let existing = self.repository.search_media(&media.title).await?;
        if !existing.is_empty() {
            return Err(anyhow::anyhow!("Media with similar title already exists"));
        }
        
        self.repository.insert_media(&media).await?;
        Ok(media)
    }
    
    /// 获取媒体详情
    pub async fn get_media_detail(&self, id: &str) -> Result<Option<MediaItem>> {
        self.repository.get_media_by_id(id).await
    }
    
    /// 更新媒体信息
    pub async fn update_media(&self, mut media: MediaItem) -> Result<()> {
        media.updated_at = Utc::now();
        self.repository.update_media(&media).await
    }
    
    /// 删除媒体项目
    pub async fn delete_media(&self, id: &str) -> Result<()> {
        // 检查是否存在
        if !self.repository.media_exists(id).await? {
            return Err(anyhow::anyhow!("Media not found"));
        }
        
        self.repository.delete_media(id).await
    }
    
    /// 添加到收藏
    pub async fn add_to_collection(&self, media_id: String, watch_status: WatchStatus) -> Result<Collection> {
        // 检查媒体是否存在
        if !self.repository.media_exists(&media_id).await? {
            return Err(anyhow::anyhow!("Media not found"));
        }
        
        // 检查是否已在收藏中
        if self.repository.is_in_collection(&media_id).await? {
            return Err(anyhow::anyhow!("Media already in collection"));
        }
        
        let collection = Collection::new(media_id, watch_status);
        self.repository.add_to_collection(&collection).await?;
        Ok(collection)
    }
    
    /// 更新收藏状态
    pub async fn update_collection(&self, collection_id: &str, watch_status: WatchStatus, progress: Option<f32>) -> Result<()> {
        if let Some(mut collection) = self.repository.get_collection_by_media_id(collection_id).await? {
            collection.set_watch_status(watch_status);
            
            if let Some(p) = progress {
                let _ = collection.update_progress(p);
            }
            
            self.repository.update_collection(&collection).await?;
        } else {
            return Err(anyhow::anyhow!("Collection not found"));
        }
        
        Ok(())
    }
    
    /// 从收藏中移除
    pub async fn remove_from_collection(&self, media_id: &str) -> Result<()> {
        if !self.repository.is_in_collection(media_id).await? {
            return Err(anyhow::anyhow!("Media not in collection"));
        }
        
        self.repository.remove_from_collection(media_id).await
    }
    
    /// 更新收藏状态（通过media_id）
    pub async fn update_collection_status(&self, media_id: &str, watch_status: WatchStatus) -> Result<()> {
        if let Some(mut collection) = self.repository.get_collection_by_media_id(media_id).await? {
            collection.set_watch_status(watch_status);
            self.repository.update_collection(&collection).await?;
            Ok(())
        } else {
            Err(anyhow::anyhow!("Collection not found"))
        }
    }
    
    /// 为收藏添加标签
    pub async fn add_tags_to_collection(&self, media_id: &str, tags: Vec<String>) -> Result<()> {
        if let Some(mut collection) = self.repository.get_collection_by_media_id(media_id).await? {
            for tag in tags {
                collection.add_user_tag(tag).map_err(|e| anyhow::anyhow!("Validation error: {:?}", e))?;
            }
            self.repository.update_collection(&collection).await?;
            Ok(())
        } else {
            Err(anyhow::anyhow!("Collection not found"))
        }
    }
    
    /// 从收藏移除标签
    pub async fn remove_tags_from_collection(&self, media_id: &str, tags: Vec<String>) -> Result<()> {
        if let Some(mut collection) = self.repository.get_collection_by_media_id(media_id).await? {
            for tag in tags {
                collection.remove_user_tag(&tag).map_err(|e| anyhow::anyhow!("Validation error: {:?}", e))?;
            }
            self.repository.update_collection(&collection).await?;
            Ok(())
        } else {
            Err(anyhow::anyhow!("Collection not found"))
        }
    }
    
    /// 搜索媒体
    pub async fn search_media(&self, query: &str) -> Result<Vec<MediaItem>> {
        if query.trim().is_empty() {
            return Ok(Vec::new());
        }
        
        // 记录搜索历史
        let results = self.repository.search_media(query).await?;
        self.repository.add_search_history(query, results.len() as i32).await?;
        
        Ok(results)
    }
    
    /// 高级搜索
    pub async fn search_with_filters(&self, filters: &SearchFilters) -> Result<Vec<MediaItem>> {
        let results = self.repository.search_media_with_filters(filters).await?;
        
        // 如果有查询字符串，记录搜索历史
        if let Some(ref query) = filters.query {
            if !query.trim().is_empty() {
                self.repository.add_search_history(query, results.len() as i32).await?;
            }
        }
        
        Ok(results)
    }
    
    /// 获取分页媒体列表
    pub async fn get_media_list(&self, page: i32, page_size: i32) -> Result<(Vec<MediaItem>, i64)> {
        let offset = (page - 1) * page_size;
        let media_list = self.repository.get_media_list(page_size, offset).await?;
        let total_count = self.repository.get_media_count().await?;
        
        Ok((media_list, total_count))
    }
    
    /// 获取带筛选的分页媒体列表
    pub async fn get_media_list_filtered(
        &self, 
        page: i32, 
        page_size: i32, 
        filters: &crate::api::media::MediaFilters
    ) -> Result<(Vec<MediaItem>, i64)> {
        let offset = (page - 1) * page_size;
        
        // 转换为 repository 的筛选结构
        let repo_filters = crate::database::repository::MediaListFilters {
            media_type: filters.media_type.clone(),
            studio: filters.studio.clone(),
            series: filters.series.clone(),
            keyword: filters.keyword.clone(),
            year: filters.year,
            genre: filters.genre.clone(),
            sort_by: filters.sort_by.clone(),
            sort_order: filters.sort_order.clone(),
        };
        
        self.repository.get_media_list_filtered(page_size, offset, &repo_filters).await
    }
    
    /// 获取收藏列表
    pub async fn get_collections(&self) -> Result<Vec<Collection>> {
        self.repository.get_collections().await
    }
    
    /// 获取统计信息
    pub async fn get_statistics(&self) -> Result<DatabaseStatistics> {
        let media_count = self.repository.get_media_count().await?;
        let collection_count = self.repository.get_collection_count().await?;
        let tags = self.repository.get_all_tags().await?;
        
        Ok(DatabaseStatistics {
            total_media: media_count,
            total_collections: collection_count,
            total_tags: tags.len() as i64,
            popular_tags: tags.into_iter().take(5).collect(),
        })
    }
    
    /// 清理数据
    pub async fn cleanup(&self) -> Result<CleanupResult> {
        // 清理过期缓存 - delete_cache 返回 Result<()>
        let _ = self.repository.delete_cache("").await;
        
        Ok(CleanupResult {
            expired_cache_entries: 0,
            old_search_entries: 0,
        })
    }
}

/// 数据库统计信息
#[derive(Debug)]
pub struct DatabaseStatistics {
    pub total_media: i64,
    pub total_collections: i64,
    pub total_tags: i64,
    pub popular_tags: Vec<crate::database::repository::Tag>,
}

/// 清理结果
#[derive(Debug)]
pub struct CleanupResult {
    pub expired_cache_entries: u64,
    pub old_search_entries: u64,
}