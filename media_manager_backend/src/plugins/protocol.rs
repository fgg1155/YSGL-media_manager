//! 刮削插件通信协议定义
//! 
//! 插件通过 stdin/stdout 与主程序通信，使用 JSON 格式

use serde::{Deserialize, Serialize};
use crate::models::{UpdateMediaRequest, Person, DownloadLink as MediaDownloadLink, DownloadLinkType as MediaDownloadLinkType};

/// 磁力链接搜索结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MagnetResult {
    pub title: String,
    pub magnet_link: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_count: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub date: Option<String>,
    #[serde(default)]
    pub files: Vec<FileInfo>,
}

/// 文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<String>,
}

/// 单个网站的搜索进度状态（用于流式进度回调）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteSearchProgress {
    pub site_name: String,
    pub status: String,  // "searching", "completed", "failed", "skipped"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_count: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// 插件请求
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum PluginRequest {
    /// 通过ID/番号获取详情
    Get { 
        id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        content_type: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        series: Option<String>,
    },
    /// 搜索
    Search { query: String, page: Option<u32> },
    /// 获取插件信息
    Info,
}

/// 插件响应
#[derive(Debug, Serialize, Deserialize)]
pub struct PluginResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<PluginResponseData>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<serde_json::Value>,  // 支持字符串或复杂对象
}

/// 响应数据
#[derive(Debug, Serialize, Deserialize)]
#[serde(untagged)]
pub enum PluginResponseData {
    /// 单个刮削结果
    Single(ScrapeResult),
    /// 搜索结果列表
    List(SearchResponse),
    /// 插件信息
    Info(PluginInfo),
}

/// 刮削结果 - 统一数据结构
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ScrapeResult {
    /// 番号/ID
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    
    /// 标题
    pub title: String,
    
    /// 原始标题
    #[serde(skip_serializing_if = "Option::is_none")]
    pub original_title: Option<String>,
    
    /// 发售日期 (YYYY-MM-DD)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub release_date: Option<String>,
    
    /// 年份
    #[serde(skip_serializing_if = "Option::is_none")]
    pub year: Option<i32>,
    
    /// 厂商/制作商
    #[serde(skip_serializing_if = "Option::is_none")]
    pub studio: Option<String>,
    
    /// 系列
    #[serde(skip_serializing_if = "Option::is_none")]
    pub series: Option<String>,
    
    /// 导演
    #[serde(skip_serializing_if = "Option::is_none")]
    pub director: Option<String>,
    
    /// 演员列表
    #[serde(default)]
    pub actors: Vec<String>,
    
    /// 标签/类别
    #[serde(default)]
    pub genres: Vec<String>,
    
    /// 封面图URL
    #[serde(skip_serializing_if = "Option::is_none")]
    pub poster_url: Option<String>,
    
    /// 背景图URLs（支持多个背景图）
    #[serde(default)]
    pub backdrop_url: Vec<String>,
    
    /// 预览图URLs
    #[serde(default)]
    pub preview_urls: Vec<String>,
    
    /// 预览视频URLs（支持带清晰度信息的格式）
    /// 格式: [{"quality": "4K", "url": "https://..."}, {"quality": "1080P", "url": "..."}]
    /// 或向后兼容的字符串数组: ["https://...", "https://..."]
    #[serde(default)]
    pub preview_video_urls: Vec<serde_json::Value>,
    
    /// 封面视频URL（短小的视频缩略图，用于悬停播放）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cover_video_url: Option<String>,
    
    /// 简介
    #[serde(skip_serializing_if = "Option::is_none")]
    pub overview: Option<String>,
    
    /// 评分
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rating: Option<f32>,
    
    /// 时长(分钟)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime: Option<i32>,
    
    /// 媒体类型 (Scene/Movie/Censored/Uncensored)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
    
    /// 语言
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    
    /// 国家/地区
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    
    /// 下载链接列表
    #[serde(default)]
    pub download_links: Vec<DownloadLink>,
}

/// 下载链接类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum DownloadLinkType {
    Magnet,
    Ed2k,
    Http,
    Ftp,
    Torrent,
    Pan,
    Other,
}

/// 下载链接
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadLink {
    /// 链接名称
    pub name: String,
    /// 下载地址
    pub url: String,
    /// 链接类型
    pub link_type: DownloadLinkType,
    /// 文件大小
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<String>,
    /// 提取码（网盘用）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub password: Option<String>,
}

/// 搜索响应
#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResponse {
    pub results: Vec<ScrapeResult>,
    pub page: u32,
    pub total_pages: Option<u32>,
    pub total_results: Option<u32>,
}

/// 插件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginInfo {
    /// 插件ID
    pub id: String,
    /// 显示名称
    pub name: String,
    /// 版本
    pub version: String,
    /// 描述
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// 作者
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    /// 支持的ID正则模式
    #[serde(default)]
    pub id_patterns: Vec<String>,
    /// 是否支持搜索
    #[serde(default)]
    pub supports_search: bool,
    /// 刮削器列表
    #[serde(default)]
    pub scrapers: Vec<ScraperInfo>,
}

