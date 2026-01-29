// 缓存管理 API
//
// 提供缓存配置管理的 HTTP API 端点，包括：
// - 获取缓存配置
// - 更新缓存配置
// - 更新单个刮削器配置

use axum::{
    extract::{Path, State},
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::services::cache::{CacheConfig, CacheService, ConfigManager, ScraperCacheConfig};

use super::error::{ApiError, ApiResult};
use super::response::success;
use super::AppState;

/// 缓存配置状态（用于依赖注入）
#[derive(Clone)]
pub struct CacheConfigState {
    pub config_manager: Arc<ConfigManager>,
}

/// 获取缓存配置
///
/// # 端点
/// GET /api/cache/config
///
/// # 响应
/// ```json
/// {
///   "success": true,
///   "data": {
///     "global_cache_enabled": false,
///     "scrapers": {
///       "maturenl": {
///         "cache_enabled": true,
///         "auto_enabled": true,
///         "auto_enabled_at": "2026-01-27T15:30:00Z",
///         "cache_fields": ["poster", "backdrop"]
///       }
///     }
///   }
/// }
/// ```
pub async fn get_cache_config(
    State(state): State<Arc<CacheConfigState>>,
) -> Result<impl IntoResponse, ApiError> {
    let config = state.config_manager.get_config().await;

    tracing::debug!("获取缓存配置成功");

    Ok(success(config))
}

/// 更新缓存配置请求体
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateCacheConfigRequest {
    /// 全局缓存开关
    pub global_cache_enabled: bool,

    /// 刮削器配置（可选，如果不提供则保持原有配置）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scrapers: Option<std::collections::HashMap<String, ScraperCacheConfig>>,
}

/// 更新缓存配置
///
/// # 端点
/// PUT /api/cache/config
///
/// # 请求体
/// ```json
/// {
///   "global_cache_enabled": false,
///   "scrapers": {
///     "maturenl": {
///       "cache_enabled": true,
///       "auto_enabled": false,
///       "cache_fields": ["poster", "backdrop", "preview"]
///     }
///   }
/// }
/// ```
///
/// # 响应
/// ```json
/// {
///   "success": true,
///   "data": {
///     "global_cache_enabled": false,
///     "scrapers": { ... }
///   }
/// }
/// ```
pub async fn update_cache_config(
    State(state): State<Arc<CacheConfigState>>,
    Json(request): Json<UpdateCacheConfigRequest>,
) -> ApiResult<impl IntoResponse> {
    // 更新全局缓存开关
    state
        .config_manager
        .update_global_cache(request.global_cache_enabled)
        .await
        .map_err(|e| {
            tracing::error!("更新全局缓存开关失败: {}", e);
            ApiError::Internal(format!("更新全局缓存开关失败: {}", e))
        })?;

    // 如果提供了刮削器配置，逐个更新
    if let Some(scrapers) = request.scrapers {
        for (scraper_name, scraper_config) in scrapers {
            state
                .config_manager
                .update_scraper_config(&scraper_name, scraper_config)
                .await
                .map_err(|e| {
                    tracing::error!("更新刮削器 {} 配置失败: {}", scraper_name, e);
                    ApiError::Internal(format!("更新刮削器配置失败: {}", e))
                })?;
        }
    }

    // 返回更新后的配置
    let updated_config = state.config_manager.get_config().await;

    tracing::info!("缓存配置更新成功");

    Ok(success(updated_config))
}

/// 更新单个刮削器配置
///
/// # 端点
/// PUT /api/cache/config/scraper/{scraper_name}
///
/// # 路径参数
/// - `scraper_name`: 刮削器名称（如 "maturenl"）
///
/// # 请求体
/// ```json
/// {
///   "cache_enabled": true,
///   "auto_enabled": false,
///   "cache_fields": ["poster", "backdrop"]
/// }
/// ```
///
/// # 响应
/// ```json
/// {
///   "success": true,
///   "data": {
///     "cache_enabled": true,
///     "auto_enabled": false,
///     "cache_fields": ["poster", "backdrop"]
///   }
/// }
/// ```
pub async fn update_scraper_config(
    State(state): State<Arc<CacheConfigState>>,
    Path(scraper_name): Path<String>,
    Json(scraper_config): Json<ScraperCacheConfig>,
) -> ApiResult<impl IntoResponse> {
    // 验证刮削器名称
    if scraper_name.trim().is_empty() {
        return Err(ApiError::Validation("刮削器名称不能为空".to_string()));
    }

    // 更新刮削器配置
    state
        .config_manager
        .update_scraper_config(&scraper_name, scraper_config.clone())
        .await
        .map_err(|e| {
            tracing::error!("更新刮削器 {} 配置失败: {}", scraper_name, e);
            ApiError::Internal(format!("更新刮削器配置失败: {}", e))
        })?;

    tracing::info!("刮削器 {} 配置更新成功", scraper_name);

    Ok(success(scraper_config))
}

/// 获取缓存统计
///
/// # 端点
/// GET /api/cache/stats
pub async fn get_cache_stats(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    tracing::info!("获取缓存统计");

    let stats = state
        .cache_service
        .get_cache_stats()
        .await
        .map_err(|e| {
            tracing::error!("获取缓存统计失败: {}", e);
            ApiError::Internal(format!("获取缓存统计失败: {}", e))
        })?;

    tracing::debug!(
        "缓存统计: 总大小={} 字节, 总文件数={}, 刮削器数={}",
        stats.total_size,
        stats.total_files,
        stats.by_scraper.len()
    );

    Ok(success(stats))
}

/// 清理指定媒体的缓存
///
/// # 端点
/// DELETE /api/media/{id}/cache
pub async fn clear_media_cache(
    State(state): State<AppState>,
    Path(media_id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    tracing::info!("清理媒体缓存: media_id={}", media_id);

    // 验证媒体 ID
    if media_id.trim().is_empty() {
        return Err(ApiError::Validation("媒体 ID 不能为空".to_string()));
    }

    // 清理缓存
    state
        .cache_service
        .clear_media_cache(&media_id)
        .await
        .map_err(|e| {
            tracing::error!("清理媒体缓存失败: media_id={}, error={}", media_id, e);
            ApiError::Internal(format!("清理媒体缓存失败: {}", e))
        })?;

    tracing::info!("媒体缓存清理成功: media_id={}", media_id);

    Ok(success(serde_json::json!({
        "message": "媒体缓存已清理",
        "media_id": media_id
    })))
}

/// 清理所有缓存
///
/// # 端点
/// DELETE /api/cache/all
pub async fn clear_all_cache(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    tracing::info!("清理所有缓存");

    // 清理缓存
    state
        .cache_service
        .clear_all_cache()
        .await
        .map_err(|e| {
            tracing::error!("清理所有缓存失败: {}", e);
            ApiError::Internal(format!("清理所有缓存失败: {}", e))
        })?;

    tracing::info!("所有缓存清理成功");

    Ok(success(serde_json::json!({
        "message": "所有缓存已清理"
    })))
}

/// 清理孤立缓存
///
/// # 端点
/// DELETE /api/cache/orphaned
pub async fn clear_orphaned_cache(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    tracing::info!("清理孤立缓存");

    // 清理孤立缓存
    state
        .cache_service
        .clear_orphaned_cache()
        .await
        .map_err(|e| {
            tracing::error!("清理孤立缓存失败: {}", e);
            ApiError::Internal(format!("清理孤立缓存失败: {}", e))
        })?;

    tracing::info!("孤立缓存清理成功");

    Ok(success(serde_json::json!({
        "message": "孤立缓存已清理"
    })))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::cache::CacheField;
    use std::path::PathBuf;

    /// 创建测试用的配置管理器
    async fn create_test_config_manager() -> Arc<ConfigManager> {
        let temp_dir = tempfile::TempDir::new().unwrap();
        let config_path = temp_dir.path().join("test_cache_config.json");
        Arc::new(ConfigManager::load(Some(config_path)).await.unwrap())
    }

    /// 创建测试用的缓存服务
    async fn create_test_cache_service() -> Arc<CacheService> {
        let temp_dir = tempfile::TempDir::new().unwrap();
        let cache_dir = temp_dir.path().join("cache");
        
        // 创建内存数据库
        let db_pool = sqlx::SqlitePool::connect(":memory:").await.unwrap();
        
        // 创建 media_items 表
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS media_items (
                id TEXT PRIMARY KEY,
                scraper_name TEXT,
                poster_url TEXT,
                backdrop_url TEXT,
                preview_urls TEXT,
                preview_video_urls TEXT
            )
            "#,
        )
        .execute(&db_pool)
        .await
        .unwrap();
        
        Arc::new(CacheService::new(cache_dir, db_pool).await.unwrap())
    }

    #[tokio::test]
    async fn test_get_cache_config() {
        let config_manager = create_test_config_manager().await;
        let state = Arc::new(CacheConfigState {
            config_manager: config_manager.clone(),
        });

        // 调用 API
        let response = get_cache_config(State(state)).await;

        // 验证响应
        assert!(response.is_ok());
    }

    #[tokio::test]
    async fn test_update_cache_config() {
        let config_manager = create_test_config_manager().await;
        let state = Arc::new(CacheConfigState {
            config_manager: config_manager.clone(),
        });

        // 创建更新请求
        let request = UpdateCacheConfigRequest {
            global_cache_enabled: true,
            scrapers: None,
        };

        // 调用 API
        let response = update_cache_config(State(state.clone()), Json(request)).await;

        // 验证响应
        assert!(response.is_ok());

        // 验证配置已更新
        let config = config_manager.get_config().await;
        assert!(config.global_cache_enabled);
    }

    #[tokio::test]
    async fn test_update_scraper_config() {
        let config_manager = create_test_config_manager().await;
        let state = Arc::new(CacheConfigState {
            config_manager: config_manager.clone(),
        });

        // 创建刮削器配置
        let scraper_config = ScraperCacheConfig {
            cache_enabled: true,
            auto_enabled: false,
            auto_enabled_at: None,
            cache_fields: vec![CacheField::Poster, CacheField::Backdrop],
        };

        // 调用 API
        let response = update_scraper_config(
            State(state.clone()),
            Path("maturenl".to_string()),
            Json(scraper_config.clone()),
        )
        .await;

        // 验证响应
        assert!(response.is_ok());

        // 验证配置已更新
        let config = config_manager.get_config().await;
        assert!(config.scrapers.contains_key("maturenl"));
        assert!(config.scrapers.get("maturenl").unwrap().cache_enabled);
    }

    #[tokio::test]
    async fn test_update_scraper_config_empty_name() {
        let config_manager = create_test_config_manager().await;
        let state = Arc::new(CacheConfigState {
            config_manager: config_manager.clone(),
        });

        let scraper_config = ScraperCacheConfig::default();

        // 调用 API（空名称）
        let result = update_scraper_config(
            State(state),
            Path("".to_string()),
            Json(scraper_config),
        )
        .await;

        // 应该返回验证错误
        assert!(result.is_err());
        if let Err(ApiError::Validation(_)) = result {
            // 正确的错误类型
        } else {
            panic!("Expected validation error");
        }
    }

    #[tokio::test]
    async fn test_update_cache_config_with_scrapers() {
        let config_manager = create_test_config_manager().await;
        let state = Arc::new(CacheConfigState {
            config_manager: config_manager.clone(),
        });

        // 创建更新请求（包含刮削器配置）
        let mut scrapers = std::collections::HashMap::new();
        scrapers.insert(
            "maturenl".to_string(),
            ScraperCacheConfig {
                cache_enabled: true,
                auto_enabled: false,
                auto_enabled_at: None,
                cache_fields: vec![CacheField::Poster],
            },
        );

        let request = UpdateCacheConfigRequest {
            global_cache_enabled: false,
            scrapers: Some(scrapers),
        };

        // 调用 API
        let response = update_cache_config(State(state.clone()), Json(request)).await;

        // 验证响应
        assert!(response.is_ok());

        // 验证配置已更新
        let config = config_manager.get_config().await;
        assert!(!config.global_cache_enabled);
        assert!(config.scrapers.contains_key("maturenl"));
        assert!(config.scrapers.get("maturenl").unwrap().cache_enabled);
    }
}
