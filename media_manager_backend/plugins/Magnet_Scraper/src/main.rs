//! 磁力链接刮削插件 - 支持多个网站（优先级：DemoSearch -> SkrBT）

use std::io::{self, BufRead, Write};
use anyhow::{Result, anyhow};
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::json;
use headless_chrome::{Browser, LaunchOptions, Tab};
use std::time::Duration;
use reqwest::blocking::Client;
use uuid::Uuid;
use std::time::{SystemTime, UNIX_EPOCH};

// 目标网站
const KITEYUAN_SITE: &str = "https://demosearch.kiteyuan.info";
const KNABEN_API: &str = "https://api.knaben.org/v1";
const SKRBT_SITE: &str = "https://skrbtux.top";

#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
enum PluginRequest {
    SearchMagnets { query: String },
    Info,
}

#[derive(Debug, Serialize)]
struct PluginResponse {
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<ResponseData>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum ResponseData {
    MagnetList(Vec<MagnetResult>),
    Info(PluginInfo),
    Progress(SearchProgress),
}

/// 搜索进度状态
#[derive(Debug, Serialize, Clone)]
struct SearchProgress {
    site_name: String,
    status: String,  // "searching", "completed", "failed"
    #[serde(skip_serializing_if = "Option::is_none")]
    result_count: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct MagnetResult {
    title: String,
    magnet_link: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    file_count: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    date: Option<String>,
    #[serde(default)]
    files: Vec<FileInfo>,
}

impl MagnetResult {
    /// 提取磁力链接的 info_hash（用于去重）
    fn extract_hash(&self) -> Option<String> {
        // 磁力链接格式: magnet:?xt=urn:btih:HASH&...
        if let Some(start) = self.magnet_link.find("xt=urn:btih:") {
            let hash_start = start + "xt=urn:btih:".len();
            let remaining = &self.magnet_link[hash_start..];
            
            // Hash 可能以 & 或字符串结尾
            let hash_end = remaining.find('&').unwrap_or(remaining.len());
            let hash = &remaining[..hash_end];
            
            // 转换为小写以便比较
            Some(hash.to_lowercase())
        } else {
            None
        }
    }
}

#[derive(Debug, Clone, Serialize)]
struct FileInfo {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<String>,
}

#[derive(Debug, Serialize)]
struct PluginInfo {
    id: String,
    name: String,
    version: String,
    description: Option<String>,
    author: Option<String>,
}

impl PluginResponse {
    fn success(data: ResponseData) -> Self {
        Self { success: true, data: Some(data), error: None }
    }
}

struct MagnetScraper {
    browser: Option<Browser>,
}

impl MagnetScraper {
    fn new() -> Result<Self> {
        // 不立即启动浏览器，延迟到需要时再启动
        Ok(Self { browser: None })
    }
    
    /// 输出进度状态到 stderr（stderr 是无缓冲的，可以实时输出）
    fn emit_progress(site_name: &str, status: &str, result_count: Option<usize>, error: Option<String>) {
        let progress = SearchProgress {
            site_name: site_name.to_string(),
            status: status.to_string(),
            result_count,
            error,
        };
        
        let response = PluginResponse {
            success: true,
            data: Some(ResponseData::Progress(progress)),
            error: None,
        };
        
        if let Ok(json) = serde_json::to_string(&response) {
            // 使用 stderr 输出进度，因为 stderr 是无缓冲的，可以实时传输
            // 添加 PROGRESS: 前缀以便后端区分进度消息和调试信息
            eprintln!("PROGRESS:{}", json);
        }
    }
    
    /// 对磁力链接结果进行 hash 去重
    fn deduplicate_by_hash(results: Vec<MagnetResult>) -> Vec<MagnetResult> {
        use std::collections::HashSet;
        
        let mut seen_hashes = HashSet::new();
        let mut deduplicated = Vec::new();
        let original_count = results.len();
        
        for result in results {
            if let Some(hash) = result.extract_hash() {
                // 如果这个 hash 没见过，就保留这个结果
                if seen_hashes.insert(hash.clone()) {
                    eprintln!("✓ Keeping result: {} (hash: {})", result.title, hash);
                    deduplicated.push(result);
                } else {
                    eprintln!("⊗ Duplicate removed: {} (hash: {})", result.title, hash);
                }
            } else {
                // 如果无法提取 hash，保留结果（可能是格式异常）
                eprintln!("⚠ No hash found for: {}, keeping anyway", result.title);
                deduplicated.push(result);
            }
        }
        
        eprintln!("Deduplication: {} -> {} results", original_count, deduplicated.len());
        deduplicated
    }
    
