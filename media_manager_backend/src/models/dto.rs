use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

use super::{MediaItem, Collection, MediaType, WatchStatus, Person, ExternalIds, PlayLink, DownloadLink};

/// 媒体项目响应DTO
#[derive(Debug, Serialize, Deserialize)]
pub struct MediaItemResponse {
    pub id: String,
    pub code: Option<String>,  // 识别号/识别码
    pub title: String,
    pub original_title: Option<String>,
    pub year: Option<i32>,
    pub media_type: MediaType,
    pub genres: Vec<String>,
    pub rating: Option<f32>,
    pub vote_count: Option<i32>,
    pub poster_url: Option<String>,
    pub backdrop_url: Vec<String>, // 支持多个背景图
    pub overview: Option<String>,
    pub runtime: Option<i32>,
    pub release_date: Option<String>,
    pub cast: Vec<Person>,
    pub crew: Vec<Person>,
    pub language: Option<String>,
    pub country: Option<String>,
    pub budget: Option<i64>,
    pub revenue: Option<i64>,
    pub status: Option<String>,
    pub external_ids: ExternalIds,
    pub play_links: Vec<PlayLink>,
    pub download_links: Vec<DownloadLink>,
    pub preview_urls: Vec<String>,
    pub preview_video_urls: Vec<serde_json::Value>,  // 支持结构化数据
    pub cover_video_url: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    
    // 计算字段
    pub display_title: String,
    pub year_string: String,
    pub rating_string: String,
    pub runtime_string: String,
}

impl From<MediaItem> for MediaItemResponse {
    fn from(item: MediaItem) -> Self {
        Self {
            display_title: item.display_title().to_string(),
            year_string: item.year_string(),
            rating_string: item.rating_string(),
            runtime_string: item.runtime_string(),
            external_ids: item.get_external_ids().unwrap_or_default(),
            media_type: item.get_media_type().unwrap_or(MediaType::Movie),
            genres: item.get_genres().unwrap_or_default(),
            cast: item.get_cast().unwrap_or_default(),
            crew: item.get_crew().unwrap_or_default(),
            play_links: item.get_play_links().unwrap_or_default(),
            download_links: item.get_download_links().unwrap_or_default(),
            preview_urls: item.get_preview_urls().unwrap_or_default(),
            preview_video_urls: item.preview_video_urls.as_ref()
                .and_then(|s| serde_json::from_str(s).ok())
                .unwrap_or_else(|| vec![]),
            cover_video_url: item.cover_video_url,
            id: item.id,
            code: item.code,  // 添加 code 字段映射
            title: item.title,
            original_title: item.original_title,
            year: item.year,
            rating: item.rating,
            vote_count: item.vote_count,
            poster_url: item.poster_url,
            backdrop_url: item.backdrop_url.as_ref()
                .and_then(|s| serde_json::from_str(s).ok())
                .unwrap_or_else(|| vec![]),
            overview: item.overview,
            runtime: item.runtime,
            release_date: item.release_date,
            language: item.language,
            country: item.country,
            budget: item.budget,
            revenue: item.revenue,
            status: item.status,
            studio: item.studio,
            series: item.series,
            created_at: item.created_at,
            updated_at: item.updated_at,
        }
    }
}

/// 收藏响应DTO
#[derive(Debug, Serialize, Deserialize)]
pub struct CollectionResponse {
    pub id: String,
    pub media_id: String,
    pub user_tags: Vec<String>,
    pub personal_rating: Option<f32>,
    pub watch_status: WatchStatus,
    pub watch_progress: Option<f32>,
    pub notes: Option<String>,
    pub is_favorite: bool,
    pub added_at: DateTime<Utc>,
    pub last_watched: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    
    // 计算字段
    pub status_display: String,
    pub rating_display: String,
    pub progress_percentage: i32,
    pub added_time_display: String,
    pub is_completed: bool,
    pub is_watching: bool,
}

