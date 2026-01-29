//! 插件管理器
//! 
//! 负责扫描、加载和调用刮削插件

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;
use tokio::io::AsyncWriteExt;
use anyhow::{Result, anyhow, Context};
use regex::Regex;
use tracing::{info, warn, error, debug};

use super::protocol::*;
use serde::Deserialize;

/// 格式化插件错误信息
fn format_plugin_error(error: Option<serde_json::Value>) -> String {
    match error {
        Some(serde_json::Value::String(s)) => s,
        Some(serde_json::Value::Object(obj)) => {
            // 尝试提取 message 字段
            if let Some(msg) = obj.get("message") {
                match msg {
                    serde_json::Value::String(s) => s.clone(),
                    serde_json::Value::Object(msg_obj) => {
                        // 多语言消息，优先中文
                        msg_obj.get("zh")
                            .or_else(|| msg_obj.get("en"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("Unknown error")
                            .to_string()
                    }
                    _ => msg.to_string(),
                }
            } else {
                serde_json::to_string(&obj).unwrap_or_else(|_| "Unknown error".to_string())
            }
        }
        Some(v) => v.to_string(),
        None => "Unknown error".to_string(),
    }
}

/// 已加载的插件
#[derive(Debug, Clone)]
pub struct LoadedPlugin {
    pub config: PluginConfig,
    pub path: PathBuf,
    pub executable_path: PathBuf,
    compiled_patterns: Vec<Regex>,
}

impl LoadedPlugin {
    /// 检查是否支持该ID
    pub fn supports_id(&self, id: &str) -> bool {
        self.compiled_patterns.iter().any(|p| p.is_match(id))
    }
}

/// 插件管理器
pub struct PluginManager {
    plugins_dir: PathBuf,
    plugins: HashMap<String, LoadedPlugin>,
}

impl PluginManager {
    /// 创建插件管理器
    pub fn new(plugins_dir: impl AsRef<Path>) -> Self {
        Self {
            plugins_dir: plugins_dir.as_ref().to_path_buf(),
            plugins: HashMap::new(),
        }
    }
    
    /// 扫描并加载所有插件
    pub async fn scan_plugins(&mut self) -> Result<()> {
        self.plugins.clear();
        
        if !self.plugins_dir.exists() {
            info!("Creating plugins directory: {:?}", self.plugins_dir);
            std::fs::create_dir_all(&self.plugins_dir)?;
            return Ok(());
        }
        
        let entries = match std::fs::read_dir(&self.plugins_dir) {
            Ok(entries) => entries,
            Err(e) => {
                warn!("Failed to read plugins directory: {}", e);
                return Ok(()); // 返回 Ok 而不是 Err，避免中断启动
            }
        };
        
        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    warn!("Failed to read directory entry: {}", e);
                    continue; // 跳过这个条目，继续处理其他的
                }
            };
            
            let path = entry.path();
            
            if path.is_dir() {
                match self.load_plugin(&path).await {
                    Ok(plugin) => {
                        info!("Loaded plugin: {} v{}", plugin.config.name, plugin.config.version);
                        self.plugins.insert(plugin.config.id.clone(), plugin);
                    }
                    Err(e) => {
                        warn!("Failed to load plugin from {:?}: {}", path, e);
                    }
                }
            }
        }
        
        info!("Loaded {} plugins", self.plugins.len());
        Ok(())
    }
    
    /// 加载单个插件
    async fn load_plugin(&self, plugin_dir: &Path) -> Result<LoadedPlugin> {
        let config_path = plugin_dir.join("plugin.json");
        
        if !config_path.exists() {
            return Err(anyhow!("plugin.json not found"));
        }
        
        let config_content = std::fs::read_to_string(&config_path)
            .context("Failed to read plugin.json")?;
        
        let config: PluginConfig = serde_json::from_str(&config_content)
            .context("Failed to parse plugin.json")?;
        
        if !config.enabled {
            return Err(anyhow!("Plugin is disabled"));
        }
        
        let executable_path = plugin_dir.join(&config.executable);
        
        if !executable_path.exists() {
            return Err(anyhow!("Executable not found: {}", config.executable));
        }
        
        // 编译ID匹配正则
        let compiled_patterns: Vec<Regex> = config.id_patterns
            .iter()
            .filter_map(|p| {
                Regex::new(p).map_err(|e| {
                    warn!("Invalid regex pattern '{}': {}", p, e);
                    e
                }).ok()
            })
            .collect();
        
        Ok(LoadedPlugin {
            config,
            path: plugin_dir.to_path_buf(),
            executable_path,
            compiled_patterns,
        })
    }
    
    /// 获取所有已加载的插件
    pub fn list_plugins(&self) -> Vec<&LoadedPlugin> {
        self.plugins.values().collect()
    }
    
    /// 获取插件信息列表
    pub fn get_plugin_infos(&self) -> Vec<PluginInfo> {
        self.plugins.values().map(|p| PluginInfo {
            id: p.config.id.clone(),
            name: p.config.name.clone(),
            version: p.config.version.clone(),
            description: p.config.description.clone(),
            author: p.config.author.clone(),
            id_patterns: p.config.id_patterns.clone(),
            supports_search: p.config.supports_search,
            scrapers: p.config.scrapers.clone(),
        }).collect()
    }
    
    /// 根据ID自动选择插件并刮削
    pub async fn scrape_auto(&self, id: &str) -> Result<ScrapeResult> {
        self.scrape_auto_with_type_and_series(id, None, None).await
    }
    
    /// 根据ID自动选择插件并刮削（带内容类型）
    pub async fn scrape_auto_with_type(&self, id: &str, content_type: Option<String>) -> Result<ScrapeResult> {
        self.scrape_auto_with_type_and_series(id, content_type, None).await
    }
    
    /// 根据ID自动选择插件并刮削（带内容类型和系列名）
    pub async fn scrape_auto_with_type_and_series(&self, id: &str, content_type: Option<String>, series: Option<String>) -> Result<ScrapeResult> {
        let id_upper = id.to_uppercase();
        
        // 首先尝试按 ID 模式匹配
        for plugin in self.plugins.values() {
            if plugin.supports_id(&id_upper) {
                debug!("Auto-selected plugin '{}' for ID '{}'", plugin.config.id, id);
                return self.scrape_with_plugin_full(&plugin.config.id, &id_upper, content_type.clone(), series.clone()).await;
            }
        }
        
        // 如果没有匹配的 ID 模式，只尝试 media_scraper 插件
        // media_scraper 插件内部会自动检测类型（JAV 或欧美）
        debug!("No ID pattern matched for '{}', trying media_scraper plugin...", id);
        
        if let Some(plugin) = self.plugins.get("media_scraper") {
            debug!("Trying media_scraper plugin with internal type detection");
            // 直接返回 media_scraper 的结果，无论成功还是失败
            return self.scrape_with_plugin_full(&plugin.config.id, id, content_type, series).await;
        }
        
        Err(anyhow!("No plugin supports ID format: {}", id))
    }
    
    /// 使用指定插件刮削
    pub async fn scrape_with_plugin(&self, plugin_id: &str, id: &str) -> Result<ScrapeResult> {
        self.scrape_with_plugin_full(plugin_id, id, None, None).await
    }
    
    /// 使用指定插件刮削（带内容类型）
    pub async fn scrape_with_plugin_and_type(&self, plugin_id: &str, id: &str, content_type: Option<String>) -> Result<ScrapeResult> {
        self.scrape_with_plugin_full(plugin_id, id, content_type, None).await
    }
    
    /// 使用指定插件刮削（完整参数：内容类型和系列名）
    pub async fn scrape_with_plugin_full(&self, plugin_id: &str, id: &str, content_type: Option<String>, series: Option<String>) -> Result<ScrapeResult> {
        let plugin = self.plugins.get(plugin_id)
            .ok_or_else(|| anyhow!("Plugin not found: {}", plugin_id))?;
        
        let request = PluginRequest::Get { 
            id: id.to_string(),
            content_type,
            series,
        };
        let response = self.call_plugin(plugin, &request).await?;
        
        match response.data {
            Some(PluginResponseData::Single(result)) => {
                info!("Scrape result - release_date: {:?}, year: {:?}", result.release_date, result.year);
                Ok(result)
            },
            _ => Err(anyhow!(format_plugin_error(response.error))),
        }
    }
    
    /// 使用指定插件搜索
    pub async fn search_with_plugin(&self, plugin_id: &str, query: &str, page: Option<u32>) -> Result<SearchResponse> {
        let plugin = self.plugins.get(plugin_id)
            .ok_or_else(|| anyhow!("Plugin not found: {}", plugin_id))?;
        
        if !plugin.config.supports_search {
            return Err(anyhow!("Plugin '{}' does not support search", plugin_id));
        }
        
        let request = PluginRequest::Search { 
            query: query.to_string(), 
            page 
        };
        let response = self.call_plugin(plugin, &request).await?;
        
        match response.data {
            Some(PluginResponseData::List(results)) => Ok(results),
            _ => Err(anyhow!(format_plugin_error(response.error))),
        }
    }
    
    /// 搜索磁力链接（使用特定插件）
    pub async fn search_magnets(&self, plugin_id: &str, query: &str) -> Result<Vec<MagnetResult>> {
        let plugin = self.plugins.get(plugin_id)
            .ok_or_else(|| anyhow!("Plugin not found: {}", plugin_id))?;
        
        // 创建自定义请求
        let request_json = serde_json::json!({
            "action": "search_magnets",
            "query": query
        });
        
        let request_str = serde_json::to_string(&request_json)?;
        debug!("Calling plugin '{}' with: {}", plugin.config.id, request_str);
        
        let mut child = Command::new(&plugin.executable_path)
            .current_dir(&plugin.path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to spawn plugin process")?;
        
        // 写入请求
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(request_str.as_bytes()).await?;
            stdin.write_all(b"\n").await?;
            drop(stdin);
        }
        
        // 读取响应
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(120),  // 磁力搜索可能需要更长时间
            child.wait_with_output()
        ).await
            .context("Plugin timeout")?
            .context("Failed to get plugin output")?;
        
        // 输出插件的 stderr（调试信息）
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.is_empty() {
            info!("Plugin '{}' stderr:\n{}", plugin.config.id, stderr);
        }
        
        if !output.status.success() {
            error!("Plugin '{}' failed with status: {}", plugin.config.id, output.status);
            return Err(anyhow!("Plugin execution failed: {}", stderr));
        }
        
        let stdout = String::from_utf8_lossy(&output.stdout);
        debug!("Plugin '{}' response: {}", plugin.config.id, stdout);
        
        // 解析响应
        for line in stdout.lines() {
            let line = line.trim();
            if line.starts_with('{') {
                #[derive(Deserialize)]
                struct MagnetResponse {
                    success: bool,
                    data: Option<Vec<MagnetResult>>,
                    error: Option<String>,
                }
                
                let response: MagnetResponse = serde_json::from_str(line)
                    .context("Failed to parse plugin response")?;
                
                if response.success {
                    return Ok(response.data.unwrap_or_default());
                } else {
                    return Err(anyhow!(response.error.unwrap_or_else(|| "Unknown error".to_string())));
                }
            }
        }
        
        Err(anyhow!("No valid JSON response from plugin"))
    }
    
    /// 搜索磁力链接（带流式进度回调）
    pub async fn search_magnets_with_progress<F>(
        &self, 
        plugin_id: &str, 
        query: &str,
        progress_callback: F
    ) -> Result<Vec<MagnetResult>> 
    where
        F: Fn(SiteSearchProgress) + Send + Sync + 'static,
    {
        let plugin = self.plugins.get(plugin_id)
            .ok_or_else(|| anyhow!("Plugin not found: {}", plugin_id))?;
        
        // 创建自定义请求
        let request_json = serde_json::json!({
            "action": "search_magnets",
            "query": query
        });
        
        let request_str = serde_json::to_string(&request_json)?;
        debug!("Calling plugin '{}' with: {}", plugin.config.id, request_str);
        
        let mut child = Command::new(&plugin.executable_path)
            .current_dir(&plugin.path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to spawn plugin process")?;
        
        // 获取 stdout 和 stderr（在写入 stdin 之前）
        let stdout = child.stdout.take()
            .ok_or_else(|| anyhow!("Failed to capture stdout"))?;
        let stderr = child.stderr.take()
            .ok_or_else(|| anyhow!("Failed to capture stderr"))?;
        
        use tokio::io::{AsyncBufReadExt, BufReader};
        use std::sync::Arc;
        
        // 将回调包装为 Arc 以便在多个任务中共享
        let progress_callback = Arc::new(progress_callback);
        let progress_callback_clone = Arc::clone(&progress_callback);
        
        // 先启动 stderr 读取任务（在写入 stdin 之前）
        let stderr_task = tokio::spawn(async move {
            let mut stderr_reader = BufReader::new(stderr).lines();
            info!("Started stderr reader task");
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                let line = line.trim();
                info!("Stderr line received: {}", line);
                
                // 检查是否是进度消息（以 PROGRESS: 开头）
                if let Some(json_str) = line.strip_prefix("PROGRESS:") {
                    info!("Found PROGRESS message: {}", json_str);
                    if let Ok(value) = serde_json::from_str::<serde_json::Value>(json_str) {
                        if let Some(data) = value.get("data") {
                            if data.get("site_name").is_some() {
                                #[derive(serde::Deserialize)]
                                struct ProgressResponse {
                                    data: SiteSearchProgress,
                                }
                                
                                if let Ok(progress_resp) = serde_json::from_value::<ProgressResponse>(value) {
                                    info!("Progress callback: {} - {}", progress_resp.data.site_name, progress_resp.data.status);
                                    progress_callback_clone(progress_resp.data);
                                }
                            }
                        }
                    }
                } else if !line.is_empty() {
                    // 其他 stderr 输出作为调试信息
                    debug!("Plugin stderr: {}", line);
                }
            }
            info!("Stderr reader task finished");
        });
        
        // 写入请求（在 stderr 任务启动之后）
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(request_str.as_bytes()).await?;
            stdin.write_all(b"\n").await?;
            drop(stdin);
        }
        
        // 读取 stdout（最终结果）
        let mut stdout_reader = BufReader::new(stdout).lines();
        let mut final_results = None;
        
        while let Ok(Some(line)) = stdout_reader.next_line().await {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            
            info!("Parsing stdout line: {}", line);
            
            if line.starts_with('{') {
                // 尝试解析为最终结果
                #[derive(Deserialize)]
                struct MagnetResponse {
                    success: bool,
                    data: Option<Vec<MagnetResult>>,
                    error: Option<String>,
                }
                
                if let Ok(response) = serde_json::from_str::<MagnetResponse>(line) {
                    if response.success {
                        if let Some(results) = response.data {
                            final_results = Some(results);
                        }
                    } else if let Some(error) = response.error {
                        return Err(anyhow!("Plugin error: {}", error));
                    }
                }
            }
        }
        
        // 等待 stderr 任务完成
        let _ = stderr_task.await;
        
        // 等待进程结束
        let status = child.wait().await?;
        
        if !status.success() {
            error!("Plugin '{}' failed with status: {}", plugin.config.id, status);
            return Err(anyhow!("Plugin execution failed"));
        }
        
        final_results.ok_or_else(|| anyhow!("No results from plugin"))
    }
    
    /// 调用插件
    async fn call_plugin(&self, plugin: &LoadedPlugin, request: &PluginRequest) -> Result<PluginResponse> {
        let request_json = serde_json::to_string(request)?;
        debug!("Calling plugin '{}' with: {}", plugin.config.id, request_json);
        
        let mut child = Command::new(&plugin.executable_path)
            .current_dir(&plugin.path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to spawn plugin process")?;
        
        // 写入请求
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(request_json.as_bytes()).await?;
            stdin.write_all(b"\n").await?;
            drop(stdin);
        }
        
        // 读取响应 - 增加超时时间到 120 秒（与磁力刮削一致）
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            child.wait_with_output()
        ).await
            .context("Plugin timeout")?
            .context("Failed to get plugin output")?;
        
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("Plugin '{}' failed: {}", plugin.config.id, stderr);
            return Err(anyhow!("Plugin execution failed: {}", stderr));
        }
        
        let stdout = String::from_utf8_lossy(&output.stdout);
        debug!("Plugin '{}' response: {}", plugin.config.id, stdout);
        
        // 解析响应（取第一行有效JSON）
        for line in stdout.lines() {
            let line = line.trim();
            if line.starts_with('{') {
                let response: PluginResponse = serde_json::from_str(line)
                    .context("Failed to parse plugin response")?;
                return Ok(response);
            }
        }
        
        Err(anyhow!("No valid JSON response from plugin"))
    }
    
    /// 重新加载插件
    pub async fn reload(&mut self) -> Result<()> {
        info!("Reloading plugins...");
        self.scan_plugins().await
    }
    
    /// 批量刮削媒体（串行）
    pub async fn batch_scrape_media(&self, media_list: &[serde_json::Value], content_type: &str) -> Result<Vec<BatchScrapeMediaResult>> {
        // 使用 media_scraper 插件
        let plugin = self.plugins.get("media_scraper")
            .ok_or_else(|| anyhow!("media_scraper plugin not found"))?;
        
        let request_json = serde_json::json!({
            "action": "batch_scrape_media",
            "media_list": media_list,
            "concurrent": false,
            "scrape_mode": "auto",  // 使用 auto 模式，让插件根据字段自动判断
            "content_type": content_type  // 使用用户选择的内容类型
        });
        
        self.call_batch_scrape_plugin(plugin, &request_json).await
    }
    
    /// 批量刮削媒体（并发）
    pub async fn batch_scrape_media_concurrent(&self, media_list: &[serde_json::Value], content_type: &str) -> Result<Vec<BatchScrapeMediaResult>> {
        // 使用 media_scraper 插件
        let plugin = self.plugins.get("media_scraper")
            .ok_or_else(|| anyhow!("media_scraper plugin not found"))?;
        
        let request_json = serde_json::json!({
            "action": "batch_scrape_media",
            "media_list": media_list,
            "concurrent": true,
            "scrape_mode": "auto",  // 使用 auto 模式，让插件根据字段自动判断
            "content_type": content_type  // 使用用户选择的内容类型
        });
        
        self.call_batch_scrape_plugin(plugin, &request_json).await
    }
    
    /// 调用批量刮削插件
    async fn call_batch_scrape_plugin(&self, plugin: &LoadedPlugin, request_json: &serde_json::Value) -> Result<Vec<BatchScrapeMediaResult>> {
        let request_str = serde_json::to_string(request_json)?;
        debug!("Calling plugin '{}' with batch scrape request", plugin.config.id);
        
        let mut child = Command::new(&plugin.executable_path)
            .current_dir(&plugin.path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to spawn plugin process")?;
        
        // 写入请求
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(request_str.as_bytes()).await?;
            stdin.write_all(b"\n").await?;
            drop(stdin);
        }
        
        // 读取响应 - 批量刮削可能需要更长时间
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(300),  // 5分钟超时
            child.wait_with_output()
        ).await
            .context("Plugin timeout")?
            .context("Failed to get plugin output")?;
        
        // 输出插件的 stderr（调试信息）
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.is_empty() {
            info!("Plugin '{}' stderr:\n{}", plugin.config.id, stderr);
        }
        
        if !output.status.success() {
            error!("Plugin '{}' failed with status: {}", plugin.config.id, output.status);
            return Err(anyhow!("Plugin execution failed: {}", stderr));
        }
        
        let stdout = String::from_utf8_lossy(&output.stdout);
        debug!("Plugin '{}' response length: {} bytes", plugin.config.id, stdout.len());
        
        // 解析响应
        for line in stdout.lines() {
            let line = line.trim();
            if line.starts_with('{') {
                #[derive(Deserialize)]
                struct BatchScrapeResponse {
                    success: bool,
                    data: Option<Vec<BatchScrapeMediaResult>>,
                    error: Option<String>,
                }
                
                let response: BatchScrapeResponse = serde_json::from_str(line)
                    .context("Failed to parse plugin response")?;
                
                if response.success {
                    return Ok(response.data.unwrap_or_default());
                } else {
                    return Err(anyhow!(response.error.unwrap_or_else(|| "Unknown error".to_string())));
                }
            }
        }
        
        Err(anyhow!("No valid JSON response from plugin"))
    }
}

/// 批量刮削媒体结果
#[derive(Debug, Clone, Deserialize)]
pub struct BatchScrapeMediaResult {
    pub media_id: String,
    pub success: bool,
    pub data: Option<serde_json::Value>,
    pub error: Option<String>,
}