    /// 延迟初始化浏览器（仅在需要 SkrBT 时调用）
    fn ensure_browser(&mut self) -> Result<&Browser> {
        if self.browser.is_none() {
            eprintln!("Initializing browser for SkrBT fallback...");
            let launch_options = LaunchOptions::default_builder()
                .headless(true)
                .window_size(Some((1920, 1080)))
                .args(vec![
                    std::ffi::OsStr::new("--disable-blink-features=AutomationControlled"),
                    std::ffi::OsStr::new("--disable-web-security"),
                    std::ffi::OsStr::new("--disable-features=IsolateOrigins,site-per-process"),
                ])
                .build()?;
            
            let browser = Browser::new(launch_options)?;
            eprintln!("✓ Browser initialized (headless=true)");
            
            // 给浏览器一点预热时间（首次启动可能需要加载资源）
            std::thread::sleep(std::time::Duration::from_millis(500));
            
            self.browser = Some(browser);
        }
        
        Ok(self.browser.as_ref().unwrap())
    }
    
    /// 搜索磁力链接 - 优先级：Kiteyuan -> Knaben -> SkrBT（带流式进度输出）
    fn search_magnets(&mut self, query: &str) -> Result<Vec<MagnetResult>> {
        eprintln!("=== Starting magnet search for: {} ===", query);
        
        // 1. 优先尝试 Kiteyuan（HTTP API，无需浏览器，中文资源丰富）
        eprintln!("Trying Kiteyuan first...");
        Self::emit_progress("Kiteyuan", "searching", None, None);
        
        match self.search_kiteyuan(query) {
            Ok(results) if !results.is_empty() => {
                eprintln!("✓ Kiteyuan succeeded with {} results", results.len());
                let deduplicated = Self::deduplicate_by_hash(results);
                let count = deduplicated.len();
                Self::emit_progress("Kiteyuan", "completed", Some(count), None);
                
                // 标记其他网站为跳过
                Self::emit_progress("Knaben", "skipped", None, None);
                Self::emit_progress("SkrBT", "skipped", None, None);
                
                return Ok(deduplicated);
            }
            Ok(_) => {
                eprintln!("⚠ Kiteyuan returned 0 results, trying Knaben...");
                Self::emit_progress("Kiteyuan", "completed", Some(0), None);
            }
            Err(e) => {
                eprintln!("✗ Kiteyuan failed: {}, trying Knaben...", e);
                Self::emit_progress("Kiteyuan", "failed", None, Some(e.to_string()));
            }
        }
        
        // 2. 尝试 Knaben（HTTP API，无需浏览器，聚合多个站点）
        eprintln!("Trying Knaben...");
        Self::emit_progress("Knaben", "searching", None, None);
        
        match self.search_knaben(query) {
            Ok(results) if !results.is_empty() => {
                eprintln!("✓ Knaben succeeded with {} results", results.len());
                let deduplicated = Self::deduplicate_by_hash(results);
                let count = deduplicated.len();
                Self::emit_progress("Knaben", "completed", Some(count), None);
                
                // 标记 SkrBT 为跳过
                Self::emit_progress("SkrBT", "skipped", None, None);
                
                return Ok(deduplicated);
            }
            Ok(_) => {
                eprintln!("⚠ Knaben returned 0 results, falling back to SkrBT");
                Self::emit_progress("Knaben", "completed", Some(0), None);
            }
            Err(e) => {
                eprintln!("✗ Knaben failed: {}, falling back to SkrBT", e);
                Self::emit_progress("Knaben", "failed", None, Some(e.to_string()));
            }
        }
        
        // 3. 回退到 SkrBT（需要浏览器）
        eprintln!("Trying SkrBT as final fallback...");
        Self::emit_progress("SkrBT", "searching", None, None);
        
        match self.search_skrbt(query) {
            Ok(results) => {
                eprintln!("✓ SkrBT succeeded with {} results", results.len());
                let deduplicated = Self::deduplicate_by_hash(results);
                let count = deduplicated.len();
                Self::emit_progress("SkrBT", "completed", Some(count), None);
                Ok(deduplicated)
            }
            Err(e) => {
                eprintln!("✗ All sources failed (Kiteyuan, Knaben, SkrBT)");
                Self::emit_progress("SkrBT", "failed", None, Some(e.to_string()));
                Err(anyhow!("All search sources failed"))
            }
        }
    }
    
    /// Kiteyuan 网站搜索（使用 HTTP API，无需浏览器）
    fn search_kiteyuan(&self, query: &str) -> Result<Vec<MagnetResult>> {
        eprintln!("Kiteyuan: Using HTTP API");
        
        // 生成 device_id (使用 UUID v4)
        let device_id = Uuid::new_v4().to_string().replace("-", "");
        
        // 获取当前时间戳（毫秒）
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)?
            .as_millis()
            .to_string();
        
        let client_id = "DEEPSEARCH100-WEB";
        let package_name = "magnet.kiteyuan.info";
        
        // 计算 captcha_sign
        // 算法：按字母顺序排列参数，拼接后加上密钥，然后 MD5
        let sign_string = format!(
            "client_id={}&device_id={}&package_name={}&timestamp={}&key=golang-deepsearch-captcha-secret-key-2025",
            client_id, device_id, package_name, timestamp
        );
        let captcha_sign = format!("1.{:x}", md5::compute(sign_string));
        
