use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

/// 厂商/制作公司
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Studio {
    pub id: String,
    pub name: String,
    pub logo_url: Option<String>,
    pub description: Option<String>,
    pub media_count: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Studio {
    pub fn new(name: String) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            logo_url: None,
            description: None,
            media_count: 0,
            created_at: now,
            updated_at: now,
        }
    }
}

/// 系列
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Series {
    pub id: String,
    pub name: String,
    pub studio_id: Option<String>,
    pub description: Option<String>,
    pub cover_url: Option<String>,
    pub media_count: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Series {
    pub fn new(name: String, studio_id: Option<String>) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            studio_id,
            description: None,
            cover_url: None,
            media_count: 0,
            created_at: now,
            updated_at: now,
        }
    }
}

/// 带厂商信息的系列（用于API响应）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeriesWithStudio {
    #[serde(flatten)]
    pub series: Series,
    pub studio_name: Option<String>,
}

/// 带系列列表的厂商（用于API响应）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StudioWithSeries {
    #[serde(flatten)]
    pub studio: Studio,
    pub series_list: Vec<Series>,
}

// ============ Request/Response DTOs ============

#[derive(Debug, Deserialize)]
pub struct CreateStudioRequest {
    pub name: String,
    pub logo_url: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateStudioRequest {
    pub name: Option<String>,
    pub logo_url: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateSeriesRequest {
    pub name: String,
    pub studio_id: Option<String>,
    pub studio_name: Option<String>,  // 可通过厂商名称关联
    pub description: Option<String>,
    pub cover_url: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateSeriesRequest {
    pub name: Option<String>,
    pub studio_id: Option<String>,
    pub description: Option<String>,
    pub cover_url: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct StudioListResponse {
    pub studios: Vec<StudioWithSeries>,
    pub total: i64,
}

#[derive(Debug, Serialize)]
pub struct SeriesListResponse {
    pub series: Vec<SeriesWithStudio>,
    pub total: i64,
}

/// 系列匹配结果（用于导入时的智能匹配）
#[derive(Debug, Clone, Serialize)]
pub struct SeriesMatchResult {
    pub series_id: String,
    pub series_name: String,
    pub studio_id: Option<String>,
    pub studio_name: Option<String>,
    pub match_type: SeriesMatchType,
}

#[derive(Debug, Clone, Serialize)]
pub enum SeriesMatchType {
    Exact,           // 精确匹配（系列名+厂商都匹配）
    UniqueByName,    // 系列名唯一，自动关联厂商
    Ambiguous,       // 系列名存在于多个厂商，需要确认
    NewSeries,       // 新系列
}