/// 插件配置文件 (plugin.json)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginConfig {
    /// 插件ID
    pub id: String,
    /// 显示名称
    pub name: String,
    /// 版本
    pub version: String,
    /// 描述
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// 作者
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    /// 可执行文件名
    pub executable: String,
    /// 支持的ID正则模式
    #[serde(default)]
    pub id_patterns: Vec<String>,
    /// 是否支持搜索
    #[serde(default = "default_true")]
    pub supports_search: bool,
    /// 是否启用
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// 刮削器列表
    #[serde(default)]
    pub scrapers: Vec<ScraperInfo>,
}

/// 刮削器信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScraperInfo {
    /// 刮削器名称
    pub name: String,
    /// 显示名称
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
}

fn default_true() -> bool {
    true
}

impl PluginResponse {
    pub fn success(data: PluginResponseData) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }
    
    pub fn error(message: impl Into<String>) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(serde_json::Value::String(message.into())),
        }
    }
}

impl ScrapeResult {
    /// 将刮削结果转换为 UpdateMediaRequest
    /// actors -> cast (Vec<Person>)
    /// director -> crew (Vec<Person>)
    /// download_links -> download_links (Vec<MediaDownloadLink>)
    pub fn to_update_request(&self) -> UpdateMediaRequest {
        // 将 actors (Vec<String>) 转换为 cast (Vec<Person>)
        let cast: Vec<Person> = self.actors.iter()
            .map(|name| Person::new(name.clone(), "actor".to_string()))
            .collect();
        
        // 将 director (Option<String>) 转换为 crew (Vec<Person>)
        let crew: Vec<Person> = if let Some(director) = &self.director {
            vec![Person::new(director.clone(), "director".to_string())]
        } else {
            Vec::new()
        };
        
        // 将 DownloadLink 转换为 MediaDownloadLink
        let download_links: Vec<MediaDownloadLink> = self.download_links.iter()
            .map(|link| {
                let link_type = match link.link_type {
                    DownloadLinkType::Magnet => MediaDownloadLinkType::Magnet,
                    DownloadLinkType::Ed2k => MediaDownloadLinkType::Ed2k,
                    DownloadLinkType::Http => MediaDownloadLinkType::Http,
                    DownloadLinkType::Ftp => MediaDownloadLinkType::Ftp,
                    DownloadLinkType::Torrent => MediaDownloadLinkType::Torrent,
                    DownloadLinkType::Pan => MediaDownloadLinkType::Pan,
                    DownloadLinkType::Other => MediaDownloadLinkType::Other,
                };
                MediaDownloadLink {
                    name: link.name.clone(),
                    url: link.url.clone(),
                    link_type,
                    size: link.size.clone(),
                    password: link.password.clone(),
                }
            })
            .collect();
        
        // 处理 preview_video_urls：提取 URL 字符串
        // 支持两种格式：
        // 1. [{"quality": "4K", "url": "https://..."}, ...] -> 提取 url 字段
        // 2. ["https://...", ...] -> 直接使用
        let preview_video_urls: Vec<String> = self.preview_video_urls.iter()
            .filter_map(|item| {
                if let Some(obj) = item.as_object() {
                    // 字典格式：提取 url 字段
                    obj.get("url").and_then(|v| v.as_str()).map(|s| s.to_string())
                } else if let Some(s) = item.as_str() {
                    // 字符串格式：直接使用
                    Some(s.to_string())
                } else {
                    None
                }
            })
            .collect();
        
        UpdateMediaRequest {
            code: self.code.clone(),
            title: if self.title.is_empty() { None } else { Some(self.title.clone()) },
            original_title: self.original_title.clone(),
            year: self.year,
            release_date: self.release_date.clone(),
            media_type: self.media_type.clone(),
            overview: self.overview.clone(),
            genres: if self.genres.is_empty() { None } else { Some(self.genres.clone()) },
            rating: self.rating,
            runtime: self.runtime,
            language: self.language.clone(),
            country: self.country.clone(),
            budget: None,
            revenue: None,
            status: None,
            poster_url: self.poster_url.clone(),
            backdrop_url: if self.backdrop_url.is_empty() { None } else { Some(self.backdrop_url.clone()) },
            cast: if cast.is_empty() { None } else { Some(cast) },
            crew: if crew.is_empty() { None } else { Some(crew) },
            play_links: None,
            download_links: if download_links.is_empty() { None } else { Some(download_links) },
            preview_urls: if self.preview_urls.is_empty() { None } else { Some(self.preview_urls.clone()) },
            preview_video_urls: if preview_video_urls.is_empty() { None } else { Some(preview_video_urls) },
            cover_video_url: self.cover_video_url.clone(),
            studio: self.studio.clone(),
            series: self.series.clone(),
        }
    }
}
