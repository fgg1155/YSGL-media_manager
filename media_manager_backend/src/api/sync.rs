use axum::{
    extract::State,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use chrono::{DateTime, Utc};

use super::error::ApiResult;
use super::response::success;

/// 同步触发状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncTrigger {
    pub requested: bool,
    pub requested_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub device_id: Option<String>,
}

/// 全局同步触发状态
pub struct SyncTriggerState {
    pub trigger: Arc<RwLock<SyncTrigger>>,
}

impl SyncTriggerState {
    pub fn new() -> Self {
        Self {
            trigger: Arc::new(RwLock::new(SyncTrigger {
                requested: false,
                requested_at: None,
                completed_at: None,
                device_id: None,
            })),
        }
    }
}

/// 触发同步请求（PC 端调用）
pub async fn trigger_sync(
    State(state): State<Arc<SyncTriggerState>>,
) -> ApiResult<impl IntoResponse> {
    let mut trigger = state.trigger.write().await;
    trigger.requested = true;
    trigger.requested_at = Some(Utc::now());
    trigger.device_id = None;
    
    Ok(success(trigger.clone()))
}

/// 检查是否有同步请求（移动端调用）
pub async fn check_sync_request(
    State(state): State<Arc<SyncTriggerState>>,
) -> ApiResult<impl IntoResponse> {
    let trigger = state.trigger.read().await;
    Ok(success(trigger.clone()))
}

/// 完成同步（移动端调用）
#[derive(Debug, Deserialize)]
pub struct CompleteSyncRequest {
    pub device_id: String,
}

pub async fn complete_sync(
    State(state): State<Arc<SyncTriggerState>>,
    Json(req): Json<CompleteSyncRequest>,
) -> ApiResult<impl IntoResponse> {
    let mut trigger = state.trigger.write().await;
    trigger.requested = false;
    trigger.completed_at = Some(Utc::now());
    trigger.device_id = Some(req.device_id);
    
    Ok(success(trigger.clone()))
}

/// 获取同步状态（Web 端查询）
pub async fn get_sync_status(
    State(state): State<Arc<SyncTriggerState>>,
) -> ApiResult<impl IntoResponse> {
    let trigger = state.trigger.read().await;
    Ok(success(trigger.clone()))
}