        eprintln!("Kiteyuan: device_id = {}", device_id);
        eprintln!("Kiteyuan: timestamp = {}", timestamp);
        eprintln!("Kiteyuan: captcha_sign = {}", captcha_sign);
        
        // 步骤 1: 初始化 captcha，获取 token
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()?;
        
        let init_body = json!({
            "action": "init",
            "client_id": client_id,
            "device_id": device_id,
            "meta": {
                "captcha_sign": captcha_sign,
                "package_name": package_name,
                "timestamp": timestamp,
                "client_version": "1.0.0"
            }
        });
        
        eprintln!("Kiteyuan: Initializing captcha...");
        let init_response = client
            .post("https://demosearch.kiteyuan.info/api/captcha/init")
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            .header("Origin", "https://demosearch.kiteyuan.info")
            .header("Referer", "https://demosearch.kiteyuan.info/")
            .json(&init_body)
            .send()?;
        
        if !init_response.status().is_success() {
            let error_text = init_response.text()?;
            return Err(anyhow!("Captcha init failed: {}", error_text));
        }
        
        #[derive(Deserialize)]
        struct CaptchaResponse {
            captcha_token: String,
        }
        
        let captcha_data: CaptchaResponse = init_response.json()?;
        eprintln!("✓ Kiteyuan: Got captcha token");
        
        // 步骤 2: 使用 token 搜索
        let search_timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)?
            .as_millis()
            .to_string();
        
        let search_sign_string = format!(
            "client_id={}&device_id={}&package_name={}&timestamp={}&key=golang-deepsearch-captcha-secret-key-2025",
            client_id, device_id, package_name, search_timestamp
        );
        let search_captcha_sign = format!("1.{:x}", md5::compute(search_sign_string));
        
        let search_body = json!({
            "query": query,
            "page": 1,
            "sort_key": "date",
            "captcha_token": captcha_data.captcha_token,
            "client_id": client_id,
            "device_id": device_id,
            "package_name": package_name,
            "timestamp": search_timestamp,
            "captcha_sign": search_captcha_sign
        });
        
        eprintln!("Kiteyuan: Searching for: {}", query);
        let search_response = client
            .post("https://demosearch.kiteyuan.info/api/magnet/search/local")
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            .header("Origin", "https://demosearch.kiteyuan.info")
            .header("Referer", format!("https://demosearch.kiteyuan.info/search?q={}", query))
            .json(&search_body)
            .send()?;
        
        if !search_response.status().is_success() {
            let error_text = search_response.text()?;
            return Err(anyhow!("Search failed: {}", error_text));
        }
        
        #[derive(Deserialize)]
        struct SearchResult {
            name: String,
            magnet_url: String,
            size: Option<String>,
            date: Option<String>,
        }
        
        #[derive(Deserialize)]
        struct SearchResponse {
            results: Vec<SearchResult>,
        }
        
        let search_data: SearchResponse = search_response.json()?;
        eprintln!("✓ Kiteyuan: Found {} results", search_data.results.len());
        
        // 转换为 MagnetResult
        let magnets: Vec<MagnetResult> = search_data.results
            .into_iter()
            .map(|r| MagnetResult {
                title: r.name,
                magnet_link: r.magnet_url,
                size: r.size,
                file_count: None,
                date: r.date,
                files: Vec::new(),
            })
            .collect();
        
        Ok(magnets)
    }
    
    /// Knaben 网站搜索（使用公开的 REST API，无需浏览器）
    fn search_knaben(&self, query: &str) -> Result<Vec<MagnetResult>> {
        eprintln!("Knaben: Using public REST API");
        
        // 转换查询关键词：将点号替换为空格
        // 例如: "dorcelclub.25.10.03" -> "dorcelclub 25 10 03"
        let knaben_query = query.replace(".", " ");
        eprintln!("Knaben: Converted query '{}' to '{}'", query, knaben_query);
        
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()?;
        
        // 构建搜索请求
        let search_body = json!({
            "query": knaben_query,
            "order_by": "seeders",
            "order_direction": "desc",
            "size": 50,
            "hide_unsafe": true,
            "hide_xxx": false
        });
        
        eprintln!("Knaben: Searching for: {}", knaben_query);
        let response = client
            .post(KNABEN_API)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            .json(&search_body)
            .send()?;
        
        if !response.status().is_success() {
            let error_text = response.text()?;
            return Err(anyhow!("Knaben API request failed: {}", error_text));
        }
        
        #[derive(Deserialize)]
        struct KnabenHit {
            title: String,
            #[serde(rename = "magnetUrl")]
            magnet_url: Option<String>,
            bytes: Option<u64>,
            seeders: Option<i32>,
            peers: Option<i32>,
            date: Option<String>,
        }
        
        #[derive(Deserialize)]
        struct KnabenResponse {
            hits: Vec<KnabenHit>,
        }
        
        let knaben_data: KnabenResponse = response.json()?;
        eprintln!("✓ Knaben: Found {} results", knaben_data.hits.len());
        
        // 转换为 MagnetResult，过滤掉没有磁力链接的结果
        let magnets: Vec<MagnetResult> = knaben_data.hits
            .into_iter()
            .filter_map(|hit| {
                // 只保留有磁力链接的结果
                hit.magnet_url.map(|magnet_url| {
                    // 格式化文件大小
                    let size = hit.bytes.map(|bytes| {
                        if bytes >= 1_073_741_824 {
                            format!("{:.2} GB", bytes as f64 / 1_073_741_824.0)
                        } else if bytes >= 1_048_576 {
                            format!("{:.2} MB", bytes as f64 / 1_048_576.0)
                        } else if bytes >= 1024 {
                            format!("{:.2} KB", bytes as f64 / 1024.0)
                        } else {
                            format!("{} Byte", bytes)
                        }
                    });
                    
                    MagnetResult {
                        title: hit.title,
                        magnet_link: magnet_url,
                        size,
                        file_count: None,
                        date: hit.date,
                        files: Vec::new(),
                    }
                })
            })
            .collect();
        
        eprintln!("✓ Knaben: Filtered to {} results with magnet links", magnets.len());
        Ok(magnets)
    }
    
