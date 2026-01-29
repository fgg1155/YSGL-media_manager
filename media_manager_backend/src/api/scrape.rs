//! 刮削 API 端点

use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;
use tracing::{info, warn, error};

use crate::api::AppState;
use crate::api::error::{ApiError, ApiResult};
use crate::api::response::{success, success_message};
use crate::plugins::protocol::MagnetResult;
use crate::models::{MediaItemResponse, MediaItem};
use crate::database::{find_or_create_actor_by_name, add_actor_to_media, DatabaseRepository};

lazy_static::lazy_static! {
    static ref MAGNET_SEARCH_PROGRESS: Arc<RwLock<HashMap<String, MagnetSearchProgress>>> = Arc::new(RwLock::new(HashMap::new()));
    pub static ref MEDIA_SCRAPE_PROGRESS: Arc<RwLock<HashMap<String, MediaScrapeProgress>>> = Arc::new(RwLock::new(HashMap::new()));
}

/// 搜索查询参数
#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    pub page: Option<u32>,
}

/// 磁力搜索进度
#[derive(Debug, Serialize, Clone)]
pub struct MagnetSearchProgress {
    pub status: String,
    pub message: Option<String>,
    pub current_site: Option<String>,  // 当前正在搜索的网站
    pub sites_status: Vec<SiteSearchStatus>,  // 各个网站的搜索状态
    pub results: Vec<MagnetResult>,
    pub completed: bool,
}

/// 单个网站的搜索状态
#[derive(Debug, Serialize, Clone)]
pub struct SiteSearchStatus {
    pub site_name: String,
    pub status: String,  // "pending", "searching", "completed", "failed"
    pub result_count: usize,
    pub error: Option<String>,
}

/// 媒体刮削进度
#[derive(Debug, Serialize, Clone)]
pub struct MediaScrapeProgress {
    pub status: String,  // "scraping", "completed", "failed"
    pub message: Option<String>,
    pub current: i32,
    pub total: i32,
    pub current_item: Option<String>,  // 当前正在刮削的项目名称（串行模式）
    pub item_status: String,  // "scraping", "completed", "failed", "skipped"
    pub success_count: i32,
    pub failed_count: i32,
    pub completed: bool,
    pub concurrent: bool,  // 是否并发模式
    pub processing_items: Vec<String>,  // 正在处理的项目列表（并发模式）
}

/// 媒体刮削响应
#[derive(Debug, Serialize)]
pub struct MediaScrapeResponse {
    pub success: bool,
    pub session_id: String,
    pub message: String,
}

/// 磁力搜索响应
#[derive(Debug, Serialize)]
pub struct MagnetSearchResponse {
    pub success: bool,
    pub session_id: String,
    pub message: String,
}

// 移除本地 ApiResponse 定义，使用统一的模块

/// 获取所有可用插件
pub async fn list_plugins(
    State(state): State<AppState>,
) -> impl IntoResponse {
    let manager = state.plugin_manager.read().await;
    let plugins = manager.get_plugin_infos();
    success(plugins)
}

/// 重新加载插件
pub async fn reload_plugins(
    State(state): State<AppState>,
) -> ApiResult<impl IntoResponse> {
    let mut manager = state.plugin_manager.write().await;
    manager.reload().await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    Ok(success_message("Plugins reloaded"))
}

/// 自动识别ID并刮削
pub async fn scrape_auto(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    let manager = state.plugin_manager.read().await;
    let result = manager.scrape_auto(&id).await
        .map_err(|e| ApiError::ExternalService(e.to_string()))?;
    Ok(success(result))
}

/// 使用指定插件刮削
pub async fn scrape_with_plugin(
    State(state): State<AppState>,
    Path((plugin_id, id)): Path<(String, String)>,
) -> ApiResult<impl IntoResponse> {
    let manager = state.plugin_manager.read().await;
    let result = manager.scrape_with_plugin(&plugin_id, &id).await
        .map_err(|e| ApiError::ExternalService(e.to_string()))?;
    Ok(success(result))
}

/// 使用指定插件搜索
pub async fn search_with_plugin(
    State(state): State<AppState>,
    Path(plugin_id): Path<String>,
    Query(query): Query<SearchQuery>,
) -> ApiResult<impl IntoResponse> {
    let manager = state.plugin_manager.read().await;
    let result = manager.search_with_plugin(&plugin_id, &query.q, query.page).await
        .map_err(|e| ApiError::ExternalService(e.to_string()))?;
    Ok(success(result))
}

/// 模式验证函数
fn validate_mode(mode: &str) -> Result<(), String> {
    match mode.to_lowercase().as_str() {
        "replace" | "supplement" => Ok(()),
        _ => Err(format!("Invalid mode: {}. Must be 'replace' or 'supplement'", mode)),
    }
}

