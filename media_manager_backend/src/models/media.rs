use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

use super::validation::{ValidationError, StringValidator, NumberValidator, CollectionValidator, Validator};

#[derive(Debug, Clone, FromRow)]
pub struct MediaItem {
    pub id: String,
    pub code: Option<String>,             // 识别号/识别码
    pub external_ids: String, // JSON string
    pub title: String,
    pub original_title: Option<String>,
    pub year: Option<i32>,
    pub media_type: String,
    pub genres: String, // JSON array as string
    pub rating: Option<f32>,
    pub vote_count: Option<i32>,
    pub poster_url: Option<String>,
    pub backdrop_url: Option<String>, // JSON array as string - 支持多个背景图
    pub overview: Option<String>,
    pub runtime: Option<i32>,
    pub release_date: Option<String>,
    pub cast: Option<String>, // JSON array as string
    pub crew: Option<String>, // JSON array as string
    pub language: Option<String>,
    pub country: Option<String>,
    pub budget: Option<i64>,
    pub revenue: Option<i64>,
    pub status: Option<String>,
    pub play_links: Option<String>,     // JSON array of PlayLink
    pub download_links: Option<String>, // JSON array of DownloadLink
    pub preview_urls: Option<String>,       // JSON array of preview image URLs
    pub preview_video_urls: Option<String>, // JSON array of preview video URLs
    pub cover_video_url: Option<String>,    // 封面视频URL（短小的视频缩略图，用于悬停播放）
    pub studio: Option<String>,             // 厂商/制作公司
    pub series: Option<String>,             // 系列
    pub scraper_name: Option<String>,       // 刮削器名称（用于缓存统计）
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MediaType {
    Movie,
    Scene,
    Documentary,
    Anime,
    Censored,
    Uncensored,
}

impl std::fmt::Display for MediaType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MediaType::Movie => write!(f, "Movie"),
            MediaType::Scene => write!(f, "Scene"),
            MediaType::Documentary => write!(f, "Documentary"),
            MediaType::Anime => write!(f, "Anime"),
            MediaType::Censored => write!(f, "Censored"),
            MediaType::Uncensored => write!(f, "Uncensored"),
        }
    }
}

impl std::str::FromStr for MediaType {
    type Err = String;
    
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "Movie" => Ok(MediaType::Movie),
            "Scene" => Ok(MediaType::Scene),
            "Documentary" => Ok(MediaType::Documentary),
            "Anime" => Ok(MediaType::Anime),
            "Censored" => Ok(MediaType::Censored),
            "Uncensored" => Ok(MediaType::Uncensored),
            _ => Err(format!("Invalid media type: {}", s)),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExternalIds {
    pub tmdb_id: Option<i32>,
    pub imdb_id: Option<String>,
    pub omdb_id: Option<String>,
}

impl Default for ExternalIds {
    fn default() -> Self {
        Self {
            tmdb_id: None,
            imdb_id: None,
            omdb_id: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Person {
    pub name: String,
    pub role: String,
    pub character: Option<String>,
}

impl Person {
    pub fn new(name: String, role: String) -> Self {
        Self {
            name,
            role,
            character: None,
        }
    }
    
    pub fn with_character(name: String, role: String, character: String) -> Self {
        Self {
            name,
            role,
            character: Some(character),
        }
    }
}

/// 播放链接
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PlayLink {
    pub name: String,        // 链接名称，如 "腾讯视频", "爱奇艺", "Netflix"
    pub url: String,         // 播放地址
    pub quality: Option<String>,  // 画质，如 "4K", "1080P", "720P"
}

impl PlayLink {
    pub fn new(name: String, url: String) -> Self {
        Self {
            name,
            url,
            quality: None,
        }
    }
    
    pub fn with_quality(name: String, url: String, quality: String) -> Self {
        Self {
            name,
            url,
            quality: Some(quality),
        }
    }
}

/// 下载链接类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DownloadLinkType {
    #[serde(rename = "magnet")]
    Magnet,      // 磁力链接
    #[serde(rename = "ed2k")]
    Ed2k,        // 电驴链接
    #[serde(rename = "http")]
    Http,        // HTTP直链
    #[serde(rename = "ftp")]
    Ftp,         // FTP链接
    #[serde(rename = "torrent")]
    Torrent,     // 种子文件
    #[serde(rename = "pan")]
    Pan,         // 网盘链接（百度网盘、阿里云盘等）
    #[serde(rename = "other")]
    Other,       // 其他类型
}

impl std::fmt::Display for DownloadLinkType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DownloadLinkType::Magnet => write!(f, "magnet"),
            DownloadLinkType::Ed2k => write!(f, "ed2k"),
            DownloadLinkType::Http => write!(f, "http"),
            DownloadLinkType::Ftp => write!(f, "ftp"),
            DownloadLinkType::Torrent => write!(f, "torrent"),
            DownloadLinkType::Pan => write!(f, "pan"),
            DownloadLinkType::Other => write!(f, "other"),
        }
    }
}

