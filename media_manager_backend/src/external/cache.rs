use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};

use crate::models::MediaItem;

/// 缓存条目
#[derive(Debug, Clone)]
struct CacheEntry<T> {
    data: T,
    created_at: Instant,
    ttl: Duration,
}

impl<T> CacheEntry<T> {
    fn new(data: T, ttl: Duration) -> Self {
        Self {
            data,
            created_at: Instant::now(),
            ttl,
        }
    }
    
    fn is_expired(&self) -> bool {
        self.created_at.elapsed() > self.ttl
    }
}

/// 内存缓存实现
#[derive(Debug, Clone)]
pub struct MemoryCache<T> {
    cache: Arc<RwLock<HashMap<String, CacheEntry<T>>>>,
    default_ttl: Duration,
}

impl<T: Clone> MemoryCache<T> {
    pub fn new(default_ttl: Duration) -> Self {
        Self {
            cache: Arc::new(RwLock::new(HashMap::new())),
            default_ttl,
        }
    }
    
    pub fn get(&self, key: &str) -> Option<T> {
        let cache = self.cache.read().ok()?;
        let entry = cache.get(key)?;
        
        if entry.is_expired() {
            drop(cache);
            self.remove(key);
            None
        } else {
            Some(entry.data.clone())
        }
    }
    
    pub fn set(&self, key: String, value: T) {
        self.set_with_ttl(key, value, self.default_ttl);
    }
    
    pub fn set_with_ttl(&self, key: String, value: T, ttl: Duration) {
        if let Ok(mut cache) = self.cache.write() {
            cache.insert(key, CacheEntry::new(value, ttl));
        }
    }
    
    pub fn remove(&self, key: &str) {
        if let Ok(mut cache) = self.cache.write() {
            cache.remove(key);
        }
    }
    
    pub fn clear(&self) {
        if let Ok(mut cache) = self.cache.write() {
            cache.clear();
        }
    }
    
    pub fn cleanup_expired(&self) {
        if let Ok(mut cache) = self.cache.write() {
            cache.retain(|_, entry| !entry.is_expired());
        }
    }
    
    pub fn size(&self) -> usize {
        self.cache.read().map(|c| c.len()).unwrap_or(0)
    }
}

/// TMDB API响应缓存
#[derive(Debug, Clone)]
pub struct TmdbCache {
    search_cache: MemoryCache<Vec<MediaItem>>,
    details_cache: MemoryCache<MediaItem>,
    popular_cache: MemoryCache<Vec<MediaItem>>,
}

impl TmdbCache {
    pub fn new() -> Self {
        Self {
            // 搜索结果缓存30分钟
            search_cache: MemoryCache::new(Duration::from_secs(30 * 60)),
            // 详情缓存2小时
            details_cache: MemoryCache::new(Duration::from_secs(2 * 60 * 60)),
            // 热门内容缓存1小时
            popular_cache: MemoryCache::new(Duration::from_secs(60 * 60)),
        }
    }
    
    /// 生成搜索缓存键
    fn search_cache_key(&self, query: &str, media_type: &str, page: u32) -> String {
        format!("search:{}:{}:{}", media_type, query, page)
    }
    
    /// 生成详情缓存键
    fn details_cache_key(&self, media_type: &str, id: u32) -> String {
        format!("details:{}:{}", media_type, id)
    }
    
    /// 生成热门内容缓存键
    fn popular_cache_key(&self, media_type: &str, page: u32) -> String {
        format!("popular:{}:{}", media_type, page)
    }
    
    /// 获取搜索结果缓存
    pub fn get_search_results(&self, query: &str, media_type: &str, page: u32) -> Option<Vec<MediaItem>> {
        let key = self.search_cache_key(query, media_type, page);
        self.search_cache.get(&key)
    }
    
    /// 设置搜索结果缓存
    pub fn set_search_results(&self, query: &str, media_type: &str, page: u32, results: Vec<MediaItem>) {
        let key = self.search_cache_key(query, media_type, page);
        self.search_cache.set(key, results);
    }
    