    /// 解析 Kiteyuan 搜索结果
    fn extract_kiteyuan_search_results(&self, tab: &Tab) -> Result<Vec<SearchResult>> {
        let html = tab.get_content()?;
        let document = Html::parse_document(&html);
        
        // 使用正确的选择器：.result-card
        let result_card_selector = Selector::parse(".result-card").unwrap();
        let title_selector = Selector::parse(".title.clickable").unwrap();
        let meta_text_selector = Selector::parse(".meta-text").unwrap();
        
        let mut results = Vec::new();
        
        for card in document.select(&result_card_selector) {
            // 提取标题
            let title = match card.select(&title_selector).next() {
                Some(element) => {
                    let text = element.text().collect::<String>().trim().to_string();
                    if text.is_empty() {
                        eprintln!("⚠ Skipping result: empty title");
                        continue;
                    }
                    text
                }
                None => {
                    eprintln!("⚠ Skipping result: no title found");
                    continue;
                }
            };
            
            // 提取元数据（大小和日期）
            let meta_texts: Vec<String> = card.select(&meta_text_selector)
                .map(|e| e.text().collect::<String>().trim().to_string())
                .collect();
            
            let size = meta_texts.get(0).cloned();
            let date = meta_texts.get(1).cloned();
            
            eprintln!("✓ Found result: {} (size: {:?}, date: {:?})", title, size, date);
            
            results.push(SearchResult {
                title: title.clone(),
                detail_url: String::new(), // Kiteyuan 不需要详情页 URL
            });
        }
        
        Ok(results)
    }
    
