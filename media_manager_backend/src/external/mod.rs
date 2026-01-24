pub mod tmdb;
pub mod cache;

use anyhow::Result;
pub use tmdb::{TmdbClient, TmdbConverter};
pub use cache::{TmdbCache, CacheStats};

use crate::models::MediaItem;

#[derive(Clone)]
pub struct ExternalApiClient {
    tmdb_client: Option<TmdbClient>,
    pub cache: TmdbCache,
}

impl ExternalApiClient {
    pub fn new() -> Self {
        let tmdb_client = std::env::var("TMDB_API_KEY")
            .ok()
            .map(|api_key| TmdbClient::new(api_key));
        
        Self {
            tmdb_client,
            cache: TmdbCache::new(),
        }
    }
    
    /// 搜索电影并转换为MediaItem（带缓存）
    pub async fn search_movies(&self, query: &str, page: Option<u32>) -> Result<Vec<MediaItem>> {
        let page = page.unwrap_or(1);
        
        // 检查缓存
        if let Some(cached_results) = self.cache.get_search_results(query, "movie", page) {
            tracing::debug!("Cache hit for movie search: {} (page {})", query, page);
            return Ok(cached_results);
        }
        
        if let Some(ref client) = self.tmdb_client {
            let response = client.search_movies(query, Some(page)).await?;
            let mut media_items = Vec::new();
            
            for movie in response.results {
                match TmdbConverter::movie_to_media_item(&movie, client) {
                    Ok(media_item) => media_items.push(media_item),
                    Err(e) => tracing::warn!("Failed to convert movie {}: {}", movie.title, e),
                }
            }
            
            // 缓存结果
            self.cache.set_search_results(query, "movie", page, media_items.clone());
            tracing::debug!("Cached movie search results: {} (page {})", query, page);
            
            Ok(media_items)
        } else {
            Err(anyhow::anyhow!("TMDB API key not configured"))
        }
    }
    
    /// 搜索电视剧并转换为MediaItem（带缓存）
    pub async fn search_tv_shows(&self, query: &str, page: Option<u32>) -> Result<Vec<MediaItem>> {
        let page = page.unwrap_or(1);
        
        // 检查缓存
        if let Some(cached_results) = self.cache.get_search_results(query, "tv", page) {
            tracing::debug!("Cache hit for TV search: {} (page {})", query, page);
            return Ok(cached_results);
        }
        
        if let Some(ref client) = self.tmdb_client {
            let response = client.search_tv_shows(query, Some(page)).await?;
            let mut media_items = Vec::new();
            
            for scene in response.results {
                match TmdbConverter::scene_to_media_item(&scene, client) {
                    Ok(media_item) => media_items.push(media_item),
                    Err(e) => tracing::warn!("Failed to convert scene {}: {}", scene.name, e),
                }
            }
            
            // 缓存结果
            self.cache.set_search_results(query, "tv", page, media_items.clone());
            tracing::debug!("Cached TV search results: {} (page {})", query, page);
            
            Ok(media_items)
        } else {
            Err(anyhow::anyhow!("TMDB API key not configured"))
        }
    }
    
    /// 获取电影详情并转换为MediaItem（带缓存）
    pub async fn get_movie_details(&self, tmdb_id: u32) -> Result<MediaItem> {
        // 检查缓存
        if let Some(cached_details) = self.cache.get_details("movie", tmdb_id) {
            tracing::debug!("Cache hit for movie details: {}", tmdb_id);
            return Ok(cached_details);
        }
        
        if let Some(ref client) = self.tmdb_client {
            let details = client.get_movie_details(tmdb_id).await?;
            let media_item = TmdbConverter::movie_details_to_media_item(&details, client)?;
            
            // 缓存结果
            self.cache.set_details("movie", tmdb_id, media_item.clone());
            tracing::debug!("Cached movie details: {}", tmdb_id);
            
            Ok(media_item)
        } else {
            Err(anyhow::anyhow!("TMDB API key not configured"))
        }
    }
    
    /// 获取电视剧详情并转换为MediaItem（带缓存）
    pub async fn get_tv_details(&self, tmdb_id: u32) -> Result<MediaItem> {
        // 检查缓存
        if let Some(cached_details) = self.cache.get_details("tv", tmdb_id) {
            tracing::debug!("Cache hit for TV details: {}", tmdb_id);
            return Ok(cached_details);
        }
        
        if let Some(ref client) = self.tmdb_client {
            let details = client.get_tv_details(tmdb_id).await?;
            let media_item = TmdbConverter::tv_details_to_media_item(&details, client)?;
            
            // 缓存结果
            self.cache.set_details("tv", tmdb_id, media_item.clone());
            tracing::debug!("Cached TV details: {}", tmdb_id);
            
            Ok(media_item)
        } else {
            Err(anyhow::anyhow!("TMDB API key not configured"))
        }
    }
    
    /// 获取热门电影（带缓存）
    pub async fn get_popular_movies(&self, page: Option<u32>) -> Result<Vec<MediaItem>> {
        let page = page.unwrap_or(1);
        
        // 检查缓存
        if let Some(cached_results) = self.cache.get_popular("movie", page) {
            tracing::debug!("Cache hit for popular movies (page {})", page);
            return Ok(cached_results);
        }
        
        if let Some(ref client) = self.tmdb_client {
            let response = client.get_popular_movies(Some(page)).await?;
            let mut media_items = Vec::new();
            
            for movie in response.results {
                match TmdbConverter::movie_to_media_item(&movie, client) {
                    Ok(media_item) => media_items.push(media_item),
                    Err(e) => tracing::warn!("Failed to convert popular movie {}: {}", movie.title, e),
                }
            }
            
            // 缓存结果
            self.cache.set_popular("movie", page, media_items.clone());
            tracing::debug!("Cached popular movies (page {})", page);
            
            Ok(media_items)
        } else {
            Err(anyhow::anyhow!("TMDB API key not configured"))
        }
    }
    
    /// 获取热门电视剧（带缓存）
    pub async fn get_popular_tv_shows(&self, page: Option<u32>) -> Result<Vec<MediaItem>> {
        let page = page.unwrap_or(1);
        
        // 检查缓存
        if let Some(cached_results) = self.cache.get_popular("tv", page) {
            tracing::debug!("Cache hit for popular TV shows (page {})", page);
            return Ok(cached_results);
        }
        
        if let Some(ref client) = self.tmdb_client {
            let response = client.get_popular_tv_shows(Some(page)).await?;
            let mut media_items = Vec::new();
            
            for scene in response.results {
                match TmdbConverter::scene_to_media_item(&scene, client) {
                    Ok(media_item) => media_items.push(media_item),
                    Err(e) => tracing::warn!("Failed to convert popular scene {}: {}", scene.name, e),
                }
            }
            
            // 缓存结果
            self.cache.set_popular("tv", page, media_items.clone());
            tracing::debug!("Cached popular TV shows (page {})", page);
            
            Ok(media_items)
        } else {
            Err(anyhow::anyhow!("TMDB API key not configured"))
        }
    }
    
    /// 检查TMDB客户端是否可用
    pub fn is_tmdb_available(&self) -> bool {
        self.tmdb_client.is_some()
    }
    
    /// 获取缓存统计信息
    pub fn get_cache_stats(&self) -> CacheStats {
        self.cache.get_stats()
    }
    
    /// 清理过期缓存
    pub fn cleanup_cache(&self) {
        self.cache.cleanup_expired();
    }
    
    /// 清空所有缓存
    pub fn clear_cache(&self) {
        self.cache.clear_all();
    }
}