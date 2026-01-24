use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use tracing::{info, warn, error};

use super::error::{ApiError, ApiResult};
use super::response::{success, success_message};
use super::scrape::{MEDIA_SCRAPE_PROGRESS, MediaScrapeProgress, MediaScrapeResponse};

/// 自定义反序列化：支持字符串和布尔值
fn deserialize_bool_from_anything<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde::de::{self, Deserialize};
    
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum BoolOrString {
        Bool(bool),
        String(String),
    }
    
    match BoolOrString::deserialize(deserializer)? {
        BoolOrString::Bool(b) => Ok(b),
        BoolOrString::String(s) => {
            match s.to_lowercase().as_str() {
                "true" | "1" | "yes" => Ok(true),
                "false" | "0" | "no" | "" => Ok(false),
                _ => Err(de::Error::custom(format!("Invalid boolean string: {}", s))),
            }
        }
    }
}

use crate::{
    api::AppState,
    database::{
        create_actor, get_actor, update_actor, delete_actor, list_actors,
        get_actor_with_filmography, add_actor_to_media, remove_actor_from_media,
        get_actors_for_media, find_actor_by_name, DatabaseRepository,
    },
    models::{
        CreateActorRequest, UpdateActorRequest, AddActorToMediaRequest,
        ActorSearchFilters,
    },
};

#[derive(Debug, Deserialize)]
pub struct ListActorsQuery {
    pub query: Option<String>,
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

/// GET /api/actors - 列出演员
pub async fn list_actors_handler(
    State(state): State<AppState>,
    Query(params): Query<ListActorsQuery>,
) -> ApiResult<impl IntoResponse> {
    let filters = ActorSearchFilters {
        query: params.query,
        limit: params.limit,
        offset: params.offset,
    };
    
    let response = list_actors(state.database.pool(), &filters).await
        .map_err(|e| {
            tracing::error!("Failed to list actors: {}", e);
            ApiError::Internal("Failed to retrieve actors".to_string())
        })?;
    
    Ok(success(response))
}

/// GET /api/actors/:id - 获取演员详情（包含作品列表）
pub async fn get_actor_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    let actor = get_actor_with_filmography(state.database.pool(), &id).await
        .map_err(|e| {
            tracing::error!("Failed to get actor: {}", e);
            ApiError::Internal("Failed to retrieve actor".to_string())
        })?
        .ok_or_else(|| ApiError::NotFound("Actor not found".to_string()))?;
    
    Ok(success(actor))
}

/// POST /api/actors - 创建或更新演员
pub async fn create_actor_handler(
    State(state): State<AppState>,
    Json(payload): Json<CreateActorRequest>,
) -> ApiResult<impl IntoResponse> {
    if payload.name.trim().is_empty() {
        return Err(ApiError::Validation("Actor name cannot be empty".to_string()));
    }
    
    // 记录收到的数据
    tracing::info!("Received actor data: name={}, photo_url={:?}, backdrop_url={:?}", 
        payload.name, payload.photo_url, payload.backdrop_url);
    
    // 先查找是否已存在同名演员
    match find_actor_by_name(state.database.pool(), &payload.name).await {
        Ok(Some(existing_actor)) => {
            // 演员已存在，更新信息
            tracing::info!("Found existing actor: {} (id={})", existing_actor.name, existing_actor.id);
            let update_request = UpdateActorRequest {
                name: None, // 不更新名字
                avatar_url: payload.avatar_url,
                photo_url: payload.photo_url,
                poster_url: payload.poster_url,
                backdrop_url: payload.backdrop_url,
                biography: payload.biography,
                birth_date: payload.birth_date,
                nationality: payload.nationality,
            };
            
            let actor = update_actor(state.database.pool(), &existing_actor.id, update_request).await
                .map_err(|e| {
                    tracing::error!("Failed to update actor: {}", e);
                    ApiError::Internal("Failed to update actor".to_string())
                })?
                .ok_or_else(|| ApiError::NotFound("Actor not found".to_string()))?;
            
            tracing::info!("Updated existing actor: {} - photo_url={:?}, backdrop_url={:?}", 
                actor.name, actor.photo_url, actor.backdrop_url);
            Ok(success(actor))
        },
        Ok(None) => {
            // 演员不存在，创建新演员
            let actor = create_actor(state.database.pool(), payload).await
                .map_err(|e| {
                    // 检查是否是 UUID 验证错误
                    if let sqlx::Error::Protocol(msg) = &e {
                        if msg.contains("Invalid ID format") || msg.contains("InvalidId") {
                            tracing::error!("Invalid UUID format in create actor request: {}", msg);
                            return ApiError::Validation("Invalid ID format".to_string());
                        }
                    }
                    tracing::error!("Failed to create actor: {}", e);
                    ApiError::Internal("Failed to create actor".to_string())
                })?;
            
            tracing::info!("Created new actor: {} - photo_url={:?}, backdrop_url={:?}", 
                actor.name, actor.photo_url, actor.backdrop_url);
            Ok(success(actor))
        },
        Err(e) => {
            tracing::error!("Failed to find actor by name: {}", e);
            Err(ApiError::Internal("Failed to find actor".to_string()))
        }
    }
}