/// 统一的单个媒体刮削端点
/// POST /api/scrape/media/:media_id
/// 
/// 行为：
/// - 如果刮削返回1个结果：直接更新数据库并返回更新后的媒体信息
/// - 如果刮削返回多个结果：返回结果列表供前端选择（不入库）
pub async fn scrape_media(
    State(state): State<AppState>,
    Path(media_id): Path<String>,
    Json(request): Json<ScrapeMediaRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    // 1. 验证 mode 参数
    validate_mode(&request.mode)
        .map_err(|e| ApiError::Validation(e))?;
    
    // 2. 获取媒体项目
    let mut media = state.db_service.get_media_detail(&media_id).await?
        .ok_or_else(|| ApiError::NotFound("Media not found".to_string()))?;
    
    // 3. 如果提供了 data 字段，直接使用这个数据入库（用户从多个结果中选择的情况）
    if let Some(data) = &request.data {
        // 3.1 检查是否是批量创建新媒体（data 是数组）
        if let Some(data_array) = data.as_array() {
            if request.create_new {
                // 批量创建新媒体
                info!("批量创建 {} 个新媒体", data_array.len());
                
                let mut created_media = Vec::new();
                
                for (index, item_data) in data_array.iter().enumerate() {
                    match create_media_from_scrape_result(item_data, &state).await {
                        Ok(media_id) => {
                            info!("✓ 创建媒体成功 ({}/{}): {}", index + 1, data_array.len(), media_id);
                            // 获取创建的媒体详情
                            if let Ok(Some(media)) = state.db_service.get_media_detail(&media_id).await {
                                created_media.push(MediaItemResponse::from(media));
                            }
                        }
                        Err(e) => {
                            error!("✗ 创建媒体失败 ({}/{}): {}", index + 1, data_array.len(), e);
                        }
                    }
                }
                
                return Ok(Json(serde_json::json!({
                    "success": true,
                    "message": format!("成功创建 {} 个媒体", created_media.len()),
                    "data": created_media
                })));
            } else {
                // 不支持批量更新现有媒体
                return Err(ApiError::Validation(
                    "批量数据只能用于创建新媒体，请设置 create_new: true".to_string()
                ));
            }
        }
        
        // 3.2 单个数据
        if request.create_new {
            // 创建新媒体
            info!("从刮削数据创建新媒体");
            
            match create_media_from_scrape_result(data, &state).await {
                Ok(media_id) => {
                    info!("✓ 创建媒体成功: {}", media_id);
                    // 获取创建的媒体详情
                    if let Ok(Some(media)) = state.db_service.get_media_detail(&media_id).await {
                        return Ok(Json(serde_json::json!({
                            "success": true,
                            "data": MediaItemResponse::from(media)
                        })));
                    }
                }
                Err(e) => {
                    error!("✗ 创建媒体失败: {}", e);
                    return Err(ApiError::Internal(format!("创建媒体失败: {}", e)));
                }
            }
        } else {
            // 更新现有媒体
            info!("使用用户选择的刮削数据更新媒体，媒体ID: {}", media_id);
            
            // 根据 mode 参数应用刮削结果
            match request.mode.to_lowercase().as_str() {
                "replace" => apply_scrape_result_to_media(&mut media, data),
                "supplement" => apply_scrape_result_to_media_supplement(&mut media, data),
                _ => unreachable!(),
            }
            
            // 保存更新后的媒体
            state.db_service.update_media(media.clone()).await?;
            
            // 同步演员到 actors 表并建立关联
            if let Some(actors) = data.get("actors").and_then(|v| v.as_array()) {
                let actor_names: Vec<String> = actors.iter()
                    .filter_map(|v| v.as_str())
                    .map(String::from)
                    .collect();
                sync_actors_to_db(&state, &actor_names, &media_id).await;
            }
            
            // 调用缓存服务处理图片缓存
            let scraper_name = data.get("source")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            
            let media_data = crate::services::cache::MediaData::from_media_item(&media);
            
            if let Err(e) = state.cache_service.handle_media_save(&media_id, &media_data, scraper_name).await {
                tracing::error!("缓存处理失败: media_id={}, scraper={}, error={:?}", media_id, scraper_name, e);
            }
            
            return Ok(Json(serde_json::json!({
                "success": true,
                "data": MediaItemResponse::from(media)
            })));
        }
    }
    
    // 4. 确定刮削关键词（优先使用请求中的code，否则使用媒体的code或title）
    let code = request.code
        .or_else(|| media.code.clone())
        .unwrap_or_else(|| media.title.clone());
    
    if code.is_empty() {
        return Err(ApiError::Validation("No code or title to scrape".to_string()));
    }
    
    info!("开始刮削媒体 {}: {}", media_id, code);
    
    // 5. 直接调用插件（不使用 plugin_manager 的高层 API）
    let (executable_path, plugin_path) = {
        let manager = state.plugin_manager.read().await;
        let plugins = manager.list_plugins();
        let media_scraper = plugins.iter()
            .find(|p| p.config.id == "media_scraper")
            .ok_or_else(|| ApiError::NotFound("media_scraper 插件未找到".to_string()))?;
        
        (media_scraper.executable_path.clone(), media_scraper.path.clone())
    };
    
    // 构建请求 JSON（不传 return_mode，让插件自动判断）
    let mut request_json = serde_json::json!({
        "action": "get",
        "id": code,
        "field_source": "code",  // 标识这是从"番号"字段来的
    });
    
    // 添加可选参数
    if let Some(content_type) = &request.content_type {
        request_json["content_type"] = serde_json::json!(content_type);
    }
    if let Some(series) = &request.series {
        request_json["series"] = serde_json::json!(series);
    }
    if let Some(studio) = &request.studio {
        request_json["studio"] = serde_json::json!(studio);
    }
    
    let request_str = serde_json::to_string(&request_json)
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    
    // 调用插件
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::process::Command;
    use std::process::Stdio;
    
    let mut child = Command::new(&executable_path)
        .current_dir(&plugin_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| ApiError::Internal(format!("启动插件失败: {}", e)))?;
    
    // 写入请求
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(request_str.as_bytes()).await
            .map_err(|e| ApiError::Internal(format!("写入请求失败: {}", e)))?;
        stdin.write_all(b"\n").await
            .map_err(|e| ApiError::Internal(format!("写入请求失败: {}", e)))?;
        drop(stdin);
    }
    
    // 读取响应
    let stdout = child.stdout.take()
        .ok_or_else(|| ApiError::Internal("无法获取 stdout".to_string()))?;
    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut response_json: Option<serde_json::Value> = None;
    
    while let Ok(Some(line)) = stdout_reader.next_line().await {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('{') {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(line) {
                response_json = Some(json);
                break;
            }
        }
    }
    
    // 等待进程结束
    let status = child.wait().await
        .map_err(|e| ApiError::Internal(format!("等待插件结束失败: {}", e)))?;
    
    if !status.success() {
        return Err(ApiError::ExternalService("插件执行失败".to_string()));
    }
    
    // 解析响应
    let response = response_json
        .ok_or_else(|| ApiError::ExternalService("未收到插件响应".to_string()))?;
    
    let is_success = response.get("success").and_then(|v| v.as_bool()).unwrap_or(false);
    
    if !is_success {
        // 处理错误信息（可能是字符串或对象）
        // 先打印完整的响应用于调试
        error!("插件返回错误，完整响应: {:?}", response);
        
        let error_msg = if let Some(error_obj) = response.get("error") {
            error!("error 字段内容: {:?}", error_obj);
            
            if let Some(error_str) = error_obj.as_str() {
                error_str.to_string()
            } else if let Some(error_dict) = error_obj.as_object() {
                if let Some(message) = error_dict.get("message") {
                    error!("message 字段内容: {:?}", message);
                    
                    // message 可能是对象（包含 zh/en）或字符串
                    if let Some(message_obj) = message.as_object() {
                        // message 是对象，尝试获取 zh 或 en
                        if let Some(zh_msg) = message_obj.get("zh").and_then(|v| v.as_str()) {
                            zh_msg.to_string()
                        } else if let Some(en_msg) = message_obj.get("en").and_then(|v| v.as_str()) {
                            en_msg.to_string()
                        } else {
                            "未知错误".to_string()
                        }
                    } else if let Some(msg_str) = message.as_str() {
                        // message 是字符串
                        msg_str.to_string()
                    } else {
                        "未知错误".to_string()
                    }
                } else {
                    "未知错误".to_string()
                }
            } else {
                "未知错误".to_string()
            }
        } else {
            "未知错误".to_string()
        };
        return Err(ApiError::ExternalService(format!("刮削失败: {}", error_msg)));
    }
    
    // 5. 检查是否是多结果格式
    if let Some(mode) = response.get("mode").and_then(|v| v.as_str()) {
        if mode == "multiple" {
            // 多个结果：返回给前端让用户选择
            let results = response.get("results")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            
            let total_count = response.get("total_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(results.len() as u64);
            
            info!("刮削返回 {} 个结果，返回给前端选择", total_count);
            
            let response = ScrapeMultipleResponse {
                success: true,
                mode: mode.to_string(),
                results: results.clone(),
                message: Some(format!("找到 {} 个结果", total_count)),
            };
            
            return Ok(Json(serde_json::json!({
                "success": true,
                "data": response
            })));
        }
    }
    
    // 6. 单个结果：直接入库
    let data = response.get("data")
        .ok_or_else(|| ApiError::ExternalService("响应中缺少 data 字段".to_string()))?;
    
    info!("刮削返回 1 个结果，直接入库");
    
    // 7. 根据 mode 参数应用刮削结果
    match request.mode.to_lowercase().as_str() {
        "replace" => apply_scrape_result_to_media(&mut media, data),
        "supplement" => apply_scrape_result_to_media_supplement(&mut media, data),
        _ => unreachable!(),
    }
    
    // 8. 保存更新后的媒体
    state.db_service.update_media(media.clone()).await?;
    
    // 9. 同步演员到 actors 表并建立关联
    if let Some(actors) = data.get("actors").and_then(|v| v.as_array()) {
        let actor_names: Vec<String> = actors.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        sync_actors_to_db(&state, &actor_names, &media_id).await;
    }
    
    // 10. 调用缓存服务处理图片缓存
    // 从刮削数据中提取刮削器名称（source 字段）
    let scraper_name = data.get("source")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");
    
    // 将 MediaItem 转换为 MediaData
    let media_data = crate::services::cache::MediaData::from_media_item(&media);
    
    // 异步调用缓存服务（不阻塞响应）
    if let Err(e) = state.cache_service.handle_media_save(&media_id, &media_data, scraper_name).await {
        // 缓存失败不影响主流程，只记录错误日志
        tracing::error!("缓存处理失败: media_id={}, scraper={}, error={:?}", media_id, scraper_name, e);
    }
    
    Ok(Json(serde_json::json!({
        "success": true,
        "data": MediaItemResponse::from(media)
    })))
}

