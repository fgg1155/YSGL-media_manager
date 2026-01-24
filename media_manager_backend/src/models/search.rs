use serde::{Deserialize, Serialize};
use super::{MediaType, WatchStatus};

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchFilters {
    pub query: Option<String>,
    pub media_type: Option<MediaType>,
    pub genres: Vec<String>,
    pub year_range: Option<(i32, i32)>,
    pub rating_range: Option<(f32, f32)>,
    pub watch_status: Option<WatchStatus>,
    pub actor_id: Option<String>,      // 按演员ID筛选
    pub studio: Option<String>,        // 按厂商筛选
    pub series: Option<String>,        // 按系列筛选
    pub sort_by: SortOption,
    pub sort_order: SortOrder,
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SortOption {
    Title,
    Year,
    Rating,
    AddedDate,
    LastWatched,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SortOrder {
    Ascending,
    Descending,
}