    /// 从 Kiteyuan 结果卡片提取磁力链接
    fn extract_kiteyuan_magnet(&self, tab: &Tab, result: SearchResult) -> Result<MagnetResult> {
        // 策略 1: 尝试从 Vue 数据中提取磁力链接
        eprintln!("Kiteyuan: Trying to extract magnet from Vue data...");
        
        let vue_extract_script = format!(
            r#"
            (function() {{
                // Try to find Vue instance and extract magnet link
                const app = document.querySelector('#app');
                if (app && app.__vue_app__) {{
                    // Vue 3
                    const vueApp = app.__vue_app__;
                    console.log('Found Vue 3 app');
                    // Try to access reactive data
                }}
                
                // Try to find result data in window
                if (window.__INITIAL_STATE__) {{
                    console.log('Found __INITIAL_STATE__');
                    return window.__INITIAL_STATE__;
                }}
                
                // Try to extract from result cards
                const cards = document.querySelectorAll('.result-card');
                for (let card of cards) {{
                    const titleElement = card.querySelector('.title.clickable');
                    if (!titleElement || titleElement.textContent.trim() !== '{}') {{
                        continue;
                    }}
                    
                    // Try to find magnet in card's Vue data
                    if (card.__vnode && card.__vnode.ctx) {{
                        console.log('Found Vue vnode data');
                        return card.__vnode.ctx;
                    }}
                    
                    // Try to find data attributes
                    const magnetAttr = card.getAttribute('data-magnet');
                    if (magnetAttr) {{
                        return {{ magnet: magnetAttr, source: 'data-attribute' }};
                    }}
                    
                    // Try to find in onclick handlers
                    const openButton = card.querySelector('mdui-button-icon[title="打开"]');
                    if (openButton) {{
                        const onclick = openButton.getAttribute('onclick');
                        if (onclick && onclick.includes('magnet:')) {{
                            const magnetMatch = onclick.match(/magnet:[^'"]+/);
                            if (magnetMatch) {{
                                return {{ magnet: magnetMatch[0], source: 'onclick' }};
                            }}
                        }}
                    }}
                }}
                
                return {{ error: 'No magnet link found in Vue data' }};
            }})();
            "#,
            result.title.replace("'", "\\'").replace("\"", "\\\"").replace("\n", "\\n")
        );
        
        match tab.evaluate(&vue_extract_script, true) {
            Ok(vue_result) => {
                eprintln!("Vue extraction result: {:?}", vue_result);
                if let Some(value) = vue_result.value {
                    if let Some(obj) = value.as_object() {
                        if let Some(magnet) = obj.get("magnet").and_then(|v| v.as_str()) {
                            eprintln!("✓ Found magnet in Vue data!");
                            
                            // Extract metadata
                            let html = tab.get_content()?;
                            let document = Html::parse_document(&html);
                            let result_card_selector = Selector::parse(".result-card").unwrap();
                            let title_selector = Selector::parse(".title.clickable").unwrap();
                            let meta_text_selector = Selector::parse(".meta-text").unwrap();
                            
                            let mut size = None;
                            let mut date = None;
                            
                            for card in document.select(&result_card_selector) {
                                if let Some(title_elem) = card.select(&title_selector).next() {
                                    let card_title = title_elem.text().collect::<String>().trim().to_string();
                                    if card_title == result.title {
                                        let meta_texts: Vec<String> = card.select(&meta_text_selector)
                                            .map(|e| e.text().collect::<String>().trim().to_string())
                                            .collect();
                                        
                                        size = meta_texts.get(0).cloned();
                                        date = meta_texts.get(1).cloned();
                                        break;
                                    }}
                            }
                            
                            return Ok(MagnetResult {
                                title: result.title,
                                magnet_link: magnet.to_string(),
                                size,
                                file_count: None,
                                date,
                                files: Vec::new(),
                            });
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("Vue extraction failed: {}", e);
            }
        }
        
        // 策略 2: 使用异步方式拦截 window.open 调用
        
        // 第一步：设置拦截器
        let setup_script = format!(
            r#"
            (function() {{
                window.__magnetCapture = null;
                const originalOpen = window.open;
                window.open = function(url, target, features) {{
                    console.log('window.open called with:', url);
                    if (url && url.startsWith('magnet:')) {{
                        window.__magnetCapture = url;
                        console.log('Captured magnet:', url);
                        return null; // 阻止实际打开
                    }}
                    return originalOpen.call(window, url, target, features);
                }};
                return true;
            }})();
            "#
        );
        
        tab.evaluate(&setup_script, true)?;
        eprintln!("Kiteyuan: Set up window.open interceptor");
        
        // 第二步：点击"打开"按钮
        let click_script = format!(
            r#"
            (function() {{
                const cards = document.querySelectorAll('.result-card');
                
                for (let card of cards) {{
                    const titleElement = card.querySelector('.title.clickable');
                    if (!titleElement || titleElement.textContent.trim() !== '{}') {{
                        continue;
                    }}
                    
                    console.log('Found matching card, clicking open button...');
                    const openButton = card.querySelector('mdui-button-icon[title="打开"]');
                    if (openButton) {{
                        openButton.click();
                        return true;
                    }}
                    return false;
                }}
                return false;
            }})();
            "#,
            result.title.replace("'", "\\'").replace("\"", "\\\"").replace("\n", "\\n")
        );
        
        let clicked = tab.evaluate(&click_script, true)?
            .value
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        
        if !clicked {
            return Err(anyhow!("Failed to find or click open button"));
        }
        
        eprintln!("Kiteyuan: Clicked open button, waiting for magnet capture...");
        
        // 第三步：等待一小段时间让点击事件处理完成
        std::thread::sleep(Duration::from_millis(500));
        
        // 第四步：检查是否捕获到磁力链接
        let check_script = r#"
            (function() {{
                if (window.__magnetCapture) {{
                    return {{ success: true, magnet: window.__magnetCapture }};
                }}
                return {{ success: false }};
            }})();
        "#;
        
        let check_result = tab.evaluate(check_script, true)?;
        let result_obj = check_result.value.ok_or_else(|| anyhow!("No result from check script"))?;
        
        eprintln!("Kiteyuan: Check result: {:?}", result_obj);
        
        let obj = result_obj.as_object().ok_or_else(|| anyhow!("Result is not an object"))?;
        
        let success = obj.get("success")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        
        if !success {
            return Err(anyhow!("Failed to capture magnet link via window.open interception"));
        }
        
        let magnet_link = obj.get("magnet")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("Magnet link not found in result"))?
            .to_string();
        
        eprintln!("✓ Extracted magnet via window.open interception");
        
        // 清理拦截器
        tab.evaluate("window.open = window.open.__original || window.open;", true).ok();
        
        // 从结果中提取元数据
        let html = tab.get_content()?;
        let document = Html::parse_document(&html);
        let result_card_selector = Selector::parse(".result-card").unwrap();
        let title_selector = Selector::parse(".title.clickable").unwrap();
        let meta_text_selector = Selector::parse(".meta-text").unwrap();
        
        let mut size = None;
        let mut date = None;
        
        for card in document.select(&result_card_selector) {
            if let Some(title_elem) = card.select(&title_selector).next() {
                let card_title = title_elem.text().collect::<String>().trim().to_string();
                if card_title == result.title {
                    let meta_texts: Vec<String> = card.select(&meta_text_selector)
                        .map(|e| e.text().collect::<String>().trim().to_string())
                        .collect();
                    
                    size = meta_texts.get(0).cloned();
                    date = meta_texts.get(1).cloned();
                    break;
                }
            }
        }
        
        Ok(MagnetResult {
            title: result.title,
            magnet_link,
            size,
            file_count: None,
            date,
            files: Vec::new(),
        })
    }
    
    /// 解析 Kiteyuan 搜索结果（旧方法，保留作为备用）
    fn parse_kiteyuan_results(&self, html: &str) -> Result<Vec<MagnetResult>> {
        let document = Html::parse_document(html);
        
        // 根据实际页面结构调整选择器
        // 假设结果在某个列表中，每个结果包含标题和磁力链接
        let result_selector = Selector::parse(".search-result, .result-item, tr").unwrap();
        let title_selector = Selector::parse(".title, .name, a, td:first-child").unwrap();
        let magnet_selector = Selector::parse("a[href^='magnet:']").unwrap();
        let size_selector = Selector::parse(".size, .file-size, td:nth-child(2)").unwrap();
        let date_selector = Selector::parse(".date, .upload-date, td:nth-child(3)").unwrap();
        
        let mut results = Vec::new();
        
        for result_element in document.select(&result_selector) {
            // 提取标题
            let title = match result_element.select(&title_selector).next() {
                Some(element) => {
                    let text = element.text().collect::<String>().trim().to_string();
                    if text.is_empty() {
                        continue;
                    }
                    text
                }
                None => continue,
            };
            
            // 提取磁力链接
            let magnet_link = match result_element.select(&magnet_selector).next() {
                Some(element) => match element.value().attr("href") {
                    Some(href) => href.to_string(),
                    None => continue,
                },
                None => continue,
            };
            
            // 提取大小
            let size = result_element.select(&size_selector)
                .next()
                .map(|e| e.text().collect::<String>().trim().to_string());
            
            // 提取日期
            let date = result_element.select(&date_selector)
                .next()
                .map(|e| e.text().collect::<String>().trim().to_string());
            
            eprintln!("Kiteyuan: Found result - {}", title);
            
            results.push(MagnetResult {
                title,
                magnet_link,
                size,
                file_count: None,
                date,
                files: Vec::new(),
            });
        }
        
        Ok(results)
    }
    
    /// SkrBT 网站搜索（需要浏览器自动化）
    fn search_skrbt(&mut self, query: &str) -> Result<Vec<MagnetResult>> {
        // 延迟初始化浏览器
        let browser = self.ensure_browser()?;
        
        // 创建新标签页
        let tab = browser.new_tab()?;
        
        // 设置反检测脚本（在页面加载前）
        tab.enable_stealth_mode()?;
        tab.evaluate(
            r#"
            // 隐藏 webdriver 标志
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined
            });
            // 伪造 plugins
            Object.defineProperty(navigator, 'plugins', {
                get: () => [1, 2, 3, 4, 5]
            });
            // 设置语言
            Object.defineProperty(navigator, 'languages', {
                get: () => ['zh-CN', 'zh', 'en']
            });
            // 伪造 Chrome 对象
            window.chrome = {
                runtime: {}
            };
            // 伪造权限
            const originalQuery = window.navigator.permissions.query;
            window.navigator.permissions.query = (parameters) => (
                parameters.name === 'notifications' ?
                    Promise.resolve({ state: Notification.permission }) :
                    originalQuery(parameters)
            );
            "#,
            false
        )?;
        
        // 1. 先访问首页
        eprintln!("SkrBT Step 1: Navigating to homepage: {}", SKRBT_SITE);
        tab.navigate_to(SKRBT_SITE)?;
        tab.wait_until_navigated()?;
        
        // 等待 1 秒
        eprintln!("SkrBT: Waiting 1 second on homepage...");
        std::thread::sleep(Duration::from_secs(1));
        
        // 保存首页 HTML 用于调试
        if std::env::var("DEBUG_HTML").is_ok() {
            let homepage_html = tab.get_content()?;
            eprintln!("Homepage HTML length: {} bytes", homepage_html.len());
            if let Err(e) = std::fs::write("debug_homepage.html", &homepage_html) {
                eprintln!("Failed to save homepage HTML: {}", e);
            } else {
                eprintln!("✓ Saved homepage HTML to debug_homepage.html");
            }
        }
        
        // 2. 查找搜索框并输入关键词
        eprintln!("SkrBT Step 2: Finding search input and entering query: {}", query);
        let search_script = format!(
            r#"
            // 查找搜索框（使用 name="keyword"）
            const searchInput = document.querySelector('input[name="keyword"]');
            
            if (searchInput) {{
                searchInput.value = '{}';
                searchInput.focus();
                true;
            }} else {{
                false;
            }}
            "#,
            query
        );
        
        let input_found = tab.evaluate(&search_script, true)?
            .value
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        
        if !input_found {
            return Err(anyhow!("Search input not found on homepage"));
        }
        
        eprintln!("✓ Search input found and filled");
        
        // 3. 提交搜索表单
        eprintln!("SkrBT Step 3: Submitting search form");
        let submit_script = r#"
            (function() {
                const searchInput = document.querySelector('input[name="keyword"]');
                
                if (searchInput) {
                    const form = searchInput.closest('form');
                    if (form) {
                        form.submit();
                        return 'form_submitted';
                    }
                }
                return 'failed';
            })();
        "#;
        
        let submit_result = tab.evaluate(submit_script, true)?
            .value
            .and_then(|v| {
                // 尝试获取字符串值
                if let Some(s) = v.as_str() {
                    Some(s.to_string())
                } else {
                    eprintln!("Debug: submit result value = {:?}", v);
                    None
                }
            })
            .unwrap_or_else(|| "unknown".to_string());
        
        eprintln!("Submit result: {}", submit_result);
        
        // 4. 提交表单后等待 3-4 秒（让 reCAPTCHA 自动验证）
        eprintln!("SkrBT Step 4: Waiting 4 seconds after form submission (for reCAPTCHA)...");
        std::thread::sleep(Duration::from_secs(4));
        
        // 检查 URL 是否变化
        let current_url = tab.get_url();
        eprintln!("Current URL after waiting: {}", current_url);
        
        // 如果还在 reCAPTCHA 页面，再等待一会
        if current_url.contains("recaptcha") {
            eprintln!("Still on reCAPTCHA page, waiting 3 more seconds...");
            std::thread::sleep(Duration::from_secs(3));
            let new_url = tab.get_url();
            eprintln!("URL after additional wait: {}", new_url);
        }
        
        // 5. 获取搜索结果列表
        eprintln!("SkrBT Step 5: Extracting search results...");
        let search_results = self.extract_search_results(&tab)?;
        eprintln!("Found {} search results", search_results.len());
        
        // 处理所有搜索结果
        let results_to_process = &search_results[..];
        
        let mut magnets = Vec::new();
        
        // 遍历搜索结果，获取磁力链接
        for (index, result) in results_to_process.iter().enumerate() {
            eprintln!("Processing result {}/{}: {}", index + 1, search_results.len(), result.title);
            match self.extract_magnet_from_detail(&tab, result.clone()) {
                Ok(magnet) => {
                    eprintln!("✓ Successfully extracted magnet for: {}", result.title);
                    magnets.push(magnet);
                },
                Err(e) => {
                    // 记录错误并继续处理下一个结果
                    eprintln!("✗ Error extracting magnet for '{}': {}", result.title, e);
                    continue;
                }
            }
        }
        
        eprintln!("Total magnets extracted: {}", magnets.len());
        Ok(magnets)
    }
    
    fn extract_search_results(&self, tab: &Tab) -> Result<Vec<SearchResult>> {
        // 获取页面HTML
        let html = tab.get_content()?;
        eprintln!("Page HTML length: {} bytes", html.len());
        
        // 调试：保存 HTML 到文件
        if std::env::var("DEBUG_HTML").is_ok() {
            if let Err(e) = std::fs::write("debug_search.html", &html) {
                eprintln!("Failed to save debug HTML: {}", e);
            } else {
                eprintln!("✓ Saved HTML to debug_search.html");
            }
        }
        
        let document = Html::parse_document(&html);
        
        // 修正选择器：标题在 a.rrt，详情页链接在 href="/detail/"
        let ul_selector = Selector::parse("ul.list-unstyled").unwrap();
        let title_selector = Selector::parse("a.rrt").unwrap();
        let detail_link_selector = Selector::parse("a[href*='/detail/']").unwrap();
        
        // 查找搜索结果列表
        let ul_elements = document.select(&ul_selector);
        
        let mut results = Vec::new();
        
        for ul in ul_elements {
            // 提取标题
            let title = match ul.select(&title_selector).next() {
                Some(a) => a.text().collect::<String>().trim().to_string(),
                None => {
                    eprintln!("⚠ Skipping result: no title found");
                    continue;
                }
            };
            
            // 提取详情页链接
            let detail_link_element = match ul.select(&detail_link_selector).next() {
                Some(e) => e,
                None => {
                    eprintln!("⚠ Skipping '{}': no detail link", title);
                    continue;
                }
            };
            
            let detail_url = match detail_link_element.value().attr("href") {
                Some(href) => href,
                None => {
                    eprintln!("⚠ Skipping '{}': no href attribute", title);
                    continue;
                }
            };
            
            // 跳过外部链接（在线观看链接）
            if detail_url.starts_with("http") && !detail_url.contains(SKRBT_SITE) {
                eprintln!("⚠ Skipping '{}': external link (online watch)", title);
                continue;
            }
            
            // 转换为完整URL
            let full_detail_url = if detail_url.starts_with("http") {
                detail_url.to_string()
            } else {
                format!("{}{}", SKRBT_SITE, detail_url)
            };
            
            eprintln!("✓ Found result: {}", title);
            results.push(SearchResult {
                title,
                detail_url: full_detail_url,
            });
        }
        
        Ok(results)
    }
    
    fn extract_magnet_from_detail(&self, tab: &Tab, result: SearchResult) -> Result<MagnetResult> {
        // 使用 JavaScript 点击链接（模拟真实用户行为，绕过反爬虫）
        // 注意：必须移除 target="_blank" 属性，让链接在当前页面打开
        let click_script = format!(
            r#"
            (function() {{
                // 查找所有搜索结果
                const allUls = document.querySelectorAll('ul.list-unstyled');
                
                for (let ul of allUls) {{
                    // 在每个 ul 中查找详情页链接
                    const detailLink = ul.querySelector('a[href*="/detail/"]');
                    if (detailLink && detailLink.href === '{}') {{
                        // 移除 target="_blank" 属性，让链接在当前页面打开
                        detailLink.removeAttribute('target');
                        // 找到了目标链接，点击它
                        detailLink.click();
                        return true;
                    }}
                }}
                
                return false;
            }})();
            "#,
            result.detail_url
        );
        
        let clicked = tab.evaluate(&click_script, true)?
            .value
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        
        if !clicked {
            eprintln!("✗ Click failed for: {}", result.detail_url);
            return Err(anyhow!("Failed to click detail link"));
        }
        
        eprintln!("✓ Clicked detail link, waiting for navigation...");
        
        // 等待页面跳转（减少等待时间到 2 秒）
        std::thread::sleep(Duration::from_secs(2));
        
        // 检查是否成功跳转到详情页
        let current_url = tab.get_url();
        eprintln!("Current URL after click: {}", current_url);
        
        if !current_url.contains("/detail/") {
            eprintln!("✗ Failed to navigate to detail page, still at: {}", current_url);
            return Err(anyhow!("Failed to navigate to detail page"));
        }
        
        // 直接使用get_content获取页面HTML，然后使用scraper解析
        let html = tab.get_content()?;
        
        // 调试：保存详情页 HTML
        if std::env::var("DEBUG_HTML").is_ok() {
            if let Err(e) = std::fs::write("debug_detail.html", &html) {
                eprintln!("Failed to save detail HTML: {}", e);
            } else {
                eprintln!("✓ Saved detail HTML to debug_detail.html");
            }
        }
        
        let document = Html::parse_document(&html);
        
        // 尝试多种选择器提取磁力链接
        let magnet_selectors = vec![
            "#magnet[href^='magnet:']",
            "a[href^='magnet:']",
            "a.magnet-link[href^='magnet:']",
        ];
        
        let mut magnet_link = None;
        for selector_str in magnet_selectors {
            let selector = Selector::parse(selector_str).unwrap();
            if let Some(element) = document.select(&selector).next() {
                if let Some(href) = element.value().attr("href") {
                    eprintln!("✓ Found magnet link using selector: {}", selector_str);
                    magnet_link = Some(href.to_string());
                    break;
                }
            }
        }
        
        let magnet_link = magnet_link.ok_or_else(|| {
            eprintln!("✗ No magnet link found in detail page");
            eprintln!("Detail page URL: {}", result.detail_url);
            eprintln!("HTML length: {} bytes", html.len());
            anyhow!("No magnet link found in detail page")
        })?;
        
        // 提取其他信息
        let size_selector = Selector::parse(".info span:nth-child(1)").unwrap();
        let size = document.select(&size_selector)
            .next()
            .map(|element| element.text().collect::<String>().trim().to_string());
        
        let date_selector = Selector::parse(".info span:nth-child(2)").unwrap();
        let date = document.select(&date_selector)
            .next()
            .map(|element| element.text().collect::<String>().trim().to_string());
        
        // 返回上一页
        tab.evaluate("window.history.back()", true)?;
        tab.wait_until_navigated()?;
        std::thread::sleep(Duration::from_secs(1));
        
        Ok(MagnetResult {
            title: result.title,
            magnet_link,
            size,
            file_count: None,
            date,
            files: Vec::new(),
        })
    }
}

#[derive(Clone)]
struct SearchResult {
    title: String,
    detail_url: String,
}

fn main() -> Result<()> {
    let mut scraper = MagnetScraper::new()?;
    
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        
        let request: PluginRequest = serde_json::from_str(&line)?;
        
        let response = match request {
            PluginRequest::SearchMagnets { query } => {
                let magnets = scraper.search_magnets(&query)?;
                PluginResponse::success(ResponseData::MagnetList(magnets))
            },
            PluginRequest::Info => {
                PluginResponse::success(ResponseData::Info(PluginInfo {
                    id: "skrbt_scraper".to_string(),
                    name: "SkrBT Scraper".to_string(),
                    version: "1.0.0".to_string(),
                    description: Some("SkrBT magnet link scraper".to_string()),
                    author: Some("Unknown".to_string()),
                }))
            },
        };
        
        serde_json::to_writer(&mut stdout, &response)?;
        writeln!(stdout)?;
        stdout.flush()?;
    }
    
    Ok(())
}