impl From<Collection> for CollectionResponse {
    fn from(collection: Collection) -> Self {
        Self {
            status_display: collection.status_display().to_string(),
            rating_display: collection.rating_display(),
            progress_percentage: collection.progress_percentage(),
            added_time_display: collection.added_time_display(),
            is_completed: collection.is_completed(),
            is_watching: collection.is_watching(),
            watch_status: collection.get_watch_status().unwrap_or(WatchStatus::WantToWatch),
            user_tags: collection.get_user_tags().unwrap_or_default(),
            id: collection.id,
            media_id: collection.media_id,
            personal_rating: collection.personal_rating,
            watch_progress: collection.watch_progress,
            notes: collection.notes,
            is_favorite: collection.is_favorite,
            added_at: collection.added_at,
            last_watched: collection.last_watched,
            completed_at: collection.completed_at,
        }
    }
}

/// 媒体项目与收藏的组合响应
#[derive(Debug, Serialize, Deserialize)]
pub struct MediaWithCollectionResponse {
    pub media: MediaItemResponse,
    pub collection: Option<CollectionResponse>,
}

/// 分页响应
#[derive(Debug, Serialize, Deserialize)]
pub struct PaginatedResponse<T> {
    pub items: Vec<T>,
    pub total: i64,
    pub page: i32,
    pub page_size: i32,
    pub total_pages: i32,
    pub has_next: bool,
    pub has_prev: bool,
}

impl<T> PaginatedResponse<T> {
    pub fn new(items: Vec<T>, total: i64, page: i32, page_size: i32) -> Self {
        let total_pages = ((total as f64) / (page_size as f64)).ceil() as i32;
        
        Self {
            items,
            total,
            page,
            page_size,
            total_pages,
            has_next: page < total_pages,
            has_prev: page > 1,
        }
    }
}

/// 搜索响应
#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResponse {
    pub results: Vec<MediaItemResponse>,
    pub total: i64,
    pub query: String,
    pub took_ms: u64,
}

/// 统计信息响应
#[derive(Debug, Serialize, Deserialize)]
pub struct StatsResponse {
    pub total_media: i64,
    pub total_collections: i64,
    pub total_tags: i64,
    pub database_size_mb: f64,
    pub cache_entries: i64,
    pub popular_tags: Vec<TagInfo>,
    pub media_by_type: Vec<MediaTypeCount>,
    pub collections_by_status: Vec<StatusCount>,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TagInfo {
    pub name: String,
    pub usage_count: i32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MediaTypeCount {
    pub media_type: MediaType,
    pub count: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatusCount {
    pub status: WatchStatus,
    pub count: i64,
}

/// API错误响应
#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
    pub message: String,
    pub timestamp: DateTime<Utc>,
}

impl ErrorResponse {
    pub fn new(error: String, message: String) -> Self {
        Self {
            error,
            message,
            timestamp: Utc::now(),
        }
    }
    
    pub fn validation_error(message: String) -> Self {
        Self::new("ValidationError".to_string(), message)
    }
    
    pub fn not_found(resource: &str) -> Self {
        Self::new(
            "NotFound".to_string(),
            format!("{} not found", resource),
        )
    }
    
    pub fn internal_error() -> Self {
        Self::new(
            "InternalError".to_string(),
            "An internal server error occurred".to_string(),
        )
    }
}

/// 成功响应
#[derive(Debug, Serialize, Deserialize)]
pub struct SuccessResponse {
    pub success: bool,
    pub message: String,
    pub timestamp: DateTime<Utc>,
}

impl SuccessResponse {
    pub fn new(message: String) -> Self {
        Self {
            success: true,
            message,
            timestamp: Utc::now(),
        }
    }
    
    pub fn created(resource: &str) -> Self {
        Self::new(format!("{} created successfully", resource))
    }
    
    pub fn updated(resource: &str) -> Self {
        Self::new(format!("{} updated successfully", resource))
    }
    
    pub fn deleted(resource: &str) -> Self {
        Self::new(format!("{} deleted successfully", resource))
    }
}