/// 同步演员到数据库
async fn sync_actors_to_db(state: &AppState, actor_names: &[String], media_id: &str) {
    for actor_name in actor_names {
        // 查找或创建演员
        if let Ok(actor) = find_or_create_actor_by_name(state.database.pool(), actor_name).await {
            // 建立演员与媒体的关联
            let _ = add_actor_to_media(
                state.database.pool(),
                &actor.id,
                media_id,
                None,  // character_name
                Some("cast".to_string()), // role
            ).await;
        }
    }
}

/// 搜索磁力链接
/// GET /api/scrape/magnets/:plugin_id?q=query
pub async fn search_magnets(
    State(state): State<AppState>,
    Path(plugin_id): Path<String>,
    Query(query): Query<SearchQuery>,
) -> Json<MagnetSearchResponse> {
    // 生成会话ID
    let session_id = uuid::Uuid::new_v4().to_string();
    info!("开始磁力搜索，会话ID: {}, 查询: {}", session_id, query.q);
    
    // 初始化进度跟踪
    {
        let mut progress_map = MAGNET_SEARCH_PROGRESS.write().await;
        progress_map.insert(session_id.clone(), MagnetSearchProgress {
            status: "searching".to_string(),
            message: Some("正在初始化搜索...".to_string()),
            current_site: None,
            sites_status: vec![
                SiteSearchStatus {
                    site_name: "Kiteyuan".to_string(),
                    status: "pending".to_string(),
                    result_count: 0,
                    error: None,
                },
                SiteSearchStatus {
                    site_name: "Knaben".to_string(),
                    status: "pending".to_string(),
                    result_count: 0,
                    error: None,
                },
                SiteSearchStatus {
                    site_name: "SkrBT".to_string(),
                    status: "pending".to_string(),
                    result_count: 0,
                    error: None,
                },
            ],
            results: vec![],
            completed: false,
        });
    }
    
    // 克隆需要的数据用于后台任务
    let session_id_clone = session_id.clone();
    let state_clone = state.clone();
    let query_clone = query.q.clone();
    
    // 在后台任务中执行搜索
    tokio::spawn(async move {
        let result = process_magnet_search(state_clone, plugin_id, query_clone, session_id_clone).await;
        if let Err(e) = result {
            error!("后台磁力搜索任务失败: {}", e);
        }
    });
    
    // 立即返回session_id，让前端开始轮询
    Json(MagnetSearchResponse {
        success: true,
        session_id,
        message: "磁力搜索任务已启动".to_string(),
    })
}

/// 处理磁力搜索（后台任务）
async fn process_magnet_search(
    state: AppState,
    plugin_id: String,
    query: String,
    session_id: String,
) -> Result<(), String> {
    info!("开始执行磁力搜索: {}", query);
    
    // 更新状态：开始搜索
    {
        let mut progress_map = MAGNET_SEARCH_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.message = Some("正在搜索磁力资源...".to_string());
            progress.current_site = None;
        }
    }
    
    // 在锁外执行耗时的插件调用，使用带进度回调的版本
    let manager = state.plugin_manager.read().await;
    
    // 克隆 session_id 用于闭包
    let session_id_for_callback = session_id.clone();
    
    // 创建进度回调函数
    let progress_callback = move |site_progress: crate::plugins::protocol::SiteSearchProgress| {
        // 使用 tokio::spawn 在异步上下文中更新进度
        let session_id = session_id_for_callback.clone();
        info!("Progress callback invoked: {} - {}", site_progress.site_name, site_progress.status);
        tokio::spawn(async move {
            info!("Updating progress map for session: {}", session_id);
            let mut progress_map = MAGNET_SEARCH_PROGRESS.write().await;
            if let Some(progress) = progress_map.get_mut(&session_id) {
                info!("Found session, updating status for: {}", site_progress.site_name);
                // 更新当前正在搜索的网站
                if site_progress.status == "searching" {
                    progress.current_site = Some(site_progress.site_name.clone());
                }
                
                // 更新或添加网站状态
                if let Some(existing) = progress.sites_status.iter_mut()
                    .find(|s| s.site_name == site_progress.site_name) 
                {
                    existing.status = site_progress.status.clone();
                    existing.result_count = site_progress.result_count.unwrap_or(0);
                    existing.error = site_progress.error.clone();
                    info!("Updated existing site status: {} -> {}", site_progress.site_name, site_progress.status);
                } else {
                    // 如果网站不在列表中，添加它
                    progress.sites_status.push(SiteSearchStatus {
                        site_name: site_progress.site_name.clone(),
                        status: site_progress.status.clone(),
                        result_count: site_progress.result_count.unwrap_or(0),
                        error: site_progress.error.clone(),
                    });
                    info!("Added new site status: {} -> {}", site_progress.site_name, site_progress.status);
                }
            } else {
                warn!("Session not found: {}", session_id);
            }
        });
    };
    
    let search_result = manager.search_magnets_with_progress(&plugin_id, &query, progress_callback).await;
    drop(manager);
    
    match search_result {
        Ok(results) => {
            info!("磁力搜索成功，找到 {} 个结果", results.len());
            
            // 更新进度为完成
            {
                let mut progress_map = MAGNET_SEARCH_PROGRESS.write().await;
                if let Some(progress) = progress_map.get_mut(&session_id) {
                    progress.status = "completed".to_string();
                    progress.message = Some(format!("搜索完成，找到 {} 个结果", results.len()));
                    progress.current_site = None;
                    progress.results = results;
                    progress.completed = true;
                }
            }
            Ok(())
        }
        Err(e) => {
            error!("磁力搜索失败: {}", e);
            
            // 更新进度为失败
            {
                let mut progress_map = MAGNET_SEARCH_PROGRESS.write().await;
                if let Some(progress) = progress_map.get_mut(&session_id) {
                    progress.status = "failed".to_string();
                    progress.message = Some(format!("搜索失败: {}", e));
                    progress.current_site = None;
                    progress.completed = true;
                }
            }
            Err(e.to_string())
        }
    }
}

/// 查询磁力搜索进度
/// GET /api/scrape/magnets/progress/:session_id
pub async fn get_magnet_search_progress(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    info!("查询磁力搜索进度，会话ID: {}", session_id);
    let progress_map = MAGNET_SEARCH_PROGRESS.read().await;
    
    let progress = progress_map.get(&session_id)
        .ok_or_else(|| {
            warn!("会话未找到: {}", session_id);
            ApiError::NotFound(format!("Session not found: {}", session_id))
        })?;
    
    info!("找到进度：{:?}", progress.status);
    Ok(success(progress.clone()))
}

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

/// 单个媒体刮削请求
#[derive(Debug, Deserialize)]
pub struct ScrapeMediaRequest {
    /// 更新模式：replace（替换）或 supplement（补全）
    pub mode: String,
    /// 可选：指定识别号进行刮削（如果不提供，使用媒体自身的code或title）
    pub code: Option<String>,
    /// 可选：内容类型（Scene/Movie），用于选择 API
    pub content_type: Option<String>,
    /// 可选：系列名（用于 Western 判定使用哪个网络的 API）
    pub series: Option<String>,
    /// 可选：片商名（用于 JAV 判定使用哪个片商的刮削器）
    pub studio: Option<String>,
    /// 可选：直接提供刮削数据（用于用户从多个结果中选择后的导入）
    /// - 单个对象：更新或创建单个媒体
    /// - 数组：批量创建新媒体
    pub data: Option<serde_json::Value>,
    /// 可选：是否创建新媒体（默认 false，更新现有媒体）
    #[serde(default)]
    pub create_new: bool,
}