/// PUT /api/actors/:id - 更新演员
pub async fn update_actor_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<UpdateActorRequest>,
) -> ApiResult<impl IntoResponse> {
    let actor = update_actor(state.database.pool(), &id, payload).await
        .map_err(|e| {
            tracing::error!("Failed to update actor: {}", e);
            ApiError::Internal("Failed to update actor".to_string())
        })?
        .ok_or_else(|| ApiError::NotFound("Actor not found".to_string()))?;
    
    Ok(success(actor))
}

/// DELETE /api/actors/:id - 删除演员
pub async fn delete_actor_handler(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    let deleted = delete_actor(state.database.pool(), &id).await
        .map_err(|e| {
            tracing::error!("Failed to delete actor: {}", e);
            ApiError::Internal("Failed to delete actor".to_string())
        })?;
    
    if deleted {
        Ok(success_message("Actor deleted successfully"))
    } else {
        Err(ApiError::NotFound("Actor not found".to_string()))
    }
}

/// POST /api/media/:id/actors - 添加演员到媒体
pub async fn add_actor_to_media_handler(
    State(state): State<AppState>,
    Path(media_id): Path<String>,
    Json(payload): Json<AddActorToMediaRequest>,
) -> ApiResult<impl IntoResponse> {
    // 验证媒体存在
    state.database.repository().get_media_by_id(&media_id).await
        .map_err(|e| {
            tracing::error!("Failed to get media: {}", e);
            ApiError::Internal("Failed to verify media".to_string())
        })?
        .ok_or_else(|| ApiError::NotFound("Media not found".to_string()))?;
    
    // 验证演员存在
    get_actor(state.database.pool(), &payload.actor_id).await
        .map_err(|e| {
            tracing::error!("Failed to get actor: {}", e);
            ApiError::Internal("Failed to verify actor".to_string())
        })?
        .ok_or_else(|| ApiError::Validation("Actor not found".to_string()))?;
    
    add_actor_to_media(
        state.database.pool(),
        &payload.actor_id,
        &media_id,
        payload.character_name,
        payload.role,
    ).await
        .map_err(|e| {
            tracing::error!("Failed to add actor to media: {}", e);
            ApiError::Internal("Failed to add actor to media".to_string())
        })?;
    
    Ok(success_message("Actor added to media successfully"))
}

/// DELETE /api/media/:media_id/actors/:actor_id - 从媒体移除演员
pub async fn remove_actor_from_media_handler(
    State(state): State<AppState>,
    Path((media_id, actor_id)): Path<(String, String)>,
) -> ApiResult<impl IntoResponse> {
    let removed = remove_actor_from_media(state.database.pool(), &actor_id, &media_id).await
        .map_err(|e| {
            tracing::error!("Failed to remove actor from media: {}", e);
            ApiError::Internal("Failed to remove actor from media".to_string())
        })?;
    
    if removed {
        Ok(success_message("Actor removed from media successfully"))
    } else {
        Err(ApiError::NotFound("Actor-media relationship not found".to_string()))
    }
}