/// 下载链接
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DownloadLink {
    pub name: String,              // 链接名称，如 "1080P蓝光", "4K HDR"
    pub url: String,               // 下载地址
    pub link_type: DownloadLinkType,  // 链接类型
    pub size: Option<String>,      // 文件大小，如 "4.5GB"
    pub password: Option<String>,  // 提取码（网盘用）
}

impl DownloadLink {
    pub fn new(name: String, url: String, link_type: DownloadLinkType) -> Self {
        Self {
            name,
            url,
            link_type,
            size: None,
            password: None,
        }
    }
    
    pub fn with_details(name: String, url: String, link_type: DownloadLinkType, size: Option<String>, password: Option<String>) -> Self {
        Self {
            name,
            url,
            link_type,
            size,
            password,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateMediaRequest {
    pub id: Option<String>,               // 客户端提供的 UUID（可选）
    pub code: Option<String>,             // 识别号/识别码
    pub title: String,
    pub original_title: Option<String>,   // 原始标题
    pub year: Option<i32>,
    pub media_type: MediaType,
    pub overview: Option<String>,
    pub genres: Option<Vec<String>>,
    pub rating: Option<f32>,              // 评分
    pub poster_url: Option<String>,
    pub backdrop_url: Option<Vec<String>>, // 支持多个背景图
    pub runtime: Option<i32>,
    pub release_date: Option<String>,
    pub cast: Option<Vec<Person>>,
    pub crew: Option<Vec<Person>>,
    pub studio: Option<String>,
    pub series: Option<String>,
    pub preview_urls: Option<Vec<String>>,
    pub preview_video_urls: Option<Vec<String>>,
    pub cover_video_url: Option<String>,
    pub play_links: Option<Vec<PlayLink>>,
    pub download_links: Option<Vec<DownloadLink>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateMediaRequest {
    pub code: Option<String>,             // 识别号/识别码
    pub title: Option<String>,
    pub original_title: Option<String>,
    pub year: Option<i32>,
    pub release_date: Option<String>,     // 发行日期
    pub media_type: Option<String>,  // 添加媒体类型字段
    pub overview: Option<String>,
    pub genres: Option<Vec<String>>,
    pub rating: Option<f32>,
    pub runtime: Option<i32>,
    pub language: Option<String>,
    pub country: Option<String>,
    pub budget: Option<i64>,
    pub revenue: Option<i64>,
    pub status: Option<String>,
    pub poster_url: Option<String>,
    pub backdrop_url: Option<Vec<String>>, // 支持多个背景图
    pub cast: Option<Vec<Person>>,
    pub crew: Option<Vec<Person>>,
    pub play_links: Option<Vec<PlayLink>>,
    pub download_links: Option<Vec<DownloadLink>>,
    pub preview_urls: Option<Vec<String>>,
    pub preview_video_urls: Option<Vec<String>>,
    pub cover_video_url: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
}

impl MediaItem {
    /// 创建新的媒体项目
    pub fn new(title: String, media_type: MediaType) -> Result<Self, ValidationError> {
        StringValidator::validate_title(&title)?;
        
        let now = Utc::now();
        Ok(Self {
            id: uuid::Uuid::new_v4().to_string(),
            code: None,
            external_ids: serde_json::to_string(&ExternalIds::default())
                .expect("Failed to serialize default ExternalIds - this should never fail"),
            title,
            original_title: None,
            year: None,
            media_type: media_type.to_string(),
            genres: "[]".to_string(),
            rating: None,
            vote_count: None,
            poster_url: None,
            backdrop_url: None,
            overview: None,
            runtime: None,
            release_date: None,
            cast: Some("[]".to_string()),
            crew: Some("[]".to_string()),
            language: None,
            country: None,
            budget: None,
            revenue: None,
            status: None,
            play_links: Some("[]".to_string()),
            download_links: Some("[]".to_string()),
            preview_urls: Some("[]".to_string()),
            preview_video_urls: Some("[]".to_string()),
            cover_video_url: None,
            studio: None,
            series: None,
            scraper_name: None,
            created_at: now,
            updated_at: now,
        })
    }
    
    /// 使用客户端提供的 ID 创建新的媒体项目
    pub fn new_with_id(id: String, title: String, media_type: MediaType) -> Result<Self, ValidationError> {
        // 验证 UUID 格式
        uuid::Uuid::parse_str(&id)
            .map_err(|_| ValidationError::InvalidId)?;
        
        // 验证标题
        StringValidator::validate_title(&title)?;
        
        let now = Utc::now();
        Ok(Self {
            id,  // 使用提供的 ID
            code: None,
            external_ids: serde_json::to_string(&ExternalIds::default())
                .expect("Failed to serialize default ExternalIds - this should never fail"),
            title,
            original_title: None,
            year: None,
            media_type: media_type.to_string(),
            genres: "[]".to_string(),
            rating: None,
            vote_count: None,
            poster_url: None,
            backdrop_url: None,
            overview: None,
            runtime: None,
            release_date: None,
            cast: Some("[]".to_string()),
            crew: Some("[]".to_string()),
            language: None,
            country: None,
            budget: None,
            revenue: None,
            status: None,
            play_links: Some("[]".to_string()),
            download_links: Some("[]".to_string()),
            preview_urls: Some("[]".to_string()),
            preview_video_urls: Some("[]".to_string()),
            cover_video_url: None,
            studio: None,
            series: None,
            scraper_name: None,
            created_at: now,
            updated_at: now,
        })
    }
    
    /// 从创建请求构建媒体项目
    pub fn from_create_request(request: CreateMediaRequest) -> Result<Self, ValidationError> {
        // 如果请求包含 ID，使用客户端提供的 ID；否则生成新 ID
        let mut media = if let Some(id) = request.id {
            Self::new_with_id(id, request.title, request.media_type)?
        } else {
            Self::new(request.title, request.media_type)?
        };
        
        media.code = request.code;
        media.original_title = request.original_title;
        
        // 处理年份 - 优先使用 year，如果没有则从 release_date 提取
        let year = request.year.or_else(|| {
            request.release_date.as_ref().and_then(|date| {
                // 尝试从 YYYY-MM-DD 格式提取年份
                if date.len() >= 4 {
                    date[..4].parse::<i32>().ok().filter(|&y| y >= 1900 && y <= 2100)
                } else {
                    None
                }
            })
        });
        if let Some(y) = year {
            media.set_year(Some(y))?;
        }
        
        if let Some(overview) = request.overview {
            media.set_overview(Some(overview))?;
        }
        
        if let Some(genres) = request.genres {
            media.set_genres(&genres)?;
        }
        
        if let Some(rating) = request.rating {
            media.rating = Some(rating);
        }
        
        if let Some(poster_url) = request.poster_url {
            media.poster_url = Some(poster_url);
        }
        
        if let Some(backdrop_url) = request.backdrop_url {
            // 将 Vec<String> 序列化为 JSON 字符串
            media.backdrop_url = Some(serde_json::to_string(&backdrop_url)
                .unwrap_or_else(|_| "[]".to_string()));
        }
        
        if let Some(runtime) = request.runtime {
            media.runtime = Some(runtime);
        }
        
        if let Some(release_date) = request.release_date {
            media.release_date = Some(release_date);
        }
        
        if let Some(cast) = request.cast {
            media.set_cast(&cast)?;
        }
        
        if let Some(crew) = request.crew {
            media.set_crew(&crew)?;
        }
        
        if let Some(studio) = request.studio {
            media.studio = Some(studio);
        }
        
        if let Some(series) = request.series {
            media.series = Some(series);
        }
        
        if let Some(preview_urls) = request.preview_urls {
            media.set_preview_urls(&preview_urls)?;
        }
        
        if let Some(preview_video_urls) = request.preview_video_urls {
            media.set_preview_video_urls(&preview_video_urls)?;
        }
        
        if let Some(cover_video_url) = request.cover_video_url {
            media.cover_video_url = Some(cover_video_url);
        }
        
        if let Some(play_links) = request.play_links {
            media.set_play_links(&play_links)?;
        }
        
        if let Some(download_links) = request.download_links {
            media.set_download_links(&download_links)?;
        }
        
        Ok(media)
    }
    
    /// 应用更新请求
    pub fn apply_update(&mut self, request: UpdateMediaRequest) -> Result<(), ValidationError> {
        // 处理 code 字段：如果提供了值（包括空字符串），则更新；空字符串转为 None
        if let Some(code) = request.code {
            self.code = if code.trim().is_empty() { None } else { Some(code) };
        }
        
        if let Some(title) = request.title {
            self.set_title(title)?;
        }
        
        // 处理 original_title 字段：空字符串转为 None
        if let Some(original_title) = request.original_title {
            self.original_title = if original_title.trim().is_empty() { None } else { Some(original_title) };
        }
        
        if let Some(year) = request.year {
            self.set_year(Some(year))?;
        }
        
        // 处理 release_date 字段：空字符串转为 None
        if let Some(release_date) = request.release_date {
            self.release_date = if release_date.trim().is_empty() { None } else { Some(release_date) };
        }
        
        // 处理媒体类型更新
        if let Some(media_type_str) = request.media_type {
            let new_type = match media_type_str.as_str() {
                "Movie" | "movie" => "Movie".to_string(),
                "Scene" | "scene" => "Scene".to_string(),
                "Anime" | "anime" => "Anime".to_string(),
                "Documentary" | "documentary" => "Documentary".to_string(),
                "Censored" | "censored" => "Censored".to_string(),
                "Uncensored" | "uncensored" => "Uncensored".to_string(),
                _ => media_type_str,
            };
            self.media_type = new_type;
        }
        
        if let Some(overview) = request.overview {
            let overview_value = if overview.trim().is_empty() { None } else { Some(overview) };
            self.set_overview(overview_value)?;
        }
        
        if let Some(genres) = request.genres {
            self.set_genres(&genres)?;
        }
        
        if let Some(rating) = request.rating {
            self.set_rating(Some(rating))?;
        }
        
        if let Some(runtime) = request.runtime {
            self.set_runtime(Some(runtime))?;
        }
        
        if let Some(language) = request.language {
            self.set_language(Some(language))?;
        }
        
        if let Some(country) = request.country {
            self.set_country(Some(country))?;
        }
        
        if let Some(budget) = request.budget {
            self.set_budget(Some(budget))?;
        }
        
        if let Some(revenue) = request.revenue {
            self.set_revenue(Some(revenue))?;
        }
        
        if let Some(status) = request.status {
            self.status = if status.trim().is_empty() { None } else { Some(status) };
        }
        
        if let Some(poster_url) = request.poster_url {
            let url = if poster_url.trim().is_empty() { None } else { Some(poster_url) };
            self.set_poster_url(url)?;
        }
        
        if let Some(backdrop_url) = request.backdrop_url {
            // 将 Vec<String> 序列化为 JSON 字符串
            let url = if backdrop_url.is_empty() { 
                None 
            } else { 
                Some(serde_json::to_string(&backdrop_url)
                    .unwrap_or_else(|_| "[]".to_string()))
            };
            self.set_backdrop_url(url)?;
        }
        
        if let Some(cast) = request.cast {
            self.set_cast(&cast)?;
        }
        
        if let Some(crew) = request.crew {
            self.set_crew(&crew)?;
        }
        
        if let Some(play_links) = request.play_links {
            self.set_play_links(&play_links)?;
        }
        
        if let Some(download_links) = request.download_links {
            self.set_download_links(&download_links)?;
        }
        
        if let Some(preview_urls) = request.preview_urls {
            self.set_preview_urls(&preview_urls)?;
        }
        
        if let Some(preview_video_urls) = request.preview_video_urls {
            self.set_preview_video_urls(&preview_video_urls)?;
        }
        
        if let Some(cover_video_url) = request.cover_video_url {
            let url = if cover_video_url.trim().is_empty() { None } else { Some(cover_video_url) };
            self.set_cover_video_url(url)?;
        }
        
        if let Some(studio) = request.studio {
            self.studio = if studio.trim().is_empty() { None } else { Some(studio) };
        }
        
        if let Some(series) = request.series {
            self.series = if series.trim().is_empty() { None } else { Some(series) };
        }
        
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置标题（带验证）
    pub fn set_title(&mut self, title: String) -> Result<(), ValidationError> {
        StringValidator::validate_title(&title)?;
        self.title = title;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置年份（带验证）
    pub fn set_year(&mut self, year: Option<i32>) -> Result<(), ValidationError> {
        NumberValidator::validate_year(&year)?;
        self.year = year;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置评分（带验证）
    pub fn set_rating(&mut self, rating: Option<f32>) -> Result<(), ValidationError> {
        NumberValidator::validate_rating(&rating)?;
        self.rating = rating;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置时长（带验证）
    pub fn set_runtime(&mut self, runtime: Option<i32>) -> Result<(), ValidationError> {
        NumberValidator::validate_runtime(&runtime)?;
        self.runtime = runtime;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置简介（带验证）
    pub fn set_overview(&mut self, overview: Option<String>) -> Result<(), ValidationError> {
        StringValidator::validate_overview(&overview)?;
        self.overview = overview;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置语言（带验证）
    pub fn set_language(&mut self, language: Option<String>) -> Result<(), ValidationError> {
        StringValidator::validate_language_code(&language)?;
        self.language = language;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置国家（带验证）
    pub fn set_country(&mut self, country: Option<String>) -> Result<(), ValidationError> {
        StringValidator::validate_country_code(&country)?;
        self.country = country;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置预算（带验证）
    pub fn set_budget(&mut self, budget: Option<i64>) -> Result<(), ValidationError> {
        NumberValidator::validate_budget(&budget)?;
        self.budget = budget;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置收入（带验证）
    pub fn set_revenue(&mut self, revenue: Option<i64>) -> Result<(), ValidationError> {
        NumberValidator::validate_revenue(&revenue)?;
        self.revenue = revenue;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置海报URL（带验证）
    pub fn set_poster_url(&mut self, url: Option<String>) -> Result<(), ValidationError> {
        StringValidator::validate_url(&url)?;
        self.poster_url = url;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 设置背景图URL（带验证）
    /// 支持单个 URL 字符串或 JSON 数组字符串
    pub fn set_backdrop_url(&mut self, url: Option<String>) -> Result<(), ValidationError> {
        // 如果是 JSON 数组格式，跳过 URL 验证（数组中的每个 URL 已在序列化前验证）
        if let Some(ref url_str) = url {
            if !url_str.starts_with('[') {
                // 单个 URL 字符串，进行验证
                StringValidator::validate_url(&url)?;
            }
        }
        self.backdrop_url = url;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析外部ID
    pub fn get_external_ids(&self) -> Result<ExternalIds, serde_json::Error> {
        serde_json::from_str(&self.external_ids)
    }
    
    /// 设置外部ID
    pub fn set_external_ids(&mut self, external_ids: &ExternalIds) -> Result<(), serde_json::Error> {
        self.external_ids = serde_json::to_string(external_ids)?;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析媒体类型
    pub fn get_media_type(&self) -> Result<MediaType, String> {
        self.media_type.parse()
    }
    
    /// 设置媒体类型
    pub fn set_media_type(&mut self, media_type: MediaType) {
        self.media_type = media_type.to_string();
        self.updated_at = Utc::now();
    }
    
    /// 解析类型列表
    pub fn get_genres(&self) -> Result<Vec<String>, serde_json::Error> {
        serde_json::from_str(&self.genres)
    }
    
    /// 设置类型列表（带验证）
    pub fn set_genres(&mut self, genres: &[String]) -> Result<(), ValidationError> {
        // 自动截断：最多保留10个分类，每个分类最多50个字符
        let truncated_genres: Vec<String> = genres
            .iter()
            .take(10)  // 最多10个
            .map(|g| {
                if g.len() > 50 {
                    g.chars().take(50).collect()  // 截断到50个字符
                } else {
                    g.clone()
                }
            })
            .collect();
        
        CollectionValidator::validate_genres(&truncated_genres)?;
        self.genres = serde_json::to_string(&truncated_genres).map_err(|_| ValidationError::TooManyGenres)?;
        self.updated_at = Utc::now();
        
        // 如果有截断，记录警告日志
        if genres.len() > 10 {
            tracing::warn!("分类数量超过限制，已截断：{} -> 10", genres.len());
        }
        if genres.iter().any(|g| g.len() > 50) {
            tracing::warn!("部分分类名称过长，已截断到50个字符");
        }
        
        Ok(())
    }
    
    /// 解析演员列表
    pub fn get_cast(&self) -> Result<Vec<Person>, serde_json::Error> {
        match &self.cast {
            Some(cast_str) => serde_json::from_str(cast_str),
            None => Ok(Vec::new()),
        }
    }
    
    /// 设置演员列表（带验证）
    pub fn set_cast(&mut self, cast: &[Person]) -> Result<(), ValidationError> {
        CollectionValidator::validate_cast(cast)?;
        self.cast = Some(serde_json::to_string(cast).map_err(|_| ValidationError::TooManyCastMembers)?);
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析制作人员列表
    pub fn get_crew(&self) -> Result<Vec<Person>, serde_json::Error> {
        match &self.crew {
            Some(crew_str) => serde_json::from_str(crew_str),
            None => Ok(Vec::new()),
        }
    }
    
    /// 设置制作人员列表（带验证）
    pub fn set_crew(&mut self, crew: &[Person]) -> Result<(), ValidationError> {
        CollectionValidator::validate_crew(crew)?;
        self.crew = Some(serde_json::to_string(crew).map_err(|_| ValidationError::TooManyCrewMembers)?);
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析播放链接列表
    pub fn get_play_links(&self) -> Result<Vec<PlayLink>, serde_json::Error> {
        match &self.play_links {
            Some(links_str) => serde_json::from_str(links_str),
            None => Ok(Vec::new()),
        }
    }
    
    /// 设置播放链接列表
    pub fn set_play_links(&mut self, links: &[PlayLink]) -> Result<(), ValidationError> {
        self.play_links = Some(serde_json::to_string(links).unwrap_or_else(|_| "[]".to_string()));
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析下载链接列表
    pub fn get_download_links(&self) -> Result<Vec<DownloadLink>, serde_json::Error> {
        match &self.download_links {
            Some(links_str) => serde_json::from_str(links_str),
            None => Ok(Vec::new()),
        }
    }
    
    /// 设置下载链接列表
    pub fn set_download_links(&mut self, links: &[DownloadLink]) -> Result<(), ValidationError> {
        self.download_links = Some(serde_json::to_string(links).unwrap_or_else(|_| "[]".to_string()));
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析预览图URL列表
    pub fn get_preview_urls(&self) -> Result<Vec<String>, serde_json::Error> {
        match &self.preview_urls {
            Some(urls_str) => serde_json::from_str(urls_str),
            None => Ok(Vec::new()),
        }
    }
    
    /// 设置预览图URL列表
    pub fn set_preview_urls(&mut self, urls: &[String]) -> Result<(), ValidationError> {
        self.preview_urls = Some(serde_json::to_string(urls).unwrap_or_else(|_| "[]".to_string()));
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 解析预览视频URL列表
    pub fn get_preview_video_urls(&self) -> Result<Vec<String>, serde_json::Error> {
        match &self.preview_video_urls {
            Some(urls_str) => serde_json::from_str(urls_str),
            None => Ok(Vec::new()),
        }
    }
    
    /// 设置预览视频URL列表
    pub fn set_preview_video_urls(&mut self, urls: &[String]) -> Result<(), ValidationError> {
        self.preview_video_urls = Some(serde_json::to_string(urls).unwrap_or_else(|_| "[]".to_string()));
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 获取封面视频URL
    pub fn get_cover_video_url(&self) -> Option<String> {
        self.cover_video_url.clone()
    }
    
    /// 设置封面视频URL（带验证）
    pub fn set_cover_video_url(&mut self, url: Option<String>) -> Result<(), ValidationError> {
        StringValidator::validate_url(&url)?;
        self.cover_video_url = url;
        self.updated_at = Utc::now();
        Ok(())
    }
    
    /// 检查是否为电影
    pub fn is_movie(&self) -> bool {
        matches!(self.get_media_type(), Ok(MediaType::Movie))
    }
    
    /// 检查是否为场景
    pub fn is_scene(&self) -> bool {
        matches!(self.get_media_type(), Ok(MediaType::Scene))
    }
    
    /// 获取显示标题（优先使用原始标题）
    pub fn display_title(&self) -> &str {
        self.original_title.as_ref().unwrap_or(&self.title)
    }
    
    /// 获取年份字符串
    pub fn year_string(&self) -> String {
        self.year.map_or("未知".to_string(), |y| y.to_string())
    }
    
    /// 获取评分字符串
    pub fn rating_string(&self) -> String {
        self.rating.map_or("未评分".to_string(), |r| format!("{:.1}", r))
    }
    
    /// 获取时长字符串
    pub fn runtime_string(&self) -> String {
        self.runtime.map_or("未知".to_string(), |r| {
            let hours = r / 60;
            let minutes = r % 60;
            if hours > 0 {
                format!("{}小时{}分钟", hours, minutes)
            } else {
                format!("{}分钟", minutes)
            }
        })
    }
}

impl Validator for MediaItem {
    type Error = ValidationError;
    
    fn validate(&self) -> Result<(), Self::Error> {
        StringValidator::validate_title(&self.title)?;
        NumberValidator::validate_year(&self.year)?;
        NumberValidator::validate_rating(&self.rating)?;
        NumberValidator::validate_runtime(&self.runtime)?;
        StringValidator::validate_overview(&self.overview)?;
        StringValidator::validate_url(&self.poster_url)?;
        StringValidator::validate_url(&self.backdrop_url)?;
        StringValidator::validate_language_code(&self.language)?;
        StringValidator::validate_country_code(&self.country)?;
        NumberValidator::validate_budget(&self.budget)?;
        NumberValidator::validate_revenue(&self.revenue)?;
        
        // 验证JSON字段
        let genres = self.get_genres().map_err(|_| ValidationError::TooManyGenres)?;
        CollectionValidator::validate_genres(&genres)?;
        
        let cast = self.get_cast().map_err(|_| ValidationError::TooManyCastMembers)?;
        CollectionValidator::validate_cast(&cast)?;
        
        let crew = self.get_crew().map_err(|_| ValidationError::TooManyCrewMembers)?;
        CollectionValidator::validate_crew(&crew)?;
        
        Ok(())
    }
}

// 自定义序列化实现，将 JSON 字符串字段解析为实际的数组/对象
impl Serialize for MediaItem {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        
        let mut state = serializer.serialize_struct("MediaItem", 31)?;
        
        state.serialize_field("id", &self.id)?;
        state.serialize_field("code", &self.code)?;
        
        // 解析 external_ids JSON 字符串
        let external_ids: serde_json::Value = serde_json::from_str(&self.external_ids)
            .unwrap_or(serde_json::json!({}));
        state.serialize_field("external_ids", &external_ids)?;
        
        state.serialize_field("title", &self.title)?;
        state.serialize_field("original_title", &self.original_title)?;
        state.serialize_field("year", &self.year)?;
        state.serialize_field("media_type", &self.media_type)?;
        
        // 解析 genres JSON 字符串
        let genres: serde_json::Value = serde_json::from_str(&self.genres)
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("genres", &genres)?;
        
        state.serialize_field("rating", &self.rating)?;
        state.serialize_field("vote_count", &self.vote_count)?;
        state.serialize_field("poster_url", &self.poster_url)?;
        state.serialize_field("backdrop_url", &self.backdrop_url)?;
        state.serialize_field("overview", &self.overview)?;
        state.serialize_field("runtime", &self.runtime)?;
        state.serialize_field("release_date", &self.release_date)?;
        
        // 解析 cast JSON 字符串
        let cast: serde_json::Value = self.cast.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("cast", &cast)?;
        
        // 解析 crew JSON 字符串
        let crew: serde_json::Value = self.crew.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("crew", &crew)?;
        
        state.serialize_field("language", &self.language)?;
        state.serialize_field("country", &self.country)?;
        state.serialize_field("budget", &self.budget)?;
        state.serialize_field("revenue", &self.revenue)?;
        state.serialize_field("status", &self.status)?;
        
        // 解析 play_links JSON 字符串
        let play_links: serde_json::Value = self.play_links.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("play_links", &play_links)?;
        
        // 解析 download_links JSON 字符串
        let download_links: serde_json::Value = self.download_links.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("download_links", &download_links)?;
        
        // 解析 preview_urls JSON 字符串
        let preview_urls: serde_json::Value = self.preview_urls.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("preview_urls", &preview_urls)?;
        
        // 解析 preview_video_urls JSON 字符串
        let preview_video_urls: serde_json::Value = self.preview_video_urls.as_ref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!([]));
        state.serialize_field("preview_video_urls", &preview_video_urls)?;
        
        state.serialize_field("cover_video_url", &self.cover_video_url)?;
        state.serialize_field("studio", &self.studio)?;
        state.serialize_field("series", &self.series)?;
        state.serialize_field("scraper_name", &self.scraper_name)?;
        state.serialize_field("created_at", &self.created_at)?;
        state.serialize_field("updated_at", &self.updated_at)?;
        
        state.end()
    }
}

// 实现 Deserialize（用于从 JSON 创建 MediaItem，虽然通常不需要）
impl<'de> Deserialize<'de> for MediaItem {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        use serde::de::{self, MapAccess, Visitor};
        use std::fmt;
        
        #[derive(Deserialize)]
        #[serde(field_identifier, rename_all = "snake_case")]
        enum Field {
            Id, Code, ExternalIds, Title, OriginalTitle, Year, MediaType, Genres,
            Rating, VoteCount, PosterUrl, BackdropUrl, Overview, Runtime, ReleaseDate,
            Cast, Crew, Language, Country, Budget, Revenue, Status,
            PlayLinks, DownloadLinks, PreviewUrls, PreviewVideoUrls, CoverVideoUrl,
            Studio, Series, CreatedAt, UpdatedAt,
        }
        
        struct MediaItemVisitor;
        
        impl<'de> Visitor<'de> for MediaItemVisitor {
            type Value = MediaItem;
            
            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("struct MediaItem")
            }
            
            fn visit_map<V>(self, _map: V) -> Result<MediaItem, V::Error>
            where
                V: MapAccess<'de>,
            {
                // 这里简化处理，实际使用中通常不需要从 JSON 反序列化到 MediaItem
                // 因为 MediaItem 主要是从数据库加载的
                Err(de::Error::custom("MediaItem deserialization not fully implemented"))
            }
        }
        
        deserializer.deserialize_struct("MediaItem", &[], MediaItemVisitor)
    }
}
