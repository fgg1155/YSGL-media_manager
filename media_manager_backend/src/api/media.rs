use axum::{
    extract::{Path, Query, State},
    response::{Json, IntoResponse},
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;

use crate::models::{
    CreateMediaRequest, MediaItem, MediaType, WatchStatus,
    MediaItemResponse, PaginatedResponse
};
use crate::database::repository::DatabaseRepository;
use crate::api::error::{ApiError, ApiResult};
use crate::api::response::{success, success_message};
use super::AppState;

/// 从各种日期格式中解析年份
/// 支持格式：
/// - YYYY-MM-DD (2025-03-03)
/// - YY.MM.DD (25.03.03)
/// - YYYY/MM/DD (2025/03/03)
/// - YY/MM/DD (25/03/03)
/// - YYYYMMDD (20250303)
fn parse_year_from_date(date_str: &str) -> Option<i32> {
    let date_str = date_str.trim();
    
    // 尝试 YYYY-MM-DD 或 YYYY/MM/DD 格式
    if date_str.len() >= 4 {
        if let Ok(year) = date_str[..4].parse::<i32>() {
            if year >= 1900 && year <= 2100 {
                return Some(year);
            }
        }
    }
    
    // 尝试 YY.MM.DD 或 YY/MM/DD 或 YY-MM-DD 格式
    let parts: Vec<&str> = date_str.split(|c| c == '.' || c == '/' || c == '-').collect();
    if parts.len() >= 1 {
        if let Ok(year_part) = parts[0].parse::<i32>() {
            // 两位数年份
            if year_part >= 0 && year_part <= 99 {
                // 假设 00-30 是 2000-2030，31-99 是 1931-1999
                let full_year = if year_part <= 30 { 2000 + year_part } else { 1900 + year_part };
                return Some(full_year);
            }
            // 四位数年份
            if year_part >= 1900 && year_part <= 2100 {
                return Some(year_part);
            }
        }
    }
    
    // 尝试 YYYYMMDD 格式
    if date_str.len() == 8 {
        if let Ok(year) = date_str[..4].parse::<i32>() {
            if year >= 1900 && year <= 2100 {
                return Some(year);
            }
        }
    }
    
    None
}

/// 标准化发售日期格式为 YYYY-MM-DD
fn normalize_release_date(date_str: &str) -> Option<String> {
    let date_str = date_str.trim();
    
    // 尝试解析各种格式
    let parts: Vec<&str> = date_str.split(|c| c == '.' || c == '/' || c == '-').collect();
    
    if parts.len() == 3 {
        let year_str = parts[0];
        let month_str = parts[1];
        let day_str = parts[2];
        
        // 解析年份
        let year: i32 = if let Ok(y) = year_str.parse::<i32>() {
            if y >= 0 && y <= 99 {
                // 两位数年份
                if y <= 30 { 2000 + y } else { 1900 + y }
            } else if y >= 1900 && y <= 2100 {
                y
            } else {
                return None;
            }
        } else {
            return None;
        };
        
        // 解析月份和日期
        let month: u32 = month_str.parse().ok()?;
        let day: u32 = day_str.parse().ok()?;
        
        if month >= 1 && month <= 12 && day >= 1 && day <= 31 {
            return Some(format!("{:04}-{:02}-{:02}", year, month, day));
        }
    }
    
    // 尝试 YYYYMMDD 格式
    if date_str.len() == 8 && date_str.chars().all(|c| c.is_ascii_digit()) {
        let year: i32 = date_str[..4].parse().ok()?;
        let month: u32 = date_str[4..6].parse().ok()?;
        let day: u32 = date_str[6..8].parse().ok()?;
        
        if year >= 1900 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31 {
            return Some(format!("{:04}-{:02}-{:02}", year, month, day));
        }
    }
    
    // 如果已经是标准格式，直接返回
    if date_str.len() == 10 && date_str.chars().nth(4) == Some('-') && date_str.chars().nth(7) == Some('-') {
        return Some(date_str.to_string());
    }
    
    None
}

#[derive(Debug, Deserialize)]
pub struct MediaListParams {
    pub page: Option<u32>,
    pub limit: Option<u32>,
    pub media_type: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
    pub keyword: Option<String>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub sort_by: Option<String>,  // created_at, year, rating, title
    pub sort_order: Option<String>,  // asc, desc
}

#[derive(Debug, Deserialize)]
pub struct TmdbDetailsParams {
    pub tmdb_id: u32,
    pub media_type: String, // "movie" or "tv"
}

pub async fn get_media_list(
    Query(params): Query<MediaListParams>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let page = params.page.unwrap_or(1) as i32;
    let page_size = params.limit.unwrap_or(20) as i32;
    
    // 构建筛选条件
    let filters = MediaFilters {
        media_type: params.media_type,
        studio: params.studio,
        series: params.series,
        keyword: params.keyword,
        year: params.year,
        genre: params.genre,
        sort_by: params.sort_by.unwrap_or_else(|| "created_at".to_string()),
        sort_order: params.sort_order.unwrap_or_else(|| "desc".to_string()),
    };
    
    let (media_list, total) = state.db_service.get_media_list_filtered(page, page_size, &filters).await?;
    
    let media_responses: Vec<MediaItemResponse> = media_list
        .into_iter()
        .map(MediaItemResponse::from)
        .collect();
    
    let response = PaginatedResponse::new(media_responses, total, page, page_size);
    Ok(success(response))
}

/// 媒体筛选条件
#[derive(Debug, Clone, Default)]
pub struct MediaFilters {
    pub media_type: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
    pub keyword: Option<String>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub sort_by: String,
    pub sort_order: String,
}

/// 筛选选项响应
#[derive(Debug, Serialize)]
pub struct FilterOptionsResponse {
    pub media_types: Vec<String>,
    pub studios: Vec<String>,
    pub series: Vec<String>,
    pub years: Vec<i32>,
    pub genres: Vec<String>,
}

/// 获取筛选选项
pub async fn get_filter_options(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let pool = state.database.pool();
    
    // 获取所有媒体类型
    let media_types: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT media_type FROM media_items WHERE media_type IS NOT NULL ORDER BY media_type"
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    
    // 获取所有厂商
    let studios: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT studio FROM media_items WHERE studio IS NOT NULL AND studio != '' ORDER BY studio"
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    
    // 获取所有系列
    let series: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT series FROM media_items WHERE series IS NOT NULL AND series != '' ORDER BY series"
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    
    // 获取所有年份
    let years: Vec<i32> = sqlx::query_scalar(
        "SELECT DISTINCT year FROM media_items WHERE year IS NOT NULL ORDER BY year DESC"
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    
    // 获取所有genres（从JSON数组中提取）
    let genres_raw: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT genres FROM media_items WHERE genres IS NOT NULL AND genres != '[]'"
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    
    // 解析JSON数组并去重
    let mut genres_set = std::collections::HashSet::new();
    for genres_json in genres_raw {
        if let Ok(genres_array) = serde_json::from_str::<Vec<String>>(&genres_json) {
            for genre in genres_array {
                if !genre.is_empty() {
                    genres_set.insert(genre);
                }
            }
        }
    }
    let mut genres: Vec<String> = genres_set.into_iter().collect();
    genres.sort();
    
    Ok(success(FilterOptionsResponse {
        media_types,
        studios,
        series,
        years,
        genres,
    }))
}

pub async fn get_media_detail(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let media = state.db_service.get_media_detail(&id).await?
        .ok_or_else(|| ApiError::NotFound("Media not found".to_string()))?;
    
    Ok(success(MediaItemResponse::from(media)))
}

pub async fn create_media(
    State(state): State<AppState>,
    Json(payload): Json<CreateMediaRequest>,
) -> ApiResult<impl IntoResponse> {
    // 记录收到的请求（包括 ID）
    tracing::info!("Create media request received - title: {}, id: {:?}", payload.title, payload.id);
    
    // 验证输入
    if payload.title.trim().is_empty() {
        return Err(ApiError::Validation("Title cannot be empty".to_string()));
    }
    
    // 提取演员列表用于后续关联
    let cast_list = payload.cast.clone();
    
    // 从请求构建完整的媒体对象
    let media = MediaItem::from_create_request(payload)
        .map_err(|e| {
            // 特别处理 InvalidId 错误
            if matches!(e, crate::models::ValidationError::InvalidId) {
                tracing::error!("Invalid UUID format in create media request: {:?}", e);
                ApiError::Validation("Invalid UUID format".to_string())
            } else {
                tracing::error!("Failed to build media from request: {:?}", e);
                ApiError::Validation(format!("Failed to build media: {:?}", e))
            }
        })?;
    
    let media_id = media.id.clone();
    
    // 保存到数据库
    state.database.repository().insert_media(&media).await
        .map_err(|e| {
            if e.to_string().contains("already exists") {
                ApiError::Conflict("Media already exists".to_string())
            } else {
                ApiError::Internal(e.to_string())
            }
        })?;
    
    // 处理演员关联
    if let Some(cast) = cast_list {
        let pool = state.database.pool();
        for person in cast {
            // 查找或创建演员
            let actor_id = match crate::database::find_actor_by_name(pool, &person.name).await {
                Ok(Some(actor)) => actor.id,
                Ok(None) => {
                    // 创建新演员
                    let new_actor = crate::models::Actor::new(person.name.clone());
                    if let Err(e) = crate::database::insert_actor(pool, &new_actor).await {
                        tracing::warn!("Failed to create actor {}: {}", person.name, e);
                        continue;
                    }
                    new_actor.id
                }
                Err(e) => {
                    tracing::warn!("Failed to find actor {}: {}", person.name, e);
                    continue;
                }
            };
            
            // 创建演员-媒体关联
            // 将 role 转换为数据库约束的值 ('cast' 或 'crew')
            let db_role = match person.role.to_lowercase().as_str() {
                "actor" | "actress" => "cast",
                "director" | "producer" | "writer" => "crew",
                _ => "cast", // 默认为 cast
            };
            
            if let Err(e) = crate::database::add_actor_to_media(
                pool, 
                &actor_id, 
                &media_id, 
                person.character.clone(),
                Some(db_role.to_string()),
            ).await {
                tracing::warn!("Failed to link actor {} to media: {}", person.name, e);
            }
        }
    }
    
    Ok(success(MediaItemResponse::from(media)))
}

pub async fn update_media(
    Path(id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<crate::models::UpdateMediaRequest>,
) -> ApiResult<impl IntoResponse> {
    // 首先获取现有媒体
    let mut media = state.db_service.get_media_detail(&id).await?
        .ok_or_else(|| ApiError::NotFound("Media not found".to_string()))?;
    
    // 应用更新
    media.apply_update(payload)
        .map_err(|e| ApiError::Validation(format!("Failed to apply update: {:?}", e)))?;
    
    // 保存更新
    state.db_service.update_media(media.clone()).await?;
    
    Ok(success(MediaItemResponse::from(media)))
}

pub async fn delete_media(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    state.db_service.delete_media(&id).await?;
    Ok(success_message("Media deleted successfully"))
}

/// 从TMDB获取详细信息并可选择性地保存到本地数据库
pub async fn get_tmdb_details(
    Query(params): Query<TmdbDetailsParams>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    if !state.external_client.is_tmdb_available() {
        return Err(ApiError::ExternalService("TMDB service unavailable".to_string()));
    }
    
    let media_item = match params.media_type.as_str() {
        "movie" => {
            state.external_client.get_movie_details(params.tmdb_id).await
                .map_err(|e| ApiError::ExternalService(format!("Failed to get movie details: {}", e)))?
        }
        "tv" => {
            state.external_client.get_tv_details(params.tmdb_id).await
                .map_err(|e| ApiError::ExternalService(format!("Failed to get TV details: {}", e)))?
        }
        _ => {
            return Err(ApiError::BadRequest("Invalid media type".to_string()));
        }
    };
    
    Ok(success(media_item))
}

/// 获取TMDB热门内容
pub async fn get_popular_content(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    if !state.external_client.is_tmdb_available() {
        return Err(ApiError::ExternalService("TMDB service unavailable".to_string()));
    }
    
    let media_type = params.get("media_type").map(|s| s.as_str()).unwrap_or("movie");
    let page = params.get("page")
        .and_then(|p| p.parse().ok())
        .unwrap_or(1);
    
    let results = match media_type {
        "movie" => {
            state.external_client.get_popular_movies(Some(page)).await
                .map_err(|e| ApiError::ExternalService(format!("Failed to get popular movies: {}", e)))?
        }
        "tv" => {
            state.external_client.get_popular_tv_shows(Some(page)).await
                .map_err(|e| ApiError::ExternalService(format!("Failed to get popular TV shows: {}", e)))?
        }
        _ => {
            return Err(ApiError::BadRequest("Invalid media type".to_string()));
        }
    };
    
    Ok(success(json!({
        "results": results,
        "total": results.len(),
        "page": page,
        "media_type": media_type
    })))
}

/// 将TMDB媒体保存到本地数据库
pub async fn save_tmdb_media(
    State(state): State<AppState>,
    Json(media_item): Json<MediaItem>,
) -> ApiResult<impl IntoResponse> {
    // 检查是否已存在相同的TMDB ID
    if let Ok(external_ids) = media_item.get_external_ids() {
        if let Some(tmdb_id) = external_ids.tmdb_id {
            tracing::info!("Saving TMDB media with ID: {}", tmdb_id);
        }
    }
    
    state.db_service.update_media(media_item.clone()).await?;
    
    Ok(success(MediaItemResponse::from(media_item)))
}


// ============ Batch Operations ============

/// 批量删除请求
#[derive(Debug, Deserialize)]
pub struct BatchDeleteRequest {
    pub ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct BatchDeleteResponse {
    pub success_count: usize,
    pub failed_count: usize,
    pub errors: Vec<String>,
}

/// 批量删除媒体
pub async fn batch_delete_media(
    State(state): State<AppState>,
    Json(payload): Json<BatchDeleteRequest>,
) -> impl IntoResponse {
    let mut success_count = 0;
    let mut failed_count = 0;
    let mut errors = Vec::new();

    for id in &payload.ids {
        match state.db_service.delete_media(id).await {
            Ok(_) => success_count += 1,
            Err(e) => {
                failed_count += 1;
                errors.push(format!("{}: {}", id, e));
            }
        }
    }

    success(BatchDeleteResponse {
        success_count,
        failed_count,
        errors,
    })
}

/// 批量编辑请求
#[derive(Debug, Deserialize)]
pub struct BatchEditRequest {
    pub ids: Vec<String>,
    pub updates: BatchEditUpdates,
}

#[derive(Debug, Deserialize)]
pub struct BatchEditUpdates {
    pub media_type: Option<String>,
    pub genres: Option<Vec<String>>,
    pub studio: Option<String>,
    pub series: Option<String>,
    pub add_tags: Option<Vec<String>>,
    pub remove_tags: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct BatchEditResponse {
    pub success_count: usize,
    pub failed_count: usize,
    pub errors: Vec<String>,
}

/// 批量编辑媒体
pub async fn batch_edit_media(
    State(state): State<AppState>,
    Json(payload): Json<BatchEditRequest>,
) -> impl IntoResponse {
    let mut success_count = 0;
    let mut failed_count = 0;
    let mut errors = Vec::new();

    for id in &payload.ids {
        // 获取现有媒体
        let media = match state.db_service.get_media_detail(id).await {
            Ok(Some(m)) => m,
            Ok(None) => {
                failed_count += 1;
                errors.push(format!("{}: not found", id));
                continue;
            }
            Err(e) => {
                failed_count += 1;
                errors.push(format!("{}: {}", id, e));
                continue;
            }
        };

        let mut media = media;
        let mut changed = false;

        // 应用更新
        if let Some(ref media_type_str) = payload.updates.media_type {
            let new_type = match media_type_str.as_str() {
                "Movie" | "movie" => "Movie".to_string(),
                "Scene" | "scene" => "Scene".to_string(),
                "Anime" | "anime" => "Anime".to_string(),
                "Documentary" | "documentary" => "Documentary".to_string(),
                _ => media.media_type.clone(),
            };
            if media.media_type != new_type {
                media.media_type = new_type;
                changed = true;
            }
        }

        if let Some(ref genres) = payload.updates.genres {
            let _ = media.set_genres(genres);
            changed = true;
        }

        if let Some(ref studio) = payload.updates.studio {
            media.studio = Some(studio.clone());
            changed = true;
        }

        if let Some(ref series) = payload.updates.series {
            media.series = Some(series.clone());
            changed = true;
        }

        // 保存更新
        if changed {
            match state.db_service.update_media(media).await {
                Ok(_) => success_count += 1,
                Err(e) => {
                    failed_count += 1;
                    errors.push(format!("{}: {}", id, e));
                }
            }
        } else {
            success_count += 1; // 没有变化也算成功
        }
    }

    success(BatchEditResponse {
        success_count,
        failed_count,
        errors,
    })
}

#[derive(Debug, Deserialize)]
pub struct BatchImportRequest {
    pub items: Vec<BatchImportItem>,
}

#[derive(Debug, Deserialize)]
pub struct BatchImportItem {
    pub tmdb_id: Option<u32>,
    pub media_type: String,
    pub title: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct BatchImportResponse {
    pub success_count: usize,
    pub failed_count: usize,
    pub results: Vec<BatchImportResult>,
}

#[derive(Debug, Serialize)]
pub struct BatchImportResult {
    pub index: usize,
    pub success: bool,
    pub media_id: Option<String>,
    pub error: Option<String>,
}

/// 批量导入媒体（从TMDB或手动创建）
pub async fn batch_import_media(
    State(state): State<AppState>,
    Json(payload): Json<BatchImportRequest>,
) -> impl IntoResponse {
    let mut results = Vec::new();
    let mut success_count = 0;
    let mut failed_count = 0;

    for (index, item) in payload.items.iter().enumerate() {
        let result = if let Some(tmdb_id) = item.tmdb_id {
            // 从TMDB获取并保存
            match item.media_type.as_str() {
                "movie" => {
                    match state.external_client.get_movie_details(tmdb_id).await {
                        Ok(media) => {
                            match state.db_service.update_media(media.clone()).await {
                                Ok(_) => BatchImportResult {
                                    index,
                                    success: true,
                                    media_id: Some(media.id),
                                    error: None,
                                },
                                Err(e) => BatchImportResult {
                                    index,
                                    success: false,
                                    media_id: None,
                                    error: Some(format!("Failed to save: {}", e)),
                                },
                            }
                        }
                        Err(e) => BatchImportResult {
                            index,
                            success: false,
                            media_id: None,
                            error: Some(format!("TMDB fetch failed: {}", e)),
                        },
                    }
                }
                "tv" => {
                    match state.external_client.get_tv_details(tmdb_id).await {
                        Ok(media) => {
                            match state.db_service.update_media(media.clone()).await {
                                Ok(_) => BatchImportResult {
                                    index,
                                    success: true,
                                    media_id: Some(media.id),
                                    error: None,
                                },
                                Err(e) => BatchImportResult {
                                    index,
                                    success: false,
                                    media_id: None,
                                    error: Some(format!("Failed to save: {}", e)),
                                },
                            }
                        }
                        Err(e) => BatchImportResult {
                            index,
                            success: false,
                            media_id: None,
                            error: Some(format!("TMDB fetch failed: {}", e)),
                        },
                    }
                }
                _ => BatchImportResult {
                    index,
                    success: false,
                    media_id: None,
                    error: Some("Invalid media type".to_string()),
                },
            }
        } else if let Some(title) = &item.title {
            // 手动创建
            let media_type = match item.media_type.as_str() {
                "movie" => MediaType::Movie,
                "tv" => MediaType::Scene,
                _ => MediaType::Movie,
            };
            
            match state.db_service.create_media(title.clone(), media_type).await {
                Ok(media) => BatchImportResult {
                    index,
                    success: true,
                    media_id: Some(media.id),
                    error: None,
                },
                Err(e) => BatchImportResult {
                    index,
                    success: false,
                    media_id: None,
                    error: Some(format!("Failed to create: {}", e)),
                },
            }
        } else {
            BatchImportResult {
                index,
                success: false,
                media_id: None,
                error: Some("Either tmdb_id or title is required".to_string()),
            }
        };

        if result.success {
            success_count += 1;
        } else {
            failed_count += 1;
        }
        results.push(result);
    }

    success(BatchImportResponse {
        success_count,
        failed_count,
        results,
    })
}

#[derive(Debug, Deserialize)]
pub struct BatchCollectionRequest {
    pub media_ids: Vec<String>,
    pub action: BatchCollectionAction,
    pub watch_status: Option<String>,
    pub tags: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BatchCollectionAction {
    Add,
    Remove,
    UpdateStatus,
    AddTags,
    RemoveTags,
}

#[derive(Debug, Serialize)]
pub struct BatchCollectionResponse {
    pub success_count: usize,
    pub failed_count: usize,
    pub errors: Vec<String>,
}

/// 批量收藏操作
pub async fn batch_collection_operation(
    State(state): State<AppState>,
    Json(payload): Json<BatchCollectionRequest>,
) -> impl IntoResponse {
    let mut success_count = 0;
    let mut failed_count = 0;
    let mut errors = Vec::new();

    for media_id in &payload.media_ids {
        let result: Result<(), anyhow::Error> = match payload.action {
            BatchCollectionAction::Add => {
                let status = payload.watch_status.as_ref()
                    .and_then(|s| match s.as_str() {
                        "want_to_watch" => Some(WatchStatus::WantToWatch),
                        "watching" => Some(WatchStatus::Watching),
                        "completed" => Some(WatchStatus::Completed),
                        "on_hold" => Some(WatchStatus::OnHold),
                        "dropped" => Some(WatchStatus::Dropped),
                        _ => None,
                    })
                    .unwrap_or(WatchStatus::WantToWatch);
                
                state.db_service.add_to_collection(media_id.clone(), status).await.map(|_| ())
            }
            BatchCollectionAction::Remove => {
                state.db_service.remove_from_collection(media_id).await
            }
            BatchCollectionAction::UpdateStatus => {
                if let Some(status_str) = &payload.watch_status {
                    let status = match status_str.as_str() {
                        "want_to_watch" => WatchStatus::WantToWatch,
                        "watching" => WatchStatus::Watching,
                        "completed" => WatchStatus::Completed,
                        "on_hold" => WatchStatus::OnHold,
                        "dropped" => WatchStatus::Dropped,
                        _ => WatchStatus::WantToWatch,
                    };
                    state.db_service.update_collection_status(media_id, status).await
                } else {
                    Err(anyhow::anyhow!("watch_status is required for update"))
                }
            }
            BatchCollectionAction::AddTags => {
                if let Some(tags) = &payload.tags {
                    state.db_service.add_tags_to_collection(media_id, tags.clone()).await
                } else {
                    Err(anyhow::anyhow!("tags is required"))
                }
            }
            BatchCollectionAction::RemoveTags => {
                if let Some(tags) = &payload.tags {
                    state.db_service.remove_tags_from_collection(media_id, tags.clone()).await
                } else {
                    Err(anyhow::anyhow!("tags is required"))
                }
            }
        };

        match result {
            Ok(_) => success_count += 1,
            Err(e) => {
                failed_count += 1;
                errors.push(format!("{}: {}", media_id, e));
            }
        }
    }

    success(BatchCollectionResponse {
        success_count,
        failed_count,
        errors,
    })
}


// ============ Export/Import Data ============

#[derive(Debug, Serialize)]
pub struct ExportActorItem {
    pub id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub photo_url: Option<String>,
    pub poster_url: Option<String>,
    pub backdrop_url: Option<String>,
    pub biography: Option<String>,
    pub birth_date: Option<String>,
    pub nationality: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ExportActorMediaRelation {
    pub actor_id: String,
    pub media_id: String,
    pub character_name: Option<String>,
    pub role: String,
}

#[derive(Debug, Serialize)]
pub struct ExportDataResponse {
    pub version: String,
    pub exported_at: String,
    pub media: Vec<MediaItemResponse>,
    pub collections: Vec<crate::models::CollectionResponse>,
    pub actors: Vec<ExportActorItem>,
    pub actor_media_relations: Vec<ExportActorMediaRelation>,
    pub studios: Vec<String>,  // 新增：所有厂商列表
    pub series: Vec<ExportSeriesItem>,  // 新增：所有系列列表
}

#[derive(Debug, Serialize)]
pub struct ExportSeriesItem {
    pub name: String,
    pub studio: Option<String>,
}

/// 导出所有数据
pub async fn export_all_data(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    // 获取所有媒体
    let (media_list, _) = state.db_service.get_media_list(1, 10000).await?;
    
    let media_responses: Vec<MediaItemResponse> = media_list
        .into_iter()
        .map(MediaItemResponse::from)
        .collect();
    
    // 获取所有收藏
    let collections = state.db_service.get_collections().await?;
    
    let collection_responses: Vec<crate::models::CollectionResponse> = collections
        .into_iter()
        .map(crate::models::CollectionResponse::from)
        .collect();
    
    // 获取所有演员
    let actors_result = crate::database::list_actors(
        state.database.pool(),
        &crate::models::ActorSearchFilters { query: None, limit: Some(10000), offset: None }
    ).await;
    
    let actors: Vec<ExportActorItem> = match actors_result {
        Ok(response) => response.actors.into_iter().map(|a| ExportActorItem {
            id: a.id,
            name: a.name,
            avatar_url: a.avatar_url,
            photo_url: a.photo_url,
            poster_url: a.poster_url,
            backdrop_url: a.backdrop_url,
            biography: a.biography,
            birth_date: a.birth_date,
            nationality: a.nationality,
        }).collect(),
        Err(e) => {
            tracing::warn!("Failed to get actors for export: {}", e);
            Vec::new()
        }
    };
    
    // 获取所有演员-媒体关系
    let relations: Vec<ExportActorMediaRelation> = {
        let pool = state.database.pool();
        let rows: Result<Vec<(String, String, Option<String>, String)>, _> = sqlx::query_as(
            "SELECT actor_id, media_id, character_name, role FROM actor_media"
        )
        .fetch_all(pool)
        .await;
        
        match rows {
            Ok(rows) => rows.into_iter().map(|(actor_id, media_id, character_name, role)| {
                ExportActorMediaRelation { actor_id, media_id, character_name, role }
            }).collect(),
            Err(e) => {
                tracing::warn!("Failed to get actor-media relations for export: {}", e);
                Vec::new()
            }
        }
    };
    
    // 获取所有厂商
    let studios: Vec<String> = {
        let pool = state.database.pool();
        let rows: Result<Vec<(String,)>, _> = sqlx::query_as(
            "SELECT DISTINCT name FROM studios ORDER BY name"
        )
        .fetch_all(pool)
        .await;
        
        match rows {
            Ok(rows) => rows.into_iter().map(|(name,)| name).collect(),
            Err(e) => {
                tracing::warn!("Failed to get studios for export: {}", e);
                Vec::new()
            }
        }
    };
    
    // 获取所有系列
    let series: Vec<ExportSeriesItem> = {
        let pool = state.database.pool();
        let rows: Result<Vec<(String, Option<String>)>, _> = sqlx::query_as(
            "SELECT name, studio FROM series ORDER BY name"
        )
        .fetch_all(pool)
        .await;
        
        match rows {
            Ok(rows) => rows.into_iter().map(|(name, studio)| {
                ExportSeriesItem { name, studio }
            }).collect(),
            Err(e) => {
                tracing::warn!("Failed to get series for export: {}", e);
                Vec::new()
            }
        }
    };
    
    Ok(success(ExportDataResponse {
        version: "1.2".to_string(),  // 版本升级到 1.2
        exported_at: chrono::Utc::now().to_rfc3339(),
        media: media_responses,
        collections: collection_responses,
        actors,
        actor_media_relations: relations,
        studios,
        series,
    }))
}

#[derive(Debug, Deserialize)]
pub struct ImportActorItem {
    pub id: Option<String>,
    pub name: String,
    pub avatar_url: Option<String>,
    pub photo_url: Option<String>,
    pub poster_url: Option<String>,
    pub backdrop_url: Option<String>,
    pub biography: Option<String>,
    pub birth_date: Option<String>,
    pub nationality: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ImportActorMediaRelation {
    pub actor_id: Option<String>,
    pub actor_name: Option<String>,  // 可以通过名称查找演员
    pub media_id: Option<String>,
    pub media_title: Option<String>, // 可以通过标题查找媒体
    pub character_name: Option<String>,
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ImportDataRequest {
    pub version: String,
    pub media: Vec<ImportMediaItem>,
    pub collections: Option<Vec<ImportCollectionItem>>,
    pub actors: Option<Vec<ImportActorItem>>,
    pub actor_media_relations: Option<Vec<ImportActorMediaRelation>>,
    pub studios: Option<Vec<String>>,  // 新增：厂商列表
    pub series: Option<Vec<ImportSeriesItem>>,  // 新增：系列列表
}

#[derive(Debug, Deserialize)]
pub struct ImportSeriesItem {
    pub name: String,
    pub studio: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ImportMediaItem {
    pub title: String,
    pub original_title: Option<String>,
    pub year: Option<i32>,
    pub release_date: Option<String>,  // 发售日期，支持多种格式：YYYY-MM-DD, YY.MM.DD, YYYY/MM/DD 等
    pub media_type: String,
    pub genres: Option<Vec<String>>,
    pub rating: Option<f64>,
    pub overview: Option<String>,
    pub poster_url: Option<String>,
    pub backdrop_url: Option<String>,
    pub play_links: Option<Vec<crate::models::PlayLink>>,
    pub download_links: Option<Vec<crate::models::DownloadLink>>,
    pub preview_urls: Option<Vec<String>>,
    pub preview_video_urls: Option<Vec<String>>,
    pub studio: Option<String>,
    pub series: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ImportCollectionItem {
    pub media_title: String,
    pub watch_status: String,
    pub personal_rating: Option<f64>,
    pub notes: Option<String>,
    pub is_favorite: Option<bool>,
    pub user_tags: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct ImportDataResponse {
    pub media_imported: usize,
    pub media_failed: usize,
    pub collections_imported: usize,
    pub collections_failed: usize,
    pub actors_imported: usize,
    pub actors_failed: usize,
    pub relations_imported: usize,
    pub relations_failed: usize,
    pub studios_imported: usize,  // 新增
    pub series_imported: usize,   // 新增
    pub errors: Vec<String>,
}

/// 导入数据
pub async fn import_data(
    State(state): State<AppState>,
    Json(payload): Json<ImportDataRequest>,
) -> impl IntoResponse {
    let mut media_imported = 0;
    let mut media_failed = 0;
    let mut collections_imported = 0;
    let mut collections_failed = 0;
    let mut actors_imported = 0;
    let mut actors_failed = 0;
    let mut relations_imported = 0;
    let mut relations_failed = 0;
    let mut studios_imported = 0;
    let mut series_imported = 0;
    let mut errors = Vec::new();
    let mut media_id_map: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    let mut actor_id_map: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    
    // 导入厂商（在导入媒体之前）
    if let Some(studios) = &payload.studios {
        for studio_name in studios {
            if !studio_name.is_empty() {
                match crate::database::find_or_create_studio(state.database.pool(), studio_name).await {
                    Ok(_) => studios_imported += 1,
                    Err(e) => {
                        tracing::warn!("Failed to import studio '{}': {}", studio_name, e);
                    }
                }
            }
        }
    }
    
    // 导入系列（在导入媒体之前）
    if let Some(series_list) = &payload.series {
        for series_item in series_list {
            if !series_item.name.is_empty() {
                // 如果有厂商，先确保厂商存在
                if let Some(ref studio) = series_item.studio {
                    if !studio.is_empty() {
                        let _ = crate::database::find_or_create_studio(state.database.pool(), studio).await;
                    }
                }
                
                // 使用智能匹配创建系列
                match crate::database::smart_match_or_create_series(
                    state.database.pool(),
                    &series_item.name,
                    series_item.studio.as_deref(),
                ).await {
                    Ok(_) => series_imported += 1,
                    Err(e) => {
                        tracing::warn!("Failed to import series '{}': {}", series_item.name, e);
                    }
                }
            }
        }
    }
    
    // 导入演员
    if let Some(actors) = &payload.actors {
        for item in actors {
            // 先尝试查找已存在的演员
            match crate::database::find_or_create_actor_by_name(state.database.pool(), &item.name).await {
                Ok(mut actor) => {
                    // 更新演员详细信息
                    if item.avatar_url.is_some() || item.photo_url.is_some() || item.poster_url.is_some() || item.backdrop_url.is_some() || item.biography.is_some() || item.birth_date.is_some() || item.nationality.is_some() {
                        if let Some(ref avatar_url) = item.avatar_url {
                            actor.avatar_url = Some(avatar_url.clone());
                        }
                        if let Some(ref photo_url) = item.photo_url {
                            actor.photo_url = Some(photo_url.clone());
                        }
                        if let Some(ref poster_url) = item.poster_url {
                            actor.poster_url = Some(poster_url.clone());
                        }
                        if let Some(ref backdrop_url) = item.backdrop_url {
                            actor.backdrop_url = Some(backdrop_url.clone());
                        }
                        if let Some(ref biography) = item.biography {
                            actor.biography = Some(biography.clone());
                        }
                        if let Some(ref birth_date) = item.birth_date {
                            actor.birth_date = Some(birth_date.clone());
                        }
                        if let Some(ref nationality) = item.nationality {
                            actor.nationality = Some(nationality.clone());
                        }
                        // 更新演员信息
                        if let Err(e) = crate::database::update_actor_direct(state.database.pool(), &actor).await {
                            tracing::warn!("Failed to update actor details: {}", e);
                        }
                    }
                    
                    if let Some(ref original_id) = item.id {
                        actor_id_map.insert(original_id.clone(), actor.id.clone());
                    }
                    actor_id_map.insert(item.name.clone(), actor.id.clone());
                    actors_imported += 1;
                }
                Err(e) => {
                    actors_failed += 1;
                    errors.push(format!("Actor '{}': {}", item.name, e));
                }
            }
        }
    }
    
    // 导入媒体
    for item in &payload.media {
        let media_type = match item.media_type.as_str() {
            "Movie" => MediaType::Movie,
            "Scene" => MediaType::Scene,
            "Documentary" => MediaType::Documentary,
            "Anime" => MediaType::Anime,
            _ => MediaType::Movie,
        };
        
        match state.db_service.create_media(item.title.clone(), media_type).await {
            Ok(mut media) => {
                // 处理年份 - 优先使用 year，如果没有则从 release_date 提取
                let year = item.year.or_else(|| {
                    item.release_date.as_ref().and_then(|date| parse_year_from_date(date))
                });
                if let Some(y) = year {
                    let _ = media.set_year(Some(y));
                }
                
                // 处理发售日期 - 标准化格式
                if let Some(ref release_date) = item.release_date {
                    if let Some(normalized) = normalize_release_date(release_date) {
                        media.release_date = Some(normalized);
                    }
                }
                
                if let Some(ref overview) = item.overview {
                    let _ = media.set_overview(Some(overview.clone()));
                }
                if let Some(ref genres) = item.genres {
                    let _ = media.set_genres(genres);
                }
                if let Some(rating) = item.rating {
                    let _ = media.set_rating(Some(rating as f32));
                }
                if let Some(ref poster_url) = item.poster_url {
                    let _ = media.set_poster_url(Some(poster_url.clone()));
                }
                if let Some(ref backdrop_url) = item.backdrop_url {
                    let _ = media.set_backdrop_url(Some(backdrop_url.clone()));
                }
                if let Some(ref original_title) = item.original_title {
                    media.original_title = Some(original_title.clone());
                }
                if let Some(ref play_links) = item.play_links {
                    let _ = media.set_play_links(play_links);
                }
                if let Some(ref download_links) = item.download_links {
                    let _ = media.set_download_links(download_links);
                }
                if let Some(ref preview_urls) = item.preview_urls {
                    let _ = media.set_preview_urls(preview_urls);
                }
                if let Some(ref preview_video_urls) = item.preview_video_urls {
                    let _ = media.set_preview_video_urls(preview_video_urls);
                }
                // 新增 studio 和 series - 使用智能匹配
                if item.studio.is_some() || item.series.is_some() {
                    // 处理厂商
                    if let Some(ref studio_name) = item.studio {
                        if !studio_name.is_empty() {
                            // 确保厂商存在
                            if let Err(e) = crate::database::find_or_create_studio(state.database.pool(), studio_name).await {
                                tracing::warn!("Failed to create studio '{}': {}", studio_name, e);
                            }
                            media.studio = Some(studio_name.clone());
                        }
                    }
                    
                    // 处理系列 - 智能匹配
                    if let Some(ref series_name) = item.series {
                        if !series_name.is_empty() {
                            match crate::database::smart_match_or_create_series(
                                state.database.pool(),
                                series_name,
                                item.studio.as_deref(),
                            ).await {
                                Ok(match_result) => {
                                    media.series = Some(match_result.series_name.clone());
                                    
                                    // 如果只提供了系列名且匹配到唯一厂商，自动填充厂商
                                    if item.studio.is_none() && match_result.studio_name.is_some() {
                                        media.studio = match_result.studio_name.clone();
                                        if let Some(ref studio_name) = match_result.studio_name {
                                            tracing::info!(
                                                "Auto-matched series '{}' to studio '{}'",
                                                series_name,
                                                studio_name
                                            );
                                        }
                                    }
                                    
                                    // 记录匹配类型
                                    match match_result.match_type {
                                        crate::models::SeriesMatchType::Ambiguous => {
                                            tracing::warn!(
                                                "Series '{}' exists in multiple studios, using first match",
                                                series_name
                                            );
                                        }
                                        _ => {}
                                    }
                                }
                                Err(e) => {
                                    tracing::warn!("Failed to match series '{}': {}", series_name, e);
                                    media.series = Some(series_name.clone());
                                }
                            }
                        }
                    }
                }
                
                // 保存更新
                if let Err(e) = state.db_service.update_media(media.clone()).await {
                    tracing::warn!("Failed to update imported media fields: {}", e);
                }
                
                media_id_map.insert(item.title.clone(), media.id.clone());
                media_imported += 1;
            }
            Err(e) => {
                media_failed += 1;
                errors.push(format!("Media '{}': {}", item.title, e));
            }
        }
    }
    
    // 导入演员-媒体关系
    if let Some(relations) = &payload.actor_media_relations {
        for rel in relations {
            // 解析演员ID
            let actor_id = if let Some(ref id) = rel.actor_id {
                actor_id_map.get(id).cloned().or_else(|| Some(id.clone()))
            } else if let Some(ref name) = rel.actor_name {
                actor_id_map.get(name).cloned()
            } else {
                None
            };
            
            // 解析媒体ID
            let media_id = if let Some(ref id) = rel.media_id {
                media_id_map.get(id).cloned().or_else(|| Some(id.clone()))
            } else if let Some(ref title) = rel.media_title {
                media_id_map.get(title).cloned()
            } else {
                None
            };
            
            if let (Some(actor_id), Some(media_id)) = (actor_id, media_id) {
                match crate::database::add_actor_to_media(
                    state.database.pool(),
                    &actor_id,
                    &media_id,
                    rel.character_name.clone(),
                    rel.role.clone(),
                ).await {
                    Ok(_) => relations_imported += 1,
                    Err(e) => {
                        relations_failed += 1;
                        errors.push(format!("Relation: {}", e));
                    }
                }
            } else {
                relations_failed += 1;
                errors.push("Relation: actor or media not found".to_string());
            }
        }
    }
    
    // 导入收藏
    if let Some(collections) = &payload.collections {
        for item in collections {
            if let Some(media_id) = media_id_map.get(&item.media_title) {
                let status = match item.watch_status.as_str() {
                    "WantToWatch" => WatchStatus::WantToWatch,
                    "Watching" => WatchStatus::Watching,
                    "Completed" => WatchStatus::Completed,
                    "OnHold" => WatchStatus::OnHold,
                    "Dropped" => WatchStatus::Dropped,
                    _ => WatchStatus::WantToWatch,
                };
                
                match state.db_service.add_to_collection(media_id.clone(), status).await {
                    Ok(_) => collections_imported += 1,
                    Err(e) => {
                        collections_failed += 1;
                        errors.push(format!("Collection '{}': {}", item.media_title, e));
                    }
                }
            } else {
                collections_failed += 1;
                errors.push(format!("Collection '{}': media not found", item.media_title));
            }
        }
    }
    
    success(ImportDataResponse {
        media_imported,
        media_failed,
        collections_imported,
        collections_failed,
        actors_imported,
        actors_failed,
        relations_imported,
        relations_failed,
        studios_imported,
        series_imported,
        errors,
    })
}