/// GET /api/media/:id/actors - 获取媒体的所有演员
pub async fn get_media_actors_handler(
    State(state): State<AppState>,
    Path(media_id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    let actors = get_actors_for_media(state.database.pool(), &media_id).await
        .map_err(|e| {
            tracing::error!("Failed to get media actors: {}", e);
            ApiError::Internal("Failed to retrieve media actors".to_string())
        })?;
    
    Ok(success(actors))
}

/// 模式验证函数
fn validate_mode(mode: &str) -> Result<(), String> {
    match mode.to_lowercase().as_str() {
        "replace" | "supplement" => Ok(()),
        _ => Err(format!("Invalid mode: {}. Must be 'replace' or 'supplement'", mode)),
    }
}

/// 统一的单个演员刮削端点
/// POST /api/scrape/actor/:actor_id
pub async fn scrape_actor(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(request): Json<ScrapeActorRequest>,
) -> ApiResult<impl IntoResponse> {
    use serde_json::json;
    
    // 1. 验证 mode 参数
    validate_mode(&request.mode)
        .map_err(|e| ApiError::Validation(format!("Invalid mode parameter: {}", e)))?;
    
    // 2. 获取演员信息
    let actor = get_actor(state.database.pool(), &id)
        .await?
        .ok_or_else(|| ApiError::NotFound(format!("Actor not found: {}", id)))?;
    
    // 3. 确定刮削关键词（优先使用请求中的name，否则使用演员的名字）
    let actor_name = request.name.unwrap_or_else(|| actor.name.clone());
    
    tracing::info!("刮削演员: {} (id={}, mode={})", actor_name, id, request.mode);
    
    // 4. 调用插件刮削
    let request_json = json!({
        "action": "scrape_actor",
        "actor_name": actor_name
    });
    
    let request_str = serde_json::to_string(&request_json)
        .map_err(|e| ApiError::Internal(format!("Failed to serialize request: {}", e)))?;
    
    // 调用 media_scraper 插件
    let plugin_manager = &state.plugin_manager;
    let plugin_manager_guard = plugin_manager.read().await;
    let plugins = plugin_manager_guard.list_plugins();
    let media_scraper = plugins.iter()
        .find(|p| p.config.id == "media_scraper")
        .ok_or_else(|| ApiError::ExternalService("media_scraper plugin not found".to_string()))?;
    
    // 执行插件调用
    use tokio::process::Command;
    use tokio::io::AsyncWriteExt;
    use std::process::Stdio;
    
    let mut child = Command::new(&media_scraper.executable_path)
        .current_dir(&media_scraper.path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| ApiError::ExternalService(format!("Failed to spawn plugin process: {}", e)))?;
    
    // 写入请求
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(request_str.as_bytes()).await
            .map_err(|e| ApiError::ExternalService(format!("Failed to write to plugin stdin: {}", e)))?;
        stdin.write_all(b"\n").await
            .map_err(|e| ApiError::ExternalService(format!("Failed to write newline to plugin stdin: {}", e)))?;
        drop(stdin);
    }
    
    // 读取响应（超时30秒）
    let output = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        child.wait_with_output()
    ).await
        .map_err(|_| ApiError::ExternalService("Plugin timeout after 30 seconds".to_string()))?
        .map_err(|e| ApiError::ExternalService(format!("Failed to get plugin output: {}", e)))?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(ApiError::ExternalService(format!("Plugin failed: {}", stderr)));
    }
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    tracing::debug!("Plugin response: {}", stdout);
    
    // 解析响应
    #[derive(serde::Deserialize)]
    struct PluginResponse {
        success: bool,
        data: Option<serde_json::Value>,
        error: Option<String>,
    }
    
    let response: PluginResponse = stdout.lines()
        .find(|line| line.trim().starts_with('{'))
        .and_then(|line| serde_json::from_str(line).ok())
        .ok_or_else(|| ApiError::ExternalService("No valid JSON response from plugin".to_string()))?;
    
    if !response.success {
        let error_msg = response.error.unwrap_or_else(|| "Unknown error".to_string());
        return Err(ApiError::ExternalService(format!("Plugin returned error: {}", error_msg)));
    }
    
    let scraped_data = response.data
        .ok_or_else(|| ApiError::ExternalService("Plugin returned no data".to_string()))?;
    
    // 5. 根据 mode 参数构建更新请求
    let is_replace_mode = request.mode.to_lowercase() == "replace";
    
    // 获取刮削数据的辅助函数
    let get_str = |key: &str| -> Option<String> {
        scraped_data.get(key)
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(String::from)
    };
    
    let get_photo_urls = || -> Option<String> {
        scraped_data.get("photo_urls")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str())
                    .collect::<Vec<_>>()
                    .join(",")
            })
            .filter(|s| !s.is_empty())
    };
    
    if is_replace_mode {
        // Replace 模式：刮削数据有值时覆盖，无值时保留原数据
        let mut updated_actor = actor.clone();
        
        // 有值则覆盖，无值则保留原数据
        if let Some(val) = get_str("avatar_url") {
            updated_actor.avatar_url = Some(val);
        }
        if let Some(val) = get_photo_urls() {
            updated_actor.photo_url = Some(val);
        }
        if let Some(val) = get_str("poster_url") {
            updated_actor.poster_url = Some(val);
        }
        if let Some(val) = get_str("backdrop_url") {
            updated_actor.backdrop_url = Some(val);
        }
        if let Some(val) = get_str("biography") {
            updated_actor.biography = Some(val);
        }
        if let Some(val) = get_str("birth_date") {
            updated_actor.birth_date = Some(val);
        }
        if let Some(val) = get_str("nationality") {
            updated_actor.nationality = Some(val);
        }
        updated_actor.updated_at = chrono::Utc::now();
        
        // 直接更新数据库
        crate::database::update_actor_direct(state.database.pool(), &updated_actor)
            .await
            .map_err(|e| ApiError::Internal(format!("Failed to update actor: {}", e)))?;
        
        tracing::info!("Successfully replaced actor: {} (id={}, mode=replace)", updated_actor.name, id);
        
        Ok(success(updated_actor))
    } else {
        // Supplement 模式：只更新空字段
        let update_request = UpdateActorRequest {
            name: None,
            avatar_url: if actor.avatar_url.is_none() || actor.avatar_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_str("avatar_url")
            } else {
                None
            },
            photo_url: if actor.photo_url.is_none() || actor.photo_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_photo_urls()
            } else {
                None
            },
            poster_url: if actor.poster_url.is_none() || actor.poster_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_str("poster_url")
            } else {
                None
            },
            backdrop_url: if actor.backdrop_url.is_none() || actor.backdrop_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_str("backdrop_url")
            } else {
                None
            },
            biography: if actor.biography.is_none() || actor.biography.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_str("biography")
            } else {
                None
            },
            birth_date: if actor.birth_date.is_none() || actor.birth_date.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_str("birth_date")
            } else {
                None
            },
            nationality: if actor.nationality.is_none() || actor.nationality.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                get_str("nationality")
            } else {
                None
            },
        };
        
        // 6. 保存到数据库
        let updated_actor = update_actor(state.database.pool(), &id, update_request)
            .await?
            .ok_or_else(|| ApiError::NotFound(format!("Actor not found after update: {}", id)))?;
        
        tracing::info!("Successfully supplemented actor: {} (id={}, mode=supplement)", updated_actor.name, id);
        
        Ok(success(updated_actor))
    }
}