/// 批量刮削请求
#[derive(Debug, Deserialize)]
pub struct BatchScrapeMediaRequest {
    /// 媒体ID列表
    pub media_ids: Vec<String>,
    /// 更新模式：replace（替换）或 supplement（补全）
    pub mode: String,
    /// 是否并发处理，默认false（串行）
    #[serde(default, deserialize_with = "deserialize_bool_from_anything")]
    pub concurrent: bool,
    /// 刮削方式：code/title/series_date/series_title
    #[serde(default)]
    pub scrape_mode: Option<String>,
    /// 内容类型：Scene/Movie
    #[serde(default)]
    pub content_type: Option<String>,
}

/// 批量刮削响应
#[derive(Debug, Serialize)]
pub struct BatchScrapeMediaResponse {
    pub success_count: usize,
    pub failed_count: usize,
    pub results: Vec<BatchScrapeResult>,
}

#[derive(Debug, Serialize)]
pub struct BatchScrapeResult {
    pub media_id: String,
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// 统一的批量媒体刮削端点（带进度支持）
/// POST /api/scrape/media/batch
/// 返回 session_id，前端通过轮询 /api/scrape/media/progress/:session_id 获取进度
pub async fn batch_scrape_media_unified(
    State(state): State<AppState>,
    Json(request): Json<BatchScrapeMediaRequest>,
) -> Json<MediaScrapeResponse> {
    use serde_json::json;
    
    // 生成会话ID
    let session_id = uuid::Uuid::new_v4().to_string();
    info!("开始批量媒体刮削，会话ID: {}, 数量: {}, 并发: {}", session_id, request.media_ids.len(), request.concurrent);
    
    // 初始化进度跟踪
    {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        progress_map.insert(session_id.clone(), MediaScrapeProgress {
            status: "scraping".to_string(),
            message: Some("正在初始化刮削...".to_string()),
            current: 0,
            total: request.media_ids.len() as i32,
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
        let result = process_batch_media_scrape(state_clone, request_clone, session_id_clone).await;
        if let Err(e) = result {
            error!("后台批量刮削任务失败: {}", e);
        }
    });
    
    // 立即返回session_id，让前端开始轮询
    Json(MediaScrapeResponse {
        success: true,
        session_id,
        message: "批量刮削任务已启动".to_string(),
    })
}



/// 应用刮削结果到媒体（替换式更新 - 刮削数据有值时覆盖原数据）
fn apply_scrape_result_to_media(media: &mut crate::models::MediaItem, scrape_data: &serde_json::Value) {
    // 刮削器名称：有值则覆盖
    if let Some(source) = scrape_data.get("source").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.scraper_name = Some(source.to_string());
    }
    
    // 识别号：有值则覆盖
    if let Some(code) = scrape_data.get("code").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.code = Some(code.to_string());
    }
    
    // 标题：有值则覆盖
    if let Some(title) = scrape_data.get("title").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.title = title.to_string();
    }
    
    // 原始标题：有值则覆盖
    if let Some(title) = scrape_data.get("original_title").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.original_title = Some(title.to_string());
    }
    
    // 年份：有值则覆盖
    if let Some(year) = scrape_data.get("year").and_then(|v| v.as_i64()) {
        media.year = Some(year as i32);
    }
    
    // 评分：有值则覆盖
    if let Some(rating) = scrape_data.get("rating").and_then(|v| v.as_f64()) {
        media.rating = Some(rating as f32);
    }
    
    // 时长：有值则覆盖
    if let Some(runtime) = scrape_data.get("runtime").and_then(|v| v.as_i64()) {
        media.runtime = Some(runtime as i32);
    }
    
    // 简介：有值则覆盖
    if let Some(overview) = scrape_data.get("overview").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        let _ = media.set_overview(Some(overview.to_string()));
    }
    
    // 海报：有值则覆盖
    info!("检查 poster_url 字段: {:?}", scrape_data.get("poster_url"));
    if let Some(poster) = scrape_data.get("poster_url").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        info!("✓ 设置封面图: {}", poster);
        let _ = media.set_poster_url(Some(poster.to_string()));
    } else {
        warn!("✗ poster_url 字段为空或不是字符串");
    }
    
    // 背景图：有值则覆盖（支持数组格式）
    if let Some(backdrop_value) = scrape_data.get("backdrop_url") {
        info!("收到 backdrop_url 字段: {:?}", backdrop_value);
        
        if let Some(backdrop_array) = backdrop_value.as_array() {
            // 数组格式：序列化为 JSON 字符串
            info!("backdrop_url 是数组格式，长度: {}", backdrop_array.len());
            if !backdrop_array.is_empty() {
                if let Ok(json_str) = serde_json::to_string(backdrop_array) {
                    info!("序列化为 JSON 字符串: {}", json_str);
                    let _ = media.set_backdrop_url(Some(json_str));
                }
            }
        } else if let Some(backdrop_str) = backdrop_value.as_str().filter(|s| !s.is_empty()) {
            // 字符串格式：直接使用
            info!("backdrop_url 是字符串格式: {}", backdrop_str);
            let _ = media.set_backdrop_url(Some(backdrop_str.to_string()));
        } else {
            warn!("backdrop_url 格式不支持: {:?}", backdrop_value);
        }
    } else {
        info!("scrape_data 中没有 backdrop_url 字段");
    }
    
    // 制作商：有值则覆盖
    if let Some(studio) = scrape_data.get("studio").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.studio = Some(studio.to_string());
    }
    
    // 系列：有值则覆盖
    if let Some(series) = scrape_data.get("series").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.series = Some(series.to_string());
    }
    
    // 发布日期：有值则覆盖
    if let Some(release_date) = scrape_data.get("release_date").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        media.release_date = Some(release_date.to_string());
    }
    
    // 媒体类型：有值则覆盖
    if let Some(media_type_str) = scrape_data.get("media_type").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        if let Ok(mt) = media_type_str.parse::<crate::models::MediaType>() {
            let _ = media.set_media_type(mt);
        }
    }
    
    // 导演：有值则覆盖
    if let Some(director) = scrape_data.get("director").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        // 将导演添加到 crew 列表
        let mut crew = media.get_crew().unwrap_or_default();
        // 移除已有的导演
        crew.retain(|p| p.role != "director");
        // 添加新导演
        crew.push(crate::models::Person::new(director.to_string(), "director".to_string()));
        let _ = media.set_crew(&crew);
    }
    
    // 语言：有值则覆盖
    if let Some(language) = scrape_data.get("language").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        let _ = media.set_language(Some(language.to_string()));
    }
    
    // 国家：有值则覆盖
    if let Some(country) = scrape_data.get("country").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        let _ = media.set_country(Some(country.to_string()));
    }
    
    // 分类：有值则覆盖（不合并，直接替换）
    if let Some(genres) = scrape_data.get("genres").and_then(|v| v.as_array()) {
        let scraped_genres: Vec<String> = genres.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        if !scraped_genres.is_empty() {
            let _ = media.set_genres(&scraped_genres);
        }
    }
    
    // 演员：有值则覆盖（不合并，直接替换）
    if let Some(actors) = scrape_data.get("actors").and_then(|v| v.as_array()) {
        let scraped_cast: Vec<crate::models::Person> = actors.iter()
            .filter_map(|v| v.as_str())
            .map(|name| crate::models::Person::new(name.to_string(), "cast".to_string()))
            .collect();
        if !scraped_cast.is_empty() {
            let _ = media.set_cast(&scraped_cast);
        }
    }
    
    // 预览图：有值则覆盖（不合并，直接替换）
    if let Some(preview_urls) = scrape_data.get("preview_urls").and_then(|v| v.as_array()) {
        let scraped_preview_urls: Vec<String> = preview_urls.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        if !scraped_preview_urls.is_empty() {
            let _ = media.set_preview_urls(&scraped_preview_urls);
        }
    }
    
    // 预览视频：有值则覆盖（不合并，直接替换）
    // 支持两种格式：
    // 1. [{"quality": "4K", "url": "https://..."}, ...] (新格式，保留完整数据)
    // 2. ["https://...", ...] (旧格式，转换为新格式)
    if let Some(preview_video_urls) = scrape_data.get("preview_video_urls").and_then(|v| v.as_array()) {
        // 直接将 JSON 数组序列化为字符串存储（保留完整的结构化数据）
        if !preview_video_urls.is_empty() {
            let json_str = serde_json::to_string(preview_video_urls).unwrap_or_else(|_| "[]".to_string());
            media.preview_video_urls = Some(json_str);
            media.updated_at = chrono::Utc::now();
        }
    }
    
    // 封面视频：有值则覆盖
    if let Some(cover_video_url) = scrape_data.get("cover_video_url").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        let _ = media.set_cover_video_url(Some(cover_video_url.to_string()));
    }
    
    // 下载链接：有值则覆盖（不合并，直接替换）
    if let Some(download_links) = scrape_data.get("download_links").and_then(|v| v.as_array()) {
        let scraped_download_links: Vec<crate::models::DownloadLink> = download_links.iter()
            .filter_map(|v| {
                let name = v.get("name").and_then(|n| n.as_str()).unwrap_or("").to_string();
                let url = v.get("url").and_then(|u| u.as_str()).unwrap_or("").to_string();
                let link_type_str = v.get("link_type").and_then(|t| t.as_str()).unwrap_or("other");
                let size = v.get("size").and_then(|s| s.as_str()).map(String::from);
                let password = v.get("password").and_then(|p| p.as_str()).map(String::from);
                
                if url.is_empty() {
                    return None;
                }
                
                let link_type = match link_type_str {
                    "magnet" => crate::models::DownloadLinkType::Magnet,
                    "ed2k" => crate::models::DownloadLinkType::Ed2k,
                    "http" => crate::models::DownloadLinkType::Http,
                    "ftp" => crate::models::DownloadLinkType::Ftp,
                    "torrent" => crate::models::DownloadLinkType::Torrent,
                    "pan" => crate::models::DownloadLinkType::Pan,
                    _ => crate::models::DownloadLinkType::Other,
                };
                
                Some(crate::models::DownloadLink {
                    name,
                    url,
                    link_type,
                    size,
                    password,
                })
            })
            .collect();
        if !scraped_download_links.is_empty() {
            let _ = media.set_download_links(&scraped_download_links);
        }
    }
    
    // 更新时间戳
    media.updated_at = chrono::Utc::now();
}



