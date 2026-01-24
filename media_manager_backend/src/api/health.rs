use axum::{
    extract::State,
    response::IntoResponse,
};
use serde_json::json;

use super::AppState;
use super::error::{ApiError, ApiResult};
use super::response::success;

/// 健康检查端点
pub async fn health_check(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    // 检查数据库连接
    state.database.verify_integrity().await
        .map_err(|e| {
            tracing::error!("Health check failed: {}", e);
            ApiError::Internal("Database connection failed".to_string())
        })?;
    
    let tmdb_status = if state.external_client.is_tmdb_available() {
        "available"
    } else {
        "not_configured"
    };
    
    Ok(success(json!({
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "version": "1.0.0",
        "database": "connected",
        "tmdb_api": tmdb_status
    })))
}

/// 获取系统统计信息
pub async fn get_stats(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let stats = state.db_service.get_statistics().await
        .map_err(|e| {
            tracing::error!("Failed to get statistics: {}", e);
            ApiError::Internal("Failed to retrieve statistics".to_string())
        })?;
    
    let db_stats = state.database.get_stats().await
        .map_err(|e| ApiError::Internal(format!("Failed to get database stats: {}", e)))?;
    
    let cache_stats = state.external_client.get_cache_stats();
        
    Ok(success(json!({
        "media_count": stats.total_media,
        "collection_count": stats.total_collections,
        "tag_count": stats.total_tags,
        "database_size_mb": db_stats.database_size_mb(),
        "cache_entries": db_stats.cache_count,
        "tmdb_cache": {
            "search_cache_size": cache_stats.search_cache_size,
            "details_cache_size": cache_stats.details_cache_size,
            "popular_cache_size": cache_stats.popular_cache_size
        },
        "popular_tags": stats.popular_tags.iter().take(5).map(|tag| json!({
            "name": tag.name,
            "usage_count": tag.usage_count
        })).collect::<Vec<_>>(),
        "timestamp": chrono::Utc::now().to_rfc3339()
    })))
}

/// 清理缓存
pub async fn cleanup_cache(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    state.external_client.cleanup_cache();
    
    Ok(success(json!({
        "message": "Cache cleanup completed",
        "timestamp": chrono::Utc::now().to_rfc3339()
    })))
}

/// 清空所有缓存
pub async fn clear_cache(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    state.external_client.clear_cache();
    
    Ok(success(json!({
        "message": "All caches cleared",
        "timestamp": chrono::Utc::now().to_rfc3339()
    })))
}