/// 单个演员刮削请求
#[derive(Debug, Deserialize)]
pub struct ScrapeActorRequest {
    /// 更新模式：replace（替换）或 supplement（补全）
    pub mode: String,
    /// 可选：指定演员名字进行刮削（如果不提供，使用演员自身的名字）
    pub name: Option<String>,
}

/// 批量演员刮削请求
#[derive(Debug, Deserialize)]
pub struct BatchScrapeActorRequest {
    /// 演员ID列表
    pub actor_ids: Vec<String>,
    /// 更新模式：replace（替换）或 supplement（补全）
    pub mode: String,
    /// 是否并发处理，默认false（串行）
    #[serde(default, deserialize_with = "deserialize_bool_from_anything")]
    pub concurrent: bool,
}

/// 统一的批量演员刮削端点（异步模式，返回 session_id）
/// POST /api/scrape/actor/batch
pub async fn batch_scrape_actor_unified(
    State(state): State<AppState>,
    Json(request): Json<BatchScrapeActorRequest>,
) -> Json<MediaScrapeResponse> {
    // 生成会话ID
    let session_id = uuid::Uuid::new_v4().to_string();
    info!("开始批量演员刮削，会话ID: {}, 数量: {}, 并发: {}", session_id, request.actor_ids.len(), request.concurrent);
    
    // 初始化进度跟踪（复用 MEDIA_SCRAPE_PROGRESS）
    {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        progress_map.insert(session_id.clone(), MediaScrapeProgress {
            status: "scraping".to_string(),
            message: Some("正在初始化演员刮削...".to_string()),
            current: 0,
            total: request.actor_ids.len() as i32,
            current_item: None,
            item_status: "pending".to_string(),
            success_count: 0,
            failed_count: 0,
            completed: false,
            concurrent: request.concurrent,
            processing_items: vec![],
        });
    }
    
    // 克隆需要的数据用于后台任务
    let session_id_clone = session_id.clone();
    let state_clone = state.clone();
    let request_clone = request;
    
    // 在后台任务中执行刮削
    tokio::spawn(async move {
        let result = process_batch_actor_scrape(state_clone, request_clone, session_id_clone).await;
        if let Err(e) = result {
            error!("后台批量演员刮削任务失败: {}", e);
        }
    });
    
    // 立即返回session_id，让前端开始轮询
    Json(MediaScrapeResponse {
        success: true,
        session_id,
        message: "批量演员刮削任务已启动".to_string(),
    })
}