/// 应用刮削结果到媒体（补充式更新 - 只填充空字段）
fn apply_scrape_result_to_media_supplement(media: &mut crate::models::MediaItem, scrape_data: &serde_json::Value) {
    // 刮削器名称：如果为空则填充
    if media.scraper_name.is_none() || media.scraper_name.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(source) = scrape_data.get("source").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
            media.scraper_name = Some(source.to_string());
        }
    }
    
    // 识别号：如果为空则填充
    if media.code.is_none() || media.code.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(code) = scrape_data.get("code").and_then(|v| v.as_str()) {
            media.code = Some(code.to_string());
        }
    }
    
    // 标题：如果为空则填充
    if media.title.is_empty() {
        if let Some(title) = scrape_data.get("title").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
            media.title = title.to_string();
        }
    }
    
    // 原始标题：如果为空则填充
    if media.original_title.is_none() || media.original_title.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(title) = scrape_data.get("original_title").and_then(|v| v.as_str()) {
            media.original_title = Some(title.to_string());
        }
    }
    
    // 年份：如果为空则填充
    if media.year.is_none() {
        if let Some(year) = scrape_data.get("year").and_then(|v| v.as_i64()) {
            media.year = Some(year as i32);
        }
    }
    
    // 评分：如果为空则填充
    if media.rating.is_none() {
        if let Some(rating) = scrape_data.get("rating").and_then(|v| v.as_f64()) {
            media.rating = Some(rating as f32);
        }
    }
    
    // 时长：如果为空则填充
    if media.runtime.is_none() {
        if let Some(runtime) = scrape_data.get("runtime").and_then(|v| v.as_i64()) {
            media.runtime = Some(runtime as i32);
        }
    }
    
    // 简介：如果为空则填充
    if media.overview.is_none() || media.overview.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(overview) = scrape_data.get("overview").and_then(|v| v.as_str()) {
            let _ = media.set_overview(Some(overview.to_string()));
        }
    }
    
    // 海报：如果为空则填充
    if media.poster_url.is_none() || media.poster_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(poster) = scrape_data.get("poster_url").and_then(|v| v.as_str()) {
            let _ = media.set_poster_url(Some(poster.to_string()));
        }
    }
    
    // 背景图：如果为空则填充（支持数组格式）
    if media.backdrop_url.is_none() || media.backdrop_url.as_ref().map(|s| s.is_empty() || s == "[]").unwrap_or(true) {
        if let Some(backdrop_value) = scrape_data.get("backdrop_url") {
            if let Some(backdrop_array) = backdrop_value.as_array() {
                // 数组格式：序列化为 JSON 字符串
                if !backdrop_array.is_empty() {
                    if let Ok(json_str) = serde_json::to_string(backdrop_array) {
                        let _ = media.set_backdrop_url(Some(json_str));
                    }
                }
            } else if let Some(backdrop_str) = backdrop_value.as_str().filter(|s| !s.is_empty()) {
                // 字符串格式：直接使用
                let _ = media.set_backdrop_url(Some(backdrop_str.to_string()));
            }
        }
    }
    
    // 制作商：如果为空则填充
    if media.studio.is_none() || media.studio.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(studio) = scrape_data.get("studio").and_then(|v| v.as_str()) {
            media.studio = Some(studio.to_string());
        }
    }
    
    // 系列：如果为空则填充
    if media.series.is_none() || media.series.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(series) = scrape_data.get("series").and_then(|v| v.as_str()) {
            media.series = Some(series.to_string());
        }
    }
    
    // 发布日期：如果为空则填充
    if media.release_date.is_none() || media.release_date.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(release_date) = scrape_data.get("release_date").and_then(|v| v.as_str()) {
            media.release_date = Some(release_date.to_string());
        }
    }
    
    // 媒体类型：如果为空则填充
    if media.media_type.is_empty() || media.media_type == "Movie" {
        if let Some(media_type_str) = scrape_data.get("media_type").and_then(|v| v.as_str()) {
            if let Ok(mt) = media_type_str.parse::<crate::models::MediaType>() {
                let _ = media.set_media_type(mt);
            }
        }
    }
    
    // 导演：如果为空则填充
    if let Some(director) = scrape_data.get("director").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        let crew = media.get_crew().unwrap_or_default();
        // 检查是否已有导演
        if !crew.iter().any(|p| p.role == "director") {
            let mut new_crew = crew.clone();
            new_crew.push(crate::models::Person::new(director.to_string(), "director".to_string()));
            let _ = media.set_crew(&new_crew);
        }
    }
    
    // 语言：如果为空则填充
    if media.language.is_none() || media.language.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(language) = scrape_data.get("language").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
            let _ = media.set_language(Some(language.to_string()));
        }
    }
    
    // 国家：如果为空则填充
    if media.country.is_none() || media.country.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(country) = scrape_data.get("country").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
            let _ = media.set_country(Some(country.to_string()));
        }
    }
    
    // 合并分类
    if let Some(genres) = scrape_data.get("genres").and_then(|v| v.as_array()) {
        let existing_genres = media.get_genres().unwrap_or_default();
        let scraped_genres: Vec<String> = genres.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        let mut merged_genres = existing_genres.clone();
        for genre in scraped_genres {
            if !merged_genres.contains(&genre) {
                merged_genres.push(genre);
            }
        }
        if !merged_genres.is_empty() {
            let _ = media.set_genres(&merged_genres);
        }
    }
    
    // 合并演员
    if let Some(actors) = scrape_data.get("actors").and_then(|v| v.as_array()) {
        let existing_cast = media.get_cast().unwrap_or_default();
        let scraped_cast: Vec<crate::models::Person> = actors.iter()
            .filter_map(|v| v.as_str())
            .map(|name| crate::models::Person::new(name.to_string(), "cast".to_string()))
            .collect();
        let mut merged_cast = existing_cast.clone();
        for person in scraped_cast {
            if !merged_cast.iter().any(|p| p.name == person.name) {
                merged_cast.push(person);
            }
        }
        if !merged_cast.is_empty() {
            let _ = media.set_cast(&merged_cast);
        }
    }
    
    // 合并预览图
    if let Some(preview_urls) = scrape_data.get("preview_urls").and_then(|v| v.as_array()) {
        let existing_preview_urls = media.get_preview_urls().unwrap_or_default();
        let scraped_preview_urls: Vec<String> = preview_urls.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        let mut merged_preview_urls = existing_preview_urls.clone();
        for url in scraped_preview_urls {
            if !merged_preview_urls.contains(&url) {
                merged_preview_urls.push(url);
            }
        }
        if !merged_preview_urls.is_empty() {
            let _ = media.set_preview_urls(&merged_preview_urls);
        }
    }
    
    // 合并预览视频（保留结构化数据）
    if let Some(preview_video_urls) = scrape_data.get("preview_video_urls").and_then(|v| v.as_array()) {
        // 获取现有的预览视频（JSON 数组）
        let existing_json: Vec<serde_json::Value> = media.preview_video_urls.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or_default();
        
        // 合并：去重（基于 URL）
        let mut merged = existing_json.clone();
        for new_item in preview_video_urls {
            // 提取 URL 用于去重
            let new_url = if let Some(obj) = new_item.as_object() {
                obj.get("url").and_then(|v| v.as_str())
            } else if let Some(s) = new_item.as_str() {
                Some(s)
            } else {
                None
            };
            
            if let Some(url) = new_url {
                // 检查是否已存在
                let exists = merged.iter().any(|existing| {
                    let existing_url = if let Some(obj) = existing.as_object() {
                        obj.get("url").and_then(|v| v.as_str())
                    } else if let Some(s) = existing.as_str() {
                        Some(s)
                    } else {
                        None
                    };
                    existing_url == Some(url)
                });
                
                if !exists {
                    merged.push(new_item.clone());
                }
            }
        }
        
        if !merged.is_empty() {
            let json_str = serde_json::to_string(&merged).unwrap_or_else(|_| "[]".to_string());
            media.preview_video_urls = Some(json_str);
            media.updated_at = chrono::Utc::now();
        }
    }
    
    // 封面视频：如果为空则填充
    if media.cover_video_url.is_none() || media.cover_video_url.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        if let Some(cover_video_url) = scrape_data.get("cover_video_url").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
            let _ = media.set_cover_video_url(Some(cover_video_url.to_string()));
        }
    }
    
    // 合并下载链接
    if let Some(download_links) = scrape_data.get("download_links").and_then(|v| v.as_array()) {
        let existing_download_links = media.get_download_links().unwrap_or_default();
        let scraped_download_links: Vec<crate::models::DownloadLink> = download_links.iter()
            .filter_map(|v| {
                let name = v.get("name").and_then(|n| n.as_str()).unwrap_or("").to_string();
                let url = v.get("url").and_then(|u| u.as_str()).unwrap_or("").to_string();
                let link_type_str = v.get("link_type").and_then(|t| t.as_str()).unwrap_or("other");
                let size = v.get("size").and_then(|s| s.as_str()).map(String::from);
                let password = v.get("password").and_then(|p| p.as_str()).map(String::from);
                
                if url.is_empty() {
                    return None;
                }
                
                let link_type = match link_type_str {
                    "magnet" => crate::models::DownloadLinkType::Magnet,
                    "ed2k" => crate::models::DownloadLinkType::Ed2k,
                    "http" => crate::models::DownloadLinkType::Http,
                    "ftp" => crate::models::DownloadLinkType::Ftp,
                    "torrent" => crate::models::DownloadLinkType::Torrent,
                    "pan" => crate::models::DownloadLinkType::Pan,
                    _ => crate::models::DownloadLinkType::Other,
                };
                
                Some(crate::models::DownloadLink {
                    name,
                    url,
                    link_type,
                    size,
                    password,
                })
            })
            .collect();
        
        let mut merged_download_links = existing_download_links.clone();
        for link in scraped_download_links {
            if !merged_download_links.iter().any(|l| l.url == link.url) {
                merged_download_links.push(link);
            }
        }
        if !merged_download_links.is_empty() {
            let _ = media.set_download_links(&merged_download_links);
        }
    }
    
    // 更新时间戳
    media.updated_at = chrono::Utc::now();
}



