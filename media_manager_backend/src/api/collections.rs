use axum::{
    extract::{Path, State},
    response::IntoResponse,
    Json,
};

use crate::models::{
    AddToCollectionRequest, WatchStatus, CollectionResponse
};
use super::AppState;
use super::error::{ApiError, ApiResult};
use super::response::{success, success_message};

pub async fn get_collections(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let collections = state.db_service.get_collections().await
        .map_err(|e| {
            tracing::error!("Failed to get collections: {}", e);
            ApiError::Internal("Failed to retrieve collections".to_string())
        })?;
    
    let responses: Vec<CollectionResponse> = collections
        .into_iter()
        .map(CollectionResponse::from)
        .collect();
    
    Ok(success(responses))
}

pub async fn add_to_collection(
    State(state): State<AppState>,
    Json(payload): Json<AddToCollectionRequest>,
) -> ApiResult<impl IntoResponse> {
    // 验证输入
    if payload.media_id.trim().is_empty() {
        return Err(ApiError::Validation("Media ID cannot be empty".to_string()));
    }
    
    let watch_status = payload.watch_status.unwrap_or(WatchStatus::WantToWatch);
    
    let collection = state.db_service.add_to_collection(payload.media_id, watch_status).await
        .map_err(|e| {
            tracing::error!("Failed to add to collection: {}", e);
            let error_msg = e.to_string();
            if error_msg.contains("not found") {
                ApiError::NotFound("Media not found".to_string())
            } else if error_msg.contains("already in collection") {
                ApiError::Conflict("Media already in collection".to_string())
            } else {
                ApiError::Internal("Failed to add to collection".to_string())
            }
        })?;
    
    let response = CollectionResponse::from(collection);
    Ok(success(response))
}

pub async fn remove_from_collection(
    Path(media_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    state.db_service.remove_from_collection(&media_id).await
        .map_err(|e| {
            tracing::error!("Failed to remove from collection: {}", e);
            let error_msg = e.to_string();
            if error_msg.contains("not in collection") {
                ApiError::NotFound("Media not in collection".to_string())
            } else {
                ApiError::Internal("Failed to remove from collection".to_string())
            }
        })?;
    
    Ok(success_message("Removed from collection successfully"))
}

pub async fn update_collection_status(
    Path(media_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateCollectionRequest>,
) -> ApiResult<impl IntoResponse> {
    let watch_status = payload.watch_status.unwrap_or(WatchStatus::WantToWatch);
    let progress = payload.progress;
    
    state.db_service.update_collection(&media_id, watch_status, progress).await
        .map_err(|e| {
            tracing::error!("Failed to update collection: {}", e);
            let error_msg = e.to_string();
            if error_msg.contains("not found") {
                ApiError::NotFound("Collection not found".to_string())
            } else {
                ApiError::Internal("Failed to update collection".to_string())
            }
        })?;
    
    Ok(success_message("Collection updated successfully"))
}

#[derive(serde::Deserialize)]
pub struct UpdateCollectionRequest {
    pub watch_status: Option<WatchStatus>,
    pub progress: Option<f32>,
}