/// 处理批量演员刮削（后台任务）
async fn process_batch_actor_scrape(
    state: AppState,
    request: BatchScrapeActorRequest,
    session_id: String,
) -> Result<(), String> {
    use serde_json::json;
    use tokio::io::{AsyncBufReadExt, BufReader};
    use std::process::Stdio;
    use tokio::process::Command;
    use tokio::io::AsyncWriteExt;
    
    info!("开始执行批量演员刮削: {} 个演员", request.actor_ids.len());
    
    // 验证 mode 参数
    if let Err(e) = validate_mode(&request.mode) {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.status = "failed".to_string();
            progress.message = Some(format!("参数错误: {}", e));
            progress.completed = true;
        }
        return Err(e);
    }
    
    // 收集演员名称和信息
    let mut actor_names = Vec::new();
    let mut actor_map = std::collections::HashMap::new();
    let mut actor_info_map = std::collections::HashMap::new();
    
    for actor_id in &request.actor_ids {
        match get_actor(state.database.pool(), actor_id).await {
            Ok(Some(actor)) => {
                actor_names.push(actor.name.clone());
                actor_map.insert(actor.name.clone(), actor_id.clone());
                actor_info_map.insert(actor_id.clone(), actor);
            }
            Ok(None) => {
                warn!("Actor not found: {}", actor_id);
            }
            Err(e) => {
                error!("Failed to get actor {}: {}", actor_id, e);
            }
        }
    }
    
    if actor_names.is_empty() {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.status = "completed".to_string();
            progress.message = Some("没有找到有效的演员".to_string());
            progress.completed = true;
        }
        return Ok(());
    }
    
    // 更新总数
    {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.total = actor_names.len() as i32;
        }
    }
    
    // 获取插件
    let plugin_manager = state.plugin_manager.read().await;
    let plugins = plugin_manager.list_plugins();
    let media_scraper = match plugins.iter().find(|p| p.config.id == "media_scraper") {
        Some(p) => p,
        None => {
            let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
            if let Some(progress) = progress_map.get_mut(&session_id) {
                progress.status = "failed".to_string();
                progress.message = Some("media_scraper 插件未找到".to_string());
                progress.completed = true;
            }
            return Err("Plugin not found".to_string());
        }
    };
    
    // 构建请求
    let request_json = json!({
        "action": "batch_scrape_actors",
        "actor_names": actor_names,
        "concurrent": request.concurrent
    });
    
    let request_str = serde_json::to_string(&request_json).map_err(|e| e.to_string())?;
    
    // 启动插件进程
    let mut child = Command::new(&media_scraper.executable_path)
        .current_dir(&media_scraper.path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    
    // 获取 stdout 和 stderr
    let stdout = child.stdout.take().ok_or("Failed to capture stdout")?;
    let stderr = child.stderr.take().ok_or("Failed to capture stderr")?;
    
    // 克隆 session_id 用于 stderr 读取任务
    let session_id_for_stderr = session_id.clone();
    
    // 启动 stderr 读取任务（读取进度）
    let stderr_task = tokio::spawn(async move {
        let mut stderr_reader = BufReader::new(stderr).lines();
        info!("Started actor scrape stderr reader task");
        
        while let Ok(Some(line)) = stderr_reader.next_line().await {
            let line = line.trim();
            
            // 检查是否是进度消息
            if let Some(json_str) = line.strip_prefix("PROGRESS:") {
                if let Ok(progress_data) = serde_json::from_str::<serde_json::Value>(json_str) {
                    let current = progress_data.get("current").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
                    let total = progress_data.get("total").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
                    let item_name = progress_data.get("item_name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    let status = progress_data.get("status").and_then(|v| v.as_str()).unwrap_or("scraping").to_string();
                    let error_msg = progress_data.get("error").and_then(|v| v.as_str()).map(String::from);
                    // 解析正在处理的项目列表（并发模式）
                    let processing_items: Vec<String> = progress_data.get("processing_items")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
                        .unwrap_or_default();
                    
                    info!("Actor scrape progress: {}/{} - {} ({})", current, total, item_name, status);
                    
                    // 更新进度
                    let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
                    if let Some(progress) = progress_map.get_mut(&session_id_for_stderr) {
                        progress.current = current;
                        progress.total = total;
                        progress.current_item = Some(item_name.clone());
                        progress.item_status = status.clone();
                        
                        // 更新正在处理的项目列表（并发模式）
                        if progress.concurrent && !processing_items.is_empty() {
                            progress.processing_items = processing_items;
                        } else if progress.concurrent && status == "scraping" && !item_name.is_empty() {
                            // 并发模式下，如果没有 processing_items，将当前项目添加到列表
                            if !progress.processing_items.contains(&item_name) {
                                progress.processing_items.push(item_name.clone());
                            }
                        }
                        
                        // 并发模式下，完成或失败时从列表中移除
                        if progress.concurrent && (status == "completed" || status == "failed") {
                            progress.processing_items.retain(|x| x != &item_name);
                        }
                        
                        // 更新成功/失败计数
                        if status == "completed" {
                            progress.success_count += 1;
                        } else if status == "failed" {
                            progress.failed_count += 1;
                        }
                        
                        // 更新消息
                        if let Some(err) = error_msg {
                            progress.message = Some(format!("刮削失败: {}", err));
                        } else if status == "scraping" {
                            if progress.concurrent {
                                let active_count = progress.processing_items.len();
                                progress.message = Some(format!("正在并发刮削 {} 个演员 ({}/{})", active_count, current, total));
                            } else {
                                progress.message = Some(format!("正在刮削 {}/{}", current, total));
                            }
                        } else if status == "completed" {
                            progress.message = Some(format!("已完成 {}/{}", current, total));
                        }
                    }
                }
            }
        }
        info!("Actor scrape stderr reader task finished");
    });
    
    // 写入请求
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(request_str.as_bytes()).await.map_err(|e| e.to_string())?;
        stdin.write_all(b"\n").await.map_err(|e| e.to_string())?;
        drop(stdin);
    }
    
    drop(plugin_manager);
    
    // 读取 stdout（最终结果）
    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut final_response: Option<serde_json::Value> = None;
    
    while let Ok(Some(line)) = stdout_reader.next_line().await {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        
        if line.starts_with('{') {
            if let Ok(response) = serde_json::from_str::<serde_json::Value>(line) {
                final_response = Some(response);
            }
        }
    }
    
    // 等待 stderr 任务完成
    let _ = stderr_task.await;
    
    // 等待进程结束
    let status = child.wait().await.map_err(|e| e.to_string())?;
    
    if !status.success() {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.status = "failed".to_string();
            progress.message = Some("插件执行失败".to_string());
            progress.completed = true;
        }
        return Err("Plugin execution failed".to_string());
    }
    
    // 处理结果并更新数据库
    if let Some(response) = final_response {
        let success = response.get("success").and_then(|v| v.as_bool()).unwrap_or(false);
        
        if success {
            let results_data = response.get("data").and_then(|v| v.as_array()).cloned().unwrap_or_default();
            let is_replace_mode = request.mode.to_lowercase() == "replace";
            
            let mut success_count = 0;
            let mut failed_count = 0;
            
            for result in results_data {
                let name = match result.get("name").and_then(|v| v.as_str()) {
                    Some(n) => n,
                    None => continue,
                };
                
                let actor_id = match actor_map.get(name) {
                    Some(id) => id,
                    None => continue,
                };
                
                let existing_actor = match actor_info_map.get(actor_id) {
                    Some(actor) => actor,
                    None => {
                        failed_count += 1;
                        continue;
                    }
                };
                
                // 辅助函数：获取字符串字段
                let get_str = |key: &str| -> Option<String> {
                    result.get(key)
                        .and_then(|v| v.as_str())
                        .filter(|s| !s.is_empty())
                        .map(String::from)
                };
                
                let get_photo_urls = || -> Option<String> {
                    result.get("photo_urls")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join(","))
                        .filter(|s| !s.is_empty())
                };
                
                if is_replace_mode {
                    // Replace 模式：刮削数据有值时覆盖，无值时保留原数据
                    let mut updated_actor = existing_actor.clone();
                    
                    // 有值则覆盖，无值则保留原数据
                    if let Some(val) = get_str("avatar_url") {
                        updated_actor.avatar_url = Some(val);
                    }
                    if let Some(val) = get_photo_urls() {
                        updated_actor.photo_url = Some(val);
                    }
                    if let Some(val) = get_str("poster_url") {
                        updated_actor.poster_url = Some(val);
                    }
                    if let Some(val) = get_str("backdrop_url") {
                        updated_actor.backdrop_url = Some(val);
                    }
                    if let Some(val) = get_str("biography") {
                        updated_actor.biography = Some(val);
                    }
                    if let Some(val) = get_str("birth_date") {
                        updated_actor.birth_date = Some(val);
                    }
                    if let Some(val) = get_str("nationality") {
                        updated_actor.nationality = Some(val);
                    }
                    updated_actor.updated_at = chrono::Utc::now();
                    
                    match crate::database::update_actor_direct(state.database.pool(), &updated_actor).await {
                        Ok(_) => {
                            success_count += 1;
                            info!("Successfully replaced actor: {} (mode: replace)", name);
                        }
                        Err(e) => {
                            error!("Failed to replace actor {}: {}", name, e);
                            failed_count += 1;
                        }
                    }
                } else {
                    // Supplement 模式：只更新空字段
                    let update_request = UpdateActorRequest {
                        name: None,
                        avatar_url: if existing_actor.avatar_url.is_none() || existing_actor.avatar_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_str("avatar_url")
                        } else { None },
                        photo_url: if existing_actor.photo_url.is_none() || existing_actor.photo_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_photo_urls()
                        } else { None },
                        poster_url: if existing_actor.poster_url.is_none() || existing_actor.poster_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_str("poster_url")
                        } else { None },
                        backdrop_url: if existing_actor.backdrop_url.is_none() || existing_actor.backdrop_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_str("backdrop_url")
                        } else { None },
                        biography: if existing_actor.biography.is_none() || existing_actor.biography.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_str("biography")
                        } else { None },
                        birth_date: if existing_actor.birth_date.is_none() || existing_actor.birth_date.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_str("birth_date")
                        } else { None },
                        nationality: if existing_actor.nationality.is_none() || existing_actor.nationality.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                            get_str("nationality")
                        } else { None },
                    };
                    
                    match update_actor(state.database.pool(), actor_id, update_request).await {
                        Ok(Some(_)) => {
                            success_count += 1;
                            info!("Successfully supplemented actor: {} (mode: supplement)", name);
                        }
                        _ => {
                            failed_count += 1;
                        }
                    }
                }
            }
            
            // 更新最终进度
            let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
            if let Some(progress) = progress_map.get_mut(&session_id) {
                progress.status = "completed".to_string();
                progress.message = Some(format!("刮削完成: {} 成功, {} 失败", success_count, failed_count));
                progress.success_count = success_count;
                progress.failed_count = failed_count;
                progress.completed = true;
            }
        } else {
            let error_msg = response.get("error").and_then(|v| v.as_str()).unwrap_or("Unknown error");
            let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
            if let Some(progress) = progress_map.get_mut(&session_id) {
                progress.status = "failed".to_string();
                progress.message = Some(format!("刮削失败: {}", error_msg));
                progress.completed = true;
            }
        }
    }
    
    Ok(())
}