    /// 获取详情缓存
    pub fn get_details(&self, media_type: &str, id: u32) -> Option<MediaItem> {
        let key = self.details_cache_key(media_type, id);
        self.details_cache.get(&key)
    }
    
    /// 设置详情缓存
    pub fn set_details(&self, media_type: &str, id: u32, details: MediaItem) {
        let key = self.details_cache_key(media_type, id);
        self.details_cache.set(key, details);
    }
    
    /// 获取热门内容缓存
    pub fn get_popular(&self, media_type: &str, page: u32) -> Option<Vec<MediaItem>> {
        let key = self.popular_cache_key(media_type, page);
        self.popular_cache.get(&key)
    }
    
    /// 设置热门内容缓存
    pub fn set_popular(&self, media_type: &str, page: u32, results: Vec<MediaItem>) {
        let key = self.popular_cache_key(media_type, page);
        self.popular_cache.set(key, results);
    }
    
    /// 清理过期缓存
    pub fn cleanup_expired(&self) {
        self.search_cache.cleanup_expired();
        self.details_cache.cleanup_expired();
        self.popular_cache.cleanup_expired();
    }
    
    /// 清空所有缓存
    pub fn clear_all(&self) {
        self.search_cache.clear();
        self.details_cache.clear();
        self.popular_cache.clear();
    }
    
    /// 获取缓存统计信息
    pub fn get_stats(&self) -> CacheStats {
        CacheStats {
            search_cache_size: self.search_cache.size(),
            details_cache_size: self.details_cache.size(),
            popular_cache_size: self.popular_cache.size(),
        }
    }
}

impl Default for TmdbCache {
    fn default() -> Self {
        Self::new()
    }
}

/// 缓存统计信息
#[derive(Debug, Serialize, Deserialize)]
pub struct CacheStats {
    pub search_cache_size: usize,
    pub details_cache_size: usize,
    pub popular_cache_size: usize,
}

/// 缓存清理任务
pub struct CacheCleanupTask {
    cache: TmdbCache,
    interval: Duration,
}

impl CacheCleanupTask {
    pub fn new(cache: TmdbCache, interval: Duration) -> Self {
        Self { cache, interval }
    }
    
    /// 启动定期清理任务
    pub async fn start(self) {
        let mut interval = tokio::time::interval(self.interval);
        
        loop {
            interval.tick().await;
            self.cache.cleanup_expired();
            tracing::debug!("Cache cleanup completed. Stats: {:?}", self.cache.get_stats());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    
    #[test]
    fn test_memory_cache_basic_operations() {
        let cache = MemoryCache::new(Duration::from_secs(1));
        
        // 测试设置和获取
        cache.set("key1".to_string(), "value1".to_string());
        assert_eq!(cache.get("key1"), Some("value1".to_string()));
        
        // 测试不存在的键
        assert_eq!(cache.get("nonexistent"), None);
        
        // 测试删除
        cache.remove("key1");
        assert_eq!(cache.get("key1"), None);
    }
    
    #[test]
    fn test_memory_cache_expiration() {
        let cache = MemoryCache::new(Duration::from_millis(100));
        
        cache.set("key1".to_string(), "value1".to_string());
        assert_eq!(cache.get("key1"), Some("value1".to_string()));
        
        // 等待过期
        thread::sleep(Duration::from_millis(150));
        assert_eq!(cache.get("key1"), None);
    }
    
    #[test]
    fn test_tmdb_cache_operations() {
        let cache = TmdbCache::new();
        
        // 创建测试数据
        let media_items = vec![
            // 这里需要创建实际的MediaItem实例进行测试
        ];
        
        // 测试搜索缓存
        cache.set_search_results("test", "movie", 1, media_items.clone());
        let cached_results = cache.get_search_results("test", "movie", 1);
        assert!(cached_results.is_some());
        
        // 测试缓存统计
        let stats = cache.get_stats();
        assert!(stats.search_cache_size > 0);
    }
}