/// 处理批量媒体刮削（后台任务）
async fn process_batch_media_scrape(
    state: AppState,
    request: BatchScrapeMediaRequest,
    session_id: String,
) -> Result<(), String> {
    use serde_json::json;
    use tokio::io::{AsyncBufReadExt, BufReader};
    use std::process::Stdio;
    use tokio::process::Command;
    use tokio::io::AsyncWriteExt;
    
    info!("开始执行批量媒体刮削: {} 个项目", request.media_ids.len());
    
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
    
    // 收集媒体信息
    let mut media_info_list = Vec::new();
    
    for media_id in &request.media_ids {
        match state.db_service.get_media_detail(media_id).await {
            Ok(Some(media)) => {
                let code = media.code.clone().unwrap_or_default();
                let title = media.title.clone();
                let series = media.series.clone();  // 添加 series 字段
                let release_date = media.release_date.clone();  // 添加 release_date 字段
                
                media_info_list.push(json!({
                    "id": media_id,
                    "code": code,
                    "title": title,
                    "series": series,
                    "release_date": release_date
                }));
            }
            Ok(None) => {
                warn!("Media not found: {}", media_id);
            }
            Err(e) => {
                error!("Failed to get media {}: {}", media_id, e);
            }
        }
    }
    
    if media_info_list.is_empty() {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.status = "completed".to_string();
            progress.message = Some("没有找到有效的媒体项目".to_string());
            progress.completed = true;
        }
        return Ok(());
    }
    
    // 更新总数
    {
        let mut progress_map = MEDIA_SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.total = media_info_list.len() as i32;
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
    let mut request_json = json!({
        "action": "batch_scrape_media",
        "media_list": media_info_list,
        "concurrent": request.concurrent
    });
    
    // 添加可选参数
    if let Some(scrape_mode) = &request.scrape_mode {
        request_json["scrape_mode"] = json!(scrape_mode);
    }
    if let Some(content_type) = &request.content_type {
        request_json["content_type"] = json!(content_type);
    }
    
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
        info!("Started media scrape stderr reader task");
        
        while let Ok(Some(line)) = stderr_reader.next_line().await {
            let line = line.trim();
            
            // 检查是否是进度消息
            if let Some(json_str) = line.strip_prefix("PROGRESS:") {
                if let Ok(progress_data) = serde_json::from_str::<serde_json::Value>(json_str) {
                    let current = progress_data.get("current").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
                    let total = progress_data.get("total").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
                    let item_name = progress_data.get("item_name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    let status = progress_data.get("status").and_then(|v| v.as_str()).unwrap_or("scraping").to_string();
                    let error = progress_data.get("error").and_then(|v| v.as_str()).map(String::from);
                    // 解析正在处理的项目列表（并发模式）
                    let processing_items: Vec<String> = progress_data.get("processing_items")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
                        .unwrap_or_default();
                    
                    info!("Media scrape progress: {}/{} - {} ({})", current, total, item_name, status);
                    
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
                        if let Some(err) = error {
                            progress.message = Some(format!("刮削失败: {}", err));
                        } else if status == "scraping" {
                            if progress.concurrent {
                                let active_count = progress.processing_items.len();
                                progress.message = Some(format!("正在并发刮削 {} 个项目 ({}/{})", active_count, current, total));
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
        info!("Media scrape stderr reader task finished");
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
            let scrape_results = response.get("data").and_then(|v| v.as_array()).cloned().unwrap_or_default();
            let is_replace_mode = request.mode.to_lowercase() == "replace";
            
            let mut success_count = 0;
            let mut failed_count = 0;
            
            for scrape_result in scrape_results {
                let media_id = match scrape_result.get("media_id").and_then(|v| v.as_str()) {
                    Some(id) => id,
                    None => continue,
                };
                
                let item_success = scrape_result.get("success").and_then(|v| v.as_bool()).unwrap_or(false);
                
                if !item_success {
                    failed_count += 1;
                    continue;
                }
                
                let scrape_data = match scrape_result.get("data") {
                    Some(data) => data,
                    None => {
                        failed_count += 1;
                        continue;
                    }
                };
                
                // 获取媒体并更新
                match state.db_service.get_media_detail(media_id).await {
                    Ok(Some(mut media)) => {
                        if is_replace_mode {
                            apply_scrape_result_to_media(&mut media, scrape_data);
                        } else {
                            apply_scrape_result_to_media_supplement(&mut media, scrape_data);
                        }
                        
                        match state.db_service.update_media(media).await {
                            Ok(_) => {
                                // 同步演员
                                if let Some(actors) = scrape_data.get("actors").and_then(|v| v.as_array()) {
                                    let actor_names: Vec<String> = actors.iter()
                                        .filter_map(|v| v.as_str())
                                        .map(String::from)
                                        .collect();
                                    sync_actors_to_db(&state, &actor_names, media_id).await;
                                }
                                success_count += 1;
                            }
                            Err(_) => {
                                failed_count += 1;
                            }
                        }
                    }
                    _ => {
                        failed_count += 1;
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

/// 查询刮削进度（媒体和演员刮削共用）
/// GET /api/scrape/progress/:session_id
pub async fn get_scrape_progress(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
) -> ApiResult<impl IntoResponse> {
    info!("查询刮削进度，会话ID: {}", session_id);
    let progress_map = MEDIA_SCRAPE_PROGRESS.read().await;
    
    let progress = progress_map.get(&session_id)
        .ok_or_else(|| {
            warn!("会话未找到: {}", session_id);
            ApiError::NotFound(format!("Session not found: {}", session_id))
        })?;
    
    info!("找到进度：{:?}", progress.status);
    Ok(success(progress.clone()))
}

/// 多结果刮削请求
#[derive(Debug, Deserialize)]
pub struct ScrapeMultipleRequest {
    /// 搜索关键词
    pub search_query: String,
    /// 可选：内容类型（Scene/Movie）
    pub content_type: Option<String>,
    /// 可选：系列名
    pub series: Option<String>,
}

/// 多结果刮削响应
#[derive(Debug, Serialize)]
pub struct ScrapeMultipleResponse {
    pub success: bool,
    pub mode: String,  // "single" 或 "multiple"
    pub results: Vec<serde_json::Value>,
    pub message: Option<String>,
}

/// 批量导入请求
#[derive(Debug, Deserialize)]
pub struct BatchImportRequest {
    /// 选中的刮削结果列表
    pub selected_results: Vec<serde_json::Value>,
    /// 媒体ID（用于关联）
    pub media_id: Option<String>,
    /// 更新模式：replace（替换）或 supplement（补全），默认为 replace
    pub mode: Option<String>,
}

/// 批量导入响应
#[derive(Debug, Serialize)]
pub struct BatchImportResponse {
    pub success: bool,
    pub imported_count: usize,
    pub failed_count: usize,
    pub results: Vec<ImportResult>,
    pub message: String,
}

/// 单个导入结果
#[derive(Debug, Serialize)]
pub struct ImportResult {
    pub title: String,
    pub success: bool,  // 导入是否成功
    pub media_id: Option<String>,
    pub error: Option<String>,
}

/// 多结果刮削端点
/// POST /api/scrape/media/:media_id/multiple
pub async fn scrape_media_multiple(
    State(state): State<AppState>,
    Path(media_id): Path<String>,
    Json(request): Json<ScrapeMultipleRequest>,
) -> ApiResult<impl IntoResponse> {
    info!("开始多结果刮削，媒体ID: {}, 查询: {}", media_id, request.search_query);
    
    // 获取插件信息并克隆必要的数据
    let (executable_path, plugin_path) = {
        let manager = state.plugin_manager.read().await;
        let plugins = manager.list_plugins();
        let media_scraper = plugins.iter()
            .find(|p| p.config.id == "media_scraper")
            .ok_or_else(|| ApiError::NotFound("media_scraper 插件未找到".to_string()))?;
        
        (media_scraper.executable_path.clone(), media_scraper.path.clone())
    };
    
    // 构建请求 JSON，指定 return_mode='multiple'
    let mut request_json = serde_json::json!({
        "action": "get",
        "id": request.search_query,
    });
    
    // 添加可选参数
    if let Some(content_type) = &request.content_type {
        request_json["content_type"] = serde_json::json!(content_type);
    }
    if let Some(series) = &request.series {
        request_json["series"] = serde_json::json!(series);
    }
    // 添加 return_mode 参数
    request_json["return_mode"] = serde_json::json!("multiple");
    
    let request_str = serde_json::to_string(&request_json)
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    
    // 调用插件
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::process::Command;
    use std::process::Stdio;
    
    let mut child = Command::new(&executable_path)
        .current_dir(&plugin_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| ApiError::Internal(format!("启动插件失败: {}", e)))?;
    
    // 写入请求
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(request_str.as_bytes()).await
            .map_err(|e| ApiError::Internal(format!("写入请求失败: {}", e)))?;
        stdin.write_all(b"\n").await
            .map_err(|e| ApiError::Internal(format!("写入请求失败: {}", e)))?;
        drop(stdin);
    }
    
    // 读取响应
    let stdout = child.stdout.take()
        .ok_or_else(|| ApiError::Internal("无法获取 stdout".to_string()))?;
    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut response_json: Option<serde_json::Value> = None;
    
    while let Ok(Some(line)) = stdout_reader.next_line().await {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('{') {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(line) {
                response_json = Some(json);
                break;
            }
        }
    }
    
    // 等待进程结束
    let status = child.wait().await
        .map_err(|e| ApiError::Internal(format!("等待插件结束失败: {}", e)))?;
    
    if !status.success() {
        return Err(ApiError::ExternalService("插件执行失败".to_string()));
    }
    
    // 解析响应
    let response = response_json
        .ok_or_else(|| ApiError::ExternalService("未收到插件响应".to_string()))?;
    
    let success = response.get("success").and_then(|v| v.as_bool()).unwrap_or(false);
    
    if !success {
        // 处理错误信息（可能是字符串或对象）
        let error_msg = if let Some(error_obj) = response.get("error") {
            if let Some(error_str) = error_obj.as_str() {
                // 简单字符串错误
                error_str.to_string()
            } else if let Some(error_dict) = error_obj.as_object() {
                // 结构化错误对象
                if let Some(message) = error_dict.get("message") {
                    if let Some(zh_msg) = message.get("zh").and_then(|v| v.as_str()) {
                        zh_msg.to_string()
                    } else if let Some(msg_str) = message.as_str() {
                        msg_str.to_string()
                    } else {
                        "未知错误".to_string()
                    }
                } else {
                    "未知错误".to_string()
                }
            } else {
                "未知错误".to_string()
            }
        } else {
            "未知错误".to_string()
        };
        return Err(ApiError::ExternalService(format!("刮削失败: {}", error_msg)));
    }
    
    // 检查是否是多结果格式（mode 字段在顶层）
    if let Some(mode) = response.get("mode").and_then(|v| v.as_str()) {
        if mode == "multiple" {
            // 多结果格式
            let results = response.get("results")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            
            let total_count = response.get("total_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(results.len() as u64);
            
            return Ok(crate::api::response::success(ScrapeMultipleResponse {
                success: true,
                mode: mode.to_string(),
                results: results.clone(),
                message: Some(format!("找到 {} 个结果", total_count)),
            }));
        }
    }
    
    // 单结果格式（兼容旧格式）
    let data = response.get("data")
        .ok_or_else(|| ApiError::ExternalService("响应中缺少 data 字段".to_string()))?;
    
    Ok(crate::api::response::success(ScrapeMultipleResponse {
        success: true,
        mode: "single".to_string(),
        results: vec![data.clone()],
        message: Some("找到 1 个结果".to_string()),
    }))
}

/// 批量导入端点
/// POST /api/scrape/media/batch-import
pub async fn batch_import_media(
    State(state): State<AppState>,
    Json(request): Json<BatchImportRequest>,
) -> ApiResult<impl IntoResponse> {
    info!("开始批量导入，数量: {}", request.selected_results.len());
    
    let mut imported_count = 0;
    let mut failed_count = 0;
    let mut results = Vec::new();
    
    // 如果提供了 media_id，说明是从多结果中选择单个结果更新现有媒体
    if let Some(media_id) = &request.media_id {
        // 单个媒体更新模式
        if request.selected_results.len() != 1 {
            return Err(ApiError::Validation(
                "当提供 media_id 时，只能选择一个结果".to_string()
            ));
        }
        
        let scrape_result = &request.selected_results[0];
        let title = scrape_result.get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("未知标题")
            .to_string();
        
        // 获取更新模式，默认为 replace
        let mode = request.mode.as_deref().unwrap_or("replace");
        
        match update_media_from_scrape_result(media_id, scrape_result, mode, &state).await {
            Ok(_) => {
                imported_count += 1;
                results.push(ImportResult {
                    title: title.clone(),
                    success: true,
                    media_id: Some(media_id.clone()),
                    error: None,
                });
                info!("成功更新媒体: {} (ID: {})", title, media_id);
            }
            Err(e) => {
                failed_count += 1;
                results.push(ImportResult {
                    title: title.clone(),
                    success: false,
                    media_id: None,
                    error: Some(e.to_string()),
                });
                error!("更新媒体失败: {} - {}", title, e);
            }
        }
    } else {
        // 批量创建新媒体模式
        for scrape_result in &request.selected_results {
            let title = scrape_result.get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("未知标题")
                .to_string();
            
            match create_media_from_scrape_result(scrape_result, &state).await {
                Ok(media_id) => {
                    imported_count += 1;
                    results.push(ImportResult {
                        title: title.clone(),
                        success: true,
                        media_id: Some(media_id.clone()),
                        error: None,
                    });
                    info!("成功导入: {} (ID: {})", title, media_id);
                }
                Err(e) => {
                    failed_count += 1;
                    results.push(ImportResult {
                        title: title.clone(),
                        success: false,
                        media_id: None,
                        error: Some(e.to_string()),
                    });
                    error!("导入失败: {} - {}", title, e);
                }
            }
        }
    }
    
    let message = if failed_count == 0 {
        format!("成功导入 {} 个媒体", imported_count)
    } else {
        format!("成功导入 {} 个，失败 {} 个", imported_count, failed_count)
    };
    
    Ok(success(BatchImportResponse {
        success: failed_count == 0,
        imported_count,
        failed_count,
        results,
        message,
    }))
}

/// 从刮削结果创建媒体记录
async fn create_media_from_scrape_result(
    scrape_result: &serde_json::Value,
    state: &AppState,
) -> Result<String, ApiError> {
    use crate::models::MediaType;
    
    // 提取标题和媒体类型
    let title = scrape_result.get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("未知标题")
        .to_string();
    
    let media_type_str = scrape_result.get("media_type")
        .and_then(|v| v.as_str())
        .unwrap_or("Movie");
    
    let media_type = media_type_str.parse::<MediaType>()
        .unwrap_or(MediaType::Movie);
    
    // 直接创建媒体记录（不检查重复，因为用户可能想创建多个相同标题的媒体）
    let media = MediaItem::new(title, media_type)
        .map_err(|e| ApiError::Validation(format!("Validation error: {:?}", e)))?;
    
    // 插入到数据库
    state.database.repository().insert_media(&media).await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    
    let media_id = media.id.clone();
    
    // 获取刚创建的媒体
    let mut media = state.db_service.get_media_detail(&media_id).await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::Internal("Failed to retrieve created media".to_string()))?;
    
    // 应用刮削结果到媒体（使用替换模式）
    apply_scrape_result_to_media(&mut media, scrape_result);
    
    // 更新媒体记录
    state.db_service.update_media(media).await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    
    // 同步演员到数据库
    if let Some(actors) = scrape_result.get("actors").and_then(|v| v.as_array()) {
        let actor_names: Vec<String> = actors.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        sync_actors_to_db(state, &actor_names, &media_id).await;
    }
    
    Ok(media_id)
}

/// 从刮削结果更新现有媒体记录
async fn update_media_from_scrape_result(
    media_id: &str,
    scrape_result: &serde_json::Value,
    mode: &str,
    state: &AppState,
) -> Result<(), ApiError> {
    // 获取现有媒体
    let mut media = state.db_service.get_media_detail(media_id).await
        .map_err(|e| ApiError::Internal(e.to_string()))?
        .ok_or_else(|| ApiError::NotFound(format!("媒体不存在: {}", media_id)))?;
    
    // 根据模式应用刮削结果
    match mode.to_lowercase().as_str() {
        "replace" => apply_scrape_result_to_media(&mut media, scrape_result),
        "supplement" => apply_scrape_result_to_media_supplement(&mut media, scrape_result),
        _ => apply_scrape_result_to_media(&mut media, scrape_result), // 默认使用替换模式
    }
    
    // 更新媒体记录
    state.db_service.update_media(media).await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    
    // 同步演员到数据库
    if let Some(actors) = scrape_result.get("actors").and_then(|v| v.as_array()) {
        let actor_names: Vec<String> = actors.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        sync_actors_to_db(state, &actor_names, media_id).await;
    }
    
    Ok(())
}
