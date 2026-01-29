use axum::{
    extract::{State, Path},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use tracing::{info, warn, error};
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

lazy_static::lazy_static! {
    static ref SCRAPE_PROGRESS: Arc<RwLock<HashMap<String, AutoScrapeProgress>>> = Arc::new(RwLock::new(HashMap::new()));
}

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

use crate::api::AppState;
use crate::services::{FileScanner, FileMatcher, FileGrouper, MatchResult, GroupMatchResult, ScannedFile, FileGroup};
use crate::database::repository::{DatabaseRepository, IgnoredFile};
use crate::models::MediaFile;

#[derive(Debug, Deserialize)]
pub struct ScanRequest {
    pub paths: Vec<String>,
    pub recursive: bool,
}

#[derive(Debug, Serialize)]
pub struct ScanResponse {
    pub success: bool,
    pub total_files: usize,
    pub scanned_files: Vec<ScannedFile>,
    pub file_groups: Vec<FileGroup>,
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct MatchRequest {
    pub scanned_files: Vec<ScannedFile>,
    pub file_groups: Vec<FileGroup>,
}

#[derive(Debug, Serialize)]
pub struct MatchResponse {
    pub success: bool,
    pub match_results: Vec<MatchResult>,
    pub group_match_results: Vec<GroupMatchResult>,
    pub exact_matches: usize,
    pub fuzzy_matches: usize,
    pub no_matches: usize,
}

#[derive(Debug, Deserialize)]
pub struct ConfirmMatchRequest {
    pub matches: Vec<ConfirmMatch>,
}

#[derive(Debug, Deserialize)]
pub struct ConfirmMatch {
    pub media_id: String,
    pub files: Vec<FileInfo>,
}

#[derive(Debug, Deserialize)]
pub struct FileInfo {
    pub file_path: String,
    pub file_size: i64,
    pub part_number: Option<i32>,
    pub part_label: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ConfirmMatchResponse {
    pub success: bool,
    pub updated_count: usize,
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct AutoScrapeRequest {
    pub unmatched_files: Vec<ScannedFile>,
    pub unmatched_groups: Option<Vec<FileGroup>>,
    #[serde(default, deserialize_with = "deserialize_bool_from_anything")]
    pub concurrent: bool,
    pub content_type: Option<String>,  // 内容类型：Scene 或 Movie
    pub process_mode: Option<String>,  // 处理模式：create_new 或 update_existing
}

#[derive(Debug, Serialize)]
pub struct AutoScrapeResponse {
    pub success: bool,
    pub session_id: String,
    pub scraped_count: usize,
    pub failed_count: usize,
    pub results: Vec<ScrapeFileResult>,
    pub message: String,
}

#[derive(Debug, Serialize, Clone)]
pub struct AutoScrapeProgress {
    pub current: usize,
    pub total: usize,
    pub file_name: String,
    pub status: String,
    pub message: Option<String>,
    pub scraped_count: usize,
    pub failed_count: usize,
}

#[derive(Debug, Serialize)]
pub struct ScrapeFileResult {
    pub file_path: String,
    pub file_name: String,
    pub success: bool,
    pub media_id: Option<String>,
    pub error: Option<String>,
}

pub async fn start_scan(
    State(_state): State<AppState>,
    Json(request): Json<ScanRequest>,
) -> Result<Json<ScanResponse>, (StatusCode, String)> {
    let scanner = FileScanner::new();
    let grouper = FileGrouper::new();
    
    let mut all_scanned_files = Vec::new();
    let mut total_files = 0;
    
    for path in &request.paths {
        match scanner.scan_directory(path, request.recursive) {
            Ok(result) => {
                total_files += result.total_files;
                all_scanned_files.extend(result.scanned_files);
            }
            Err(e) => {
                return Err((StatusCode::BAD_REQUEST, format!("Scan path {} failed: {}", path, e)));
            }
        }
    }
    
    let all_file_groups = grouper.group_files(all_scanned_files.clone());
    let file_groups: Vec<FileGroup> = all_file_groups
        .into_iter()
        .filter(|group| group.files.len() > 1)
        .collect();
    
    let file_groups_len = file_groups.len();
    
    Ok(Json(ScanResponse {
        success: true,
        total_files,
        scanned_files: all_scanned_files,
        file_groups,
        message: format!("Successfully scanned {} directories, found {} video files, grouped into {} groups", 
            request.paths.len(), total_files, file_groups_len),
    }))
}

pub async fn match_files(
    State(state): State<AppState>,
    Json(request): Json<MatchRequest>,
) -> Result<Json<MatchResponse>, (StatusCode, String)> {
    let all_media = state.database.repository()
        .get_all_media()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to get media list: {}", e)))?;
    
    let match_results = FileMatcher::match_files(request.scanned_files, all_media.clone());
    let group_match_results = FileMatcher::match_file_groups(request.file_groups, all_media);
    
    let exact_matches = match_results.iter()
        .filter(|r| r.match_type == crate::services::MatchType::Exact)
        .count()
        + group_match_results.iter()
        .filter(|r| r.match_type == crate::services::MatchType::Exact)
        .count();
        
    let fuzzy_matches = match_results.iter()
        .filter(|r| r.match_type == crate::services::MatchType::Fuzzy)
        .count()
        + group_match_results.iter()
        .filter(|r| r.match_type == crate::services::MatchType::Fuzzy)
        .count();
        
    let no_matches = match_results.iter()
        .filter(|r| r.match_type == crate::services::MatchType::None)
        .count()
        + group_match_results.iter()
        .filter(|r| r.match_type == crate::services::MatchType::None)
        .count();
    
    Ok(Json(MatchResponse {
        success: true,
        match_results,
        group_match_results,
        exact_matches,
        fuzzy_matches,
        no_matches,
    }))
}

pub async fn confirm_matches(
    State(state): State<AppState>,
    Json(request): Json<ConfirmMatchRequest>,
) -> Result<Json<ConfirmMatchResponse>, (StatusCode, String)> {
    let mut updated_count = 0;
    
    for confirm_match in request.matches {
        let media_files: Vec<MediaFile> = confirm_match.files.iter().map(|file_info| {
            MediaFile::new(
                confirm_match.media_id.clone(),
                file_info.file_path.clone(),
                file_info.file_size,
                file_info.part_number,
                file_info.part_label.clone(),
            )
        }).collect();
        
        let save_result = state.database.repository()
            .save_media_files(&media_files)
            .await;
        
        if save_result.is_err() {
            continue;
        }
        
        if let Some(first_file) = confirm_match.files.first() {
            let total_size: i64 = confirm_match.files.iter().map(|f| f.file_size).sum();
            
            let update_result = state.database.repository()
                .update_media_file_info(
                    &confirm_match.media_id,
                    &first_file.file_path,
                    total_size
                )
                .await;
            
            if update_result.is_ok() {
                updated_count += 1;
            }
        }
    }
    
    Ok(Json(ConfirmMatchResponse {
        success: true,
        updated_count,
        message: format!("Successfully updated {} media local files", updated_count),
    }))
}

#[derive(Debug, Deserialize)]
pub struct IgnoreFileRequest {
    pub file_path: String,
    pub file_name: String,
    pub reason: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct IgnoreFileResponse {
    pub success: bool,
    pub message: String,
}

pub async fn ignore_file(
    State(state): State<AppState>,
    Json(request): Json<IgnoreFileRequest>,
) -> Result<Json<IgnoreFileResponse>, (StatusCode, String)> {
    let id = uuid::Uuid::new_v4().to_string();
    let ignored_at = chrono::Utc::now().to_rfc3339();
    
    let result = state.database.repository()
        .add_ignored_file(&id, &request.file_path, &request.file_name, &ignored_at, request.reason.as_deref())
        .await;
    
    match result {
        Ok(_) => Ok(Json(IgnoreFileResponse {
            success: true,
            message: "File added to ignore list".to_string(),
        })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to add ignored file: {}", e))),
    }
}

#[derive(Debug, Serialize)]
pub struct GetIgnoredFilesResponse {
    pub success: bool,
    pub files: Vec<IgnoredFile>,
}

pub async fn get_ignored_files(
    State(state): State<AppState>,
) -> Result<Json<GetIgnoredFilesResponse>, (StatusCode, String)> {
    let files = state.database.repository()
        .get_ignored_files()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to get ignored files: {}", e)))?;
    
    Ok(Json(GetIgnoredFilesResponse {
        success: true,
        files,
    }))
}

#[derive(Debug, Deserialize)]
pub struct RemoveIgnoredFileRequest {
    pub id: String,
}

pub async fn remove_ignored_file(
    State(state): State<AppState>,
    Json(request): Json<RemoveIgnoredFileRequest>,
) -> Result<Json<IgnoreFileResponse>, (StatusCode, String)> {
    let result = state.database.repository()
        .remove_ignored_file(&request.id)
        .await;
    
    match result {
        Ok(_) => Ok(Json(IgnoreFileResponse {
            success: true,
            message: "Removed from ignore list".to_string(),
        })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to remove ignored file: {}", e))),
    }
}

#[derive(Debug, Serialize)]
pub struct GetMediaFilesResponse {
    pub success: bool,
    pub files: Vec<MediaFile>,
    pub total_size: i64,
}

pub async fn get_media_files(
    State(state): State<AppState>,
    Path(media_id): Path<String>,
) -> Result<Json<GetMediaFilesResponse>, (StatusCode, String)> {
    let files = state.database.repository()
        .get_media_files(&media_id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to get file list: {}", e)))?;
    
    let total_size: i64 = files.iter().map(|f| f.file_size).sum();
    
    Ok(Json(GetMediaFilesResponse {
        success: true,
        files,
        total_size,
    }))
}

pub async fn auto_scrape_unmatched(
    State(state): State<AppState>,
    Json(request): Json<AutoScrapeRequest>,
) -> Result<Json<AutoScrapeResponse>, (StatusCode, String)> {
    // 生成会话ID
    let session_id = uuid::Uuid::new_v4().to_string();
    info!("开始自动刮削，会话ID: {}", session_id);
    
    let total_count = request.unmatched_files.len() + request.unmatched_groups.as_ref().map(|g| g.len()).unwrap_or(0);
    
    // 初始化进度跟踪
    {
        let mut progress_map = SCRAPE_PROGRESS.write().await;
        progress_map.insert(session_id.clone(), AutoScrapeProgress {
            current: 0,
            total: total_count,
            file_name: String::new(),
            status: "准备开始...".to_string(),
            message: Some("正在初始化刮削任务".to_string()),
            scraped_count: 0,
            failed_count: 0,
        });
    }
    
    // 克隆需要的数据用于后台任务
    let session_id_clone = session_id.clone();
    let state_clone = state.clone();
    
    // 在后台任务中执行刮削
    tokio::spawn(async move {
        let result = process_auto_scrape(state_clone, request, session_id_clone).await;
        if let Err(e) = result {
            error!("后台刮削任务失败: {}", e);
        }
    });
    
    // 立即返回session_id，让前端开始轮询
    Ok(Json(AutoScrapeResponse {
        success: true,
        session_id,
        scraped_count: 0,
        failed_count: 0,
        results: vec![],
        message: "刮削任务已启动".to_string(),
    }))
}

async fn process_auto_scrape(
    state: AppState,
    request: AutoScrapeRequest,
    session_id: String,
) -> Result<(), String> {
    use crate::models::MediaItem;
    use crate::models::MediaType;
    
    let mut scraped_count = 0;
    let mut failed_count = 0;
    
    let total_files = request.unmatched_files.len();
    let total_groups = request.unmatched_groups.as_ref().map(|g| g.len()).unwrap_or(0);
    let total_count = total_files + total_groups;
    
    info!("开始自动刮削：{} 个单文件，{} 个文件组，并发模式: {}", 
        total_files, total_groups, request.concurrent);
    
    // 准备批量刮削的媒体列表
    let mut media_list = Vec::new();
    let mut file_info_map = std::collections::HashMap::new();
    
    // 收集单文件信息
    for (index, file) in request.unmatched_files.iter().enumerate() {
        let key = format!("file_{}", index);
        
        // 优先使用 JAV 番号
        if let Some(code) = &file.parsed_code {
            media_list.push(serde_json::json!({
                "id": key.clone(),
                "code": code,
                "title": "",
            }));
            file_info_map.insert(key, serde_json::json!({
                "is_group": false,
                "file_path": file.file_path,
                "file_name": file.file_name,
                "file_size": file.file_size,
                "code": code,
            }));
        }
        // 其次使用欧美系列+日期
        else if let (Some(series), Some(date)) = (&file.parsed_series, &file.parsed_date) {
            // 只传递系列名和发布日期，让刮削管理器自动处理
            media_list.push(serde_json::json!({
                "id": key.clone(),
                "series": series,  // 系列名用于选择刮削器
                "release_date": date,  // 发布日期用于生成查询
            }));
            file_info_map.insert(key, serde_json::json!({
                "is_group": false,
                "file_path": file.file_path,
                "file_name": file.file_name,
                "file_size": file.file_size,
                "series": series,
                "date": date,
            }));
        }
        // 再次使用欧美系列+标题
        else if let Some(series) = &file.parsed_series {
            if let Some(title) = &file.parsed_title {
                // 只传递纯标题和系列名，让刮削管理器自动处理
                media_list.push(serde_json::json!({
                    "id": key.clone(),
                    "title": title,  // 只传递纯标题（如 "Scene Title"）
                    "series": series,  // 系列名用于选择刮削器
                }));
                file_info_map.insert(key, serde_json::json!({
                    "is_group": false,
                    "file_path": file.file_path,
                    "file_name": file.file_name,
                    "file_size": file.file_size,
                    "series": series,
                    "title": title,
                }));
            } else {
                warn!("单文件 {} 只有系列名但没有标题或日期", file.file_name);
                failed_count += 1;
            }
        }
        // 最后使用纯标题（没有番号、系列名的文件）
        else if let Some(title) = &file.parsed_title {
            // 如果有年份，构建 "标题 (年份)" 格式
            let query = if let Some(year) = file.parsed_year {
                format!("{} ({})", title, year)
            } else {
                title.clone()
            };
            
            media_list.push(serde_json::json!({
                "id": key.clone(),
                "title": query,  // 使用标题（可能包含年份）
            }));
            file_info_map.insert(key, serde_json::json!({
                "is_group": false,
                "file_path": file.file_path,
                "file_name": file.file_name,
                "file_size": file.file_size,
                "title": title,
                "year": file.parsed_year,
            }));
        }
        else {
            warn!("单文件 {} 无法识别任何有效信息", file.file_name);
            failed_count += 1;
        }
    }
    
    // 收集文件组信息
    if let Some(groups) = &request.unmatched_groups {
        for (index, group) in groups.iter().enumerate() {
            if let Some(code) = group.files.first().and_then(|f| f.scanned_file.parsed_code.as_ref()) {
                let key = format!("group_{}", index);
                media_list.push(serde_json::json!({
                    "id": key.clone(),
                    "code": code,
                    "title": "",
                }));
                
                let files_json: Vec<serde_json::Value> = group.files.iter().map(|f| {
                    serde_json::json!({
                        "file_path": f.scanned_file.file_path,
                        "file_name": f.scanned_file.file_name,
                        "file_size": f.scanned_file.file_size,
                        "part_label": f.part_info.as_ref().map(|p| p.part_label.clone()),
                    })
                }).collect();
                
                file_info_map.insert(key, serde_json::json!({
                    "is_group": true,
                    "group_name": group.base_name,
                    "code": code,
                    "files": files_json,
                }));
            } else {
                warn!("文件组 {} 没有识别到识别号", group.base_name);
                failed_count += 1;
            }
        }
    }
    
    if media_list.is_empty() {
        info!("没有可刮削的文件");
        // 更新进度为完成
        {
            let mut progress_map = SCRAPE_PROGRESS.write().await;
            if let Some(progress) = progress_map.get_mut(&session_id) {
                progress.status = "completed".to_string();
                progress.message = Some("没有可刮削的文件".to_string());
            }
        }
        return Ok(());
    }
    
    // 更新进度：开始刮削
    {
        let mut progress_map = SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.status = format!("正在刮削 (0/{})", media_list.len());
            progress.message = Some(format!("开始{}刮削 {} 个项目", 
                if request.concurrent { "并发" } else { "串行" }, 
                media_list.len()));
        }
    }
    
    // 调用插件批量刮削
    let manager = state.plugin_manager.read().await;
    info!("准备调用插件管理器，并发模式: {}", request.concurrent);
    
    // 使用用户选择的 content_type，默认为 "Scene"
    let content_type = request.content_type.as_deref().unwrap_or("Scene");
    info!("使用内容类型: {}", content_type);
    
    let scrape_results = if request.concurrent {
        info!("使用并发模式批量刮削 {} 个项目", media_list.len());
        manager.batch_scrape_media_concurrent(&media_list, content_type).await
    } else {
        info!("使用串行模式批量刮削 {} 个项目", media_list.len());
        manager.batch_scrape_media(&media_list, content_type).await
    };
    info!("插件管理器调用完成");
    
    match scrape_results {
        Ok(results) => {
            info!("插件批量刮削完成，收到 {} 个结果", results.len());
            
            // 处理刮削结果并保存到数据库（串行）
            for (index, result) in results.iter().enumerate() {
                let current = index + 1;
                
                // 更新进度
                {
                    let mut progress_map = SCRAPE_PROGRESS.write().await;
                    if let Some(progress) = progress_map.get_mut(&session_id) {
                        progress.current = current;
                        progress.total = total_count;
                        progress.status = format!("正在保存 ({}/{})", current, total_count);
                    }
                }
                
                let file_info = match file_info_map.get(&result.media_id) {
                    Some(info) => info,
                    None => {
                        warn!("找不到文件信息: {}", result.media_id);
                        failed_count += 1;
                        continue;
                    }
                };
                
                let is_group = file_info["is_group"].as_bool().unwrap_or(false);
                let display_name = if is_group {
                    file_info["group_name"].as_str().unwrap_or("未知文件组")
                } else {
                    file_info["file_name"].as_str().unwrap_or("未知文件")
                };
                
                if result.success {
                    // 刮削成功，保存到数据库
                    if let Some(scrape_data) = &result.data {
                        // 调试：输出刮削数据
                        info!("刮削数据: {}", serde_json::to_string_pretty(scrape_data).unwrap_or_else(|_| "无法序列化".to_string()));
                        
                        // 获取标题
                        let title = scrape_data.get("title")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Unknown")
                            .to_string();
                        
                        // 创建新媒体项
                        let media_id = uuid::Uuid::new_v4().to_string();
                        let media_result = MediaItem::new(title.clone(), MediaType::Movie);
                        
                        match media_result {
                            Ok(mut media) => {
                                media.id = media_id.clone();
                                
                                // 应用刮削结果
                                apply_scrape_result_to_media(&mut media, scrape_data);
                                
                                // 保存到数据库
                                match state.database.repository().insert_media(&media).await {
                                    Ok(_) => {
                                        // 关联文件
                                        let save_result = if is_group {
                                            // 文件组
                                            if let Some(files) = file_info["files"].as_array() {
                                                let media_files: Vec<MediaFile> = files.iter().enumerate().map(|(i, f)| {
                                                    let file_path = f["file_path"].as_str().unwrap_or("").to_string();
                                                    let file_size = f["file_size"].as_i64().unwrap_or(0);
                                                    let part_label = f["part_label"].as_str().map(|s| s.to_string());
                                                    
                                                    MediaFile::new(
                                                        media_id.clone(),
                                                        file_path,
                                                        file_size,
                                                        Some((i + 1) as i32),
                                                        part_label,
                                                    )
                                                }).collect();
                                                
                                                state.database.repository().save_media_files(&media_files).await
                                            } else {
                                                Err(anyhow::anyhow!("文件组没有文件列表"))
                                            }
                                        } else {
                                            // 单文件
                                            let file_path = file_info["file_path"].as_str().unwrap_or("").to_string();
                                            let file_size = file_info["file_size"].as_i64().unwrap_or(0);
                                            
                                            let media_file = MediaFile::new(
                                                media_id.clone(),
                                                file_path,
                                                file_size,
                                                None,
                                                None,
                                            );
                                            
                                            state.database.repository().save_media_files(&[media_file]).await
                                        };
                                        
                                        match save_result {
                                            Ok(_) => {
                                                // 更新媒体的文件信息
                                                let (first_file_path, total_size) = if is_group {
                                                    // 文件组：使用第一个文件的路径，总大小为所有文件之和
                                                    if let Some(files) = file_info["files"].as_array() {
                                                        let first_path = files.first()
                                                            .and_then(|f| f["file_path"].as_str())
                                                            .unwrap_or("")
                                                            .to_string();
                                                        let total: i64 = files.iter()
                                                            .filter_map(|f| f["file_size"].as_i64())
                                                            .sum();
                                                        (first_path, total)
                                                    } else {
                                                        (String::new(), 0)
                                                    }
                                                } else {
                                                    // 单文件
                                                    let path = file_info["file_path"].as_str().unwrap_or("").to_string();
                                                    let size = file_info["file_size"].as_i64().unwrap_or(0);
                                                    (path, size)
                                                };
                                                
                                                // 更新媒体表中的文件路径和大小
                                                if let Err(e) = state.database.repository()
                                                    .update_media_file_info(&media_id, &first_file_path, total_size)
                                                    .await {
                                                    warn!("更新媒体文件信息失败: {}", e);
                                                }
                                                
                                                info!("{} {} 刮削成功: {}", 
                                                    if is_group { "文件组" } else { "单文件" },
                                                    display_name, title);
                                                scraped_count += 1;
                                                
                                                // 同步演员到数据库
                                                if let Some(actors) = scrape_data.get("actors").and_then(|v| v.as_array()) {
                                                    let actor_names: Vec<String> = actors.iter()
                                                        .filter_map(|v| v.as_str())
                                                        .map(String::from)
                                                        .collect();
                                                    sync_actors_to_db(&state, &actor_names, &media_id).await;
                                                }
                                                
                                                // 更新成功计数
                                                {
                                                    let mut progress_map = SCRAPE_PROGRESS.write().await;
                                                    if let Some(progress) = progress_map.get_mut(&session_id) {
                                                        progress.scraped_count = scraped_count;
                                                    }
                                                }
                                            }
                                            Err(e) => {
                                                error!("{} {} 保存文件关联失败: {}", 
                                                    if is_group { "文件组" } else { "单文件" },
                                                    display_name, e);
                                                failed_count += 1;
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        error!("{} {} 保存到数据库失败: {}", 
                                            if is_group { "文件组" } else { "单文件" },
                                            display_name, e);
                                        failed_count += 1;
                                    }
                                }
                            }
                            Err(e) => {
                                error!("{} {} 创建媒体项失败: {}", 
                                    if is_group { "文件组" } else { "单文件" },
                                    display_name, e);
                                failed_count += 1;
                            }
                        }
                    } else {
                        warn!("{} {} 刮削结果没有数据", 
                            if is_group { "文件组" } else { "单文件" },
                            display_name);
                        failed_count += 1;
                    }
                } else {
                    // 刮削失败
                    let error_msg = result.error.as_deref().unwrap_or("未知错误");
                    warn!("{} {} 刮削失败: {}", 
                        if is_group { "文件组" } else { "单文件" },
                        display_name, error_msg);
                    failed_count += 1;
                }
                
                // 更新失败计数
                {
                    let mut progress_map = SCRAPE_PROGRESS.write().await;
                    if let Some(progress) = progress_map.get_mut(&session_id) {
                        progress.failed_count = failed_count;
                    }
                }
            }
        }
        Err(e) => {
            error!("插件批量刮削失败: {}", e);
            failed_count = media_list.len();
        }
    }
    
    info!("自动刮削完成：成功 {} 个，失败 {} 个", scraped_count, failed_count);
    
    // 标记完成
    {
        let mut progress_map = SCRAPE_PROGRESS.write().await;
        if let Some(progress) = progress_map.get_mut(&session_id) {
            progress.status = "completed".to_string();
            progress.message = Some(format!("刮削完成：成功 {} 个，失败 {} 个", scraped_count, failed_count));
        }
    }
    
    Ok(())
}

/// 应用刮削结果到媒体
fn apply_scrape_result_to_media(media: &mut crate::models::MediaItem, scrape_data: &serde_json::Value) {
    // 刮削器名称
    if let Some(source) = scrape_data.get("source").and_then(|v| v.as_str()) {
        media.scraper_name = Some(source.to_string());
    }
    
    // 识别号
    if let Some(code) = scrape_data.get("code").and_then(|v| v.as_str()) {
        media.code = Some(code.to_string());
    }
    
    // 原始标题
    if let Some(title) = scrape_data.get("original_title").and_then(|v| v.as_str()) {
        media.original_title = Some(title.to_string());
    }
    
    // 年份
    if let Some(year) = scrape_data.get("year").and_then(|v| v.as_i64()) {
        media.year = Some(year as i32);
    }
    
    // 评分
    if let Some(rating) = scrape_data.get("rating").and_then(|v| v.as_f64()) {
        media.rating = Some(rating as f32);
    }
    
    // 时长
    if let Some(runtime) = scrape_data.get("runtime").and_then(|v| v.as_i64()) {
        media.runtime = Some(runtime as i32);
    }
    
    // 简介
    if let Some(overview) = scrape_data.get("overview").and_then(|v| v.as_str()) {
        let _ = media.set_overview(Some(overview.to_string()));
    }
    
    // 海报
    if let Some(poster) = scrape_data.get("poster_url").and_then(|v| v.as_str()) {
        let _ = media.set_poster_url(Some(poster.to_string()));
    }
    
    // 背景图（支持数组格式）
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
    
    // 制作商
    if let Some(studio) = scrape_data.get("studio").and_then(|v| v.as_str()) {
        media.studio = Some(studio.to_string());
    }
    
    // 系列
    if let Some(series) = scrape_data.get("series").and_then(|v| v.as_str()) {
        media.series = Some(series.to_string());
    }
    
    // 发行日期
    if let Some(release_date) = scrape_data.get("release_date").and_then(|v| v.as_str()) {
        media.release_date = Some(release_date.to_string());
    }
    
    // 媒体类型（有码/无码）
    if let Some(media_type_str) = scrape_data.get("media_type").and_then(|v| v.as_str()) {
        if let Ok(mt) = media_type_str.parse::<crate::models::MediaType>() {
            let _ = media.set_media_type(mt);
        }
    }
    
    // 分类
    if let Some(genres) = scrape_data.get("genres").and_then(|v| v.as_array()) {
        let scraped_genres: Vec<String> = genres.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        if !scraped_genres.is_empty() {
            let _ = media.set_genres(&scraped_genres);
        }
    }
    
    // 演员
    if let Some(actors) = scrape_data.get("actors").and_then(|v| v.as_array()) {
        let scraped_cast: Vec<crate::models::Person> = actors.iter()
            .filter_map(|v| v.as_str())
            .map(|name| crate::models::Person::new(name.to_string(), "cast".to_string()))
            .collect();
        if !scraped_cast.is_empty() {
            let _ = media.set_cast(&scraped_cast);
        }
    }
    
    // 预览图
    if let Some(preview_urls) = scrape_data.get("preview_urls").and_then(|v| v.as_array()) {
        let scraped_preview_urls: Vec<String> = preview_urls.iter()
            .filter_map(|v| v.as_str())
            .map(String::from)
            .collect();
        if !scraped_preview_urls.is_empty() {
            let _ = media.set_preview_urls(&scraped_preview_urls);
        }
    }
    
    // 预览视频（保留结构化数据）
    if let Some(preview_video_urls) = scrape_data.get("preview_video_urls").and_then(|v| v.as_array()) {
        if !preview_video_urls.is_empty() {
            let json_str = serde_json::to_string(preview_video_urls).unwrap_or_else(|_| "[]".to_string());
            media.preview_video_urls = Some(json_str);
            media.updated_at = chrono::Utc::now();
        }
    }
    
    // 封面视频
    if let Some(cover_video_url) = scrape_data.get("cover_video_url").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        let _ = media.set_cover_video_url(Some(cover_video_url.to_string()));
    }
    
    // 下载链接
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
}

/// 同步演员到数据库
async fn sync_actors_to_db(state: &AppState, actor_names: &[String], media_id: &str) {
    use crate::database::actor_repository::{find_or_create_actor_by_name, add_actor_to_media};
    
    info!("开始同步演员到数据库: media_id={}, 演员数量={}", media_id, actor_names.len());
    
    if actor_names.is_empty() {
        warn!("演员列表为空，跳过同步");
        return;
    }
    
    for actor_name in actor_names {
        info!("处理演员: {}", actor_name);
        
        // 查找或创建演员
        match find_or_create_actor_by_name(state.database.pool(), actor_name).await {
            Ok(actor) => {
                info!("演员已找到或创建: {} (id={})", actor.name, actor.id);
                
                // 建立演员与媒体的关联
                match add_actor_to_media(
                    state.database.pool(),
                    &actor.id,
                    media_id,
                    None,  // character_name
                    Some("cast".to_string()), // role
                ).await {
                    Ok(_) => {
                        info!("✓ 演员 {} 已关联到媒体 {}", actor.name, media_id);
                    }
                    Err(e) => {
                        error!("✗ 关联演员 {} 到媒体 {} 失败: {}", actor.name, media_id, e);
                    }
                }
            }
            Err(e) => {
                error!("✗ 查找或创建演员 {} 失败: {}", actor_name, e);
            }
        }
    }
    
    info!("演员同步完成: media_id={}", media_id);
}

pub async fn get_auto_scrape_progress(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<Json<AutoScrapeProgress>, (StatusCode, String)> {
    info!("查询进度，会话ID: {}", session_id);
    let progress_map = SCRAPE_PROGRESS.read().await;
    
    // 调试：显示所有会话ID
    let all_sessions: Vec<String> = progress_map.keys().cloned().collect();
    info!("当前所有会话: {:?}", all_sessions);
    
    if let Some(progress) = progress_map.get(&session_id) {
        info!("找到进度：{:?}", progress);
        Ok(Json(progress.clone()))
    } else {
        warn!("会话未找到: {}", session_id);
        Err((StatusCode::NOT_FOUND, format!("Session not found: {}", session_id)))
    }
}
