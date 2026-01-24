use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use sqlx;

use crate::database;
use crate::models::{
    Studio, Series, StudioWithSeries, SeriesWithStudio,
    CreateStudioRequest, UpdateStudioRequest,
    CreateSeriesRequest, UpdateSeriesRequest,
};
use super::AppState;
use super::error::{ApiError, ApiResult};
use super::response::{success, success_message};

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    pub studio_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SearchParams {
    pub q: String,
    pub limit: Option<i32>,
    pub studio_id: Option<String>,
}

// ============ Studio Handlers ============

/// 获取厂商列表
pub async fn list_studios_handler(
    Query(params): Query<ListParams>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let response = database::list_studios(state.database.pool(), params.limit, params.offset).await
        .map_err(|e| {
            tracing::error!("Failed to list studios: {}", e);
            ApiError::Internal("Failed to retrieve studios".to_string())
        })?;
    
    Ok(success(response))
}

/// 获取单个厂商
pub async fn get_studio_handler(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let studio = database::get_studio_by_id(state.database.pool(), &id).await
        .map_err(|_| ApiError::NotFound("Studio not found".to_string()))?;
    
    let series_list: Vec<Series> = sqlx::query_as(
        "SELECT * FROM series WHERE studio_id = ? ORDER BY media_count DESC, name COLLATE NOCASE"
    )
    .bind(&id)
    .fetch_all(state.database.pool())
    .await
    .unwrap_or_default();
    
    Ok(success(StudioWithSeries { studio, series_list }))
}

/// 创建厂商
pub async fn create_studio_handler(
    State(state): State<AppState>,
    Json(payload): Json<CreateStudioRequest>,
) -> ApiResult<impl IntoResponse> {
    if payload.name.trim().is_empty() {
        return Err(ApiError::Validation("Studio name cannot be empty".to_string()));
    }
    
    let studio = database::create_studio(state.database.pool(), payload).await
        .map_err(|e| {
            tracing::error!("Failed to create studio: {}", e);
            if e.to_string().contains("UNIQUE constraint") {
                ApiError::Conflict("Studio already exists".to_string())
            } else {
                ApiError::Internal("Failed to create studio".to_string())
            }
        })?;
    
    Ok(success(studio))
}

/// 更新厂商
pub async fn update_studio_handler(
    Path(id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateStudioRequest>,
) -> ApiResult<impl IntoResponse> {
    let studio = database::update_studio(state.database.pool(), &id, payload).await
        .map_err(|e| {
            tracing::error!("Failed to update studio: {}", e);
            ApiError::Internal("Failed to update studio".to_string())
        })?;
    
    Ok(success(studio))
}

/// 删除厂商
pub async fn delete_studio_handler(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    database::delete_studio(state.database.pool(), &id).await
        .map_err(|e| {
            tracing::error!("Failed to delete studio: {}", e);
            ApiError::Internal("Failed to delete studio".to_string())
        })?;
    
    Ok(success_message("Studio deleted successfully"))
}

// ============ Series Handlers ============

/// 获取系列列表
pub async fn list_series_handler(
    Query(params): Query<ListParams>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let response = database::list_series(
        state.database.pool(),
        params.studio_id.as_deref(),
        params.limit,
        params.offset,
    ).await
        .map_err(|e| {
            tracing::error!("Failed to list series: {}", e);
            ApiError::Internal("Failed to retrieve series".to_string())
        })?;
    
    Ok(success(response))
}

/// 获取单个系列
pub async fn get_series_handler(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let series = database::get_series_by_id(state.database.pool(), &id).await
        .map_err(|_| ApiError::NotFound("Series not found".to_string()))?;
    
    let studio_name = if let Some(ref studio_id) = series.studio_id {
        database::get_studio_by_id(state.database.pool(), studio_id)
            .await
            .ok()
            .map(|s| s.name)
    } else {
        None
    };
    
    Ok(success(SeriesWithStudio { series, studio_name }))
}

/// 创建系列
pub async fn create_series_handler(
    State(state): State<AppState>,
    Json(payload): Json<CreateSeriesRequest>,
) -> ApiResult<impl IntoResponse> {
    if payload.name.trim().is_empty() {
        return Err(ApiError::Validation("Series name cannot be empty".to_string()));
    }
    
    let series = database::create_series(state.database.pool(), payload).await
        .map_err(|e| {
            tracing::error!("Failed to create series: {}", e);
            if e.to_string().contains("UNIQUE constraint") {
                ApiError::Conflict("Series already exists".to_string())
            } else {
                ApiError::Internal("Failed to create series".to_string())
            }
        })?;
    
    Ok(success(series))
}

/// 更新系列
pub async fn update_series_handler(
    Path(id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateSeriesRequest>,
) -> ApiResult<impl IntoResponse> {
    let series = database::update_series(state.database.pool(), &id, payload).await
        .map_err(|e| {
            tracing::error!("Failed to update series: {}", e);
            ApiError::Internal("Failed to update series".to_string())
        })?;
    
    Ok(success(series))
}

/// 删除系列
pub async fn delete_series_handler(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    database::delete_series(state.database.pool(), &id).await
        .map_err(|e| {
            tracing::error!("Failed to delete series: {}", e);
            ApiError::Internal("Failed to delete series".to_string())
        })?;
    
    Ok(success_message("Series deleted successfully"))
}

/// 同步所有计数
pub async fn sync_counts_handler(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    database::sync_all_counts(state.database.pool()).await
        .map_err(|e| {
            tracing::error!("Failed to sync counts: {}", e);
            ApiError::Internal("Failed to sync counts".to_string())
        })?;
    
    Ok(success_message("Counts synced successfully"))
}

// ============ Search Handlers ============

/// 搜索厂商（模糊匹配）
pub async fn search_studios_handler(
    Query(params): Query<SearchParams>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    if params.q.trim().is_empty() {
        return Ok(success(Vec::<Studio>::new()));
    }
    
    let studios = database::search_studios(state.database.pool(), &params.q, params.limit).await
        .map_err(|e| {
            tracing::error!("Failed to search studios: {}", e);
            ApiError::Internal("Failed to search studios".to_string())
        })?;
    
    Ok(success(studios))
}

/// 搜索系列（模糊匹配）
pub async fn search_series_handler(
    Query(params): Query<SearchParams>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    if params.q.trim().is_empty() {
        return Ok(success(Vec::<SeriesWithStudio>::new()));
    }
    
    let series = database::search_series(
        state.database.pool(),
        &params.q,
        params.studio_id.as_deref(),
        params.limit,
    ).await
        .map_err(|e| {
            tracing::error!("Failed to search series: {}", e);
            ApiError::Internal("Failed to search series".to_string())
        })?;
    
    Ok(success(series))
}
