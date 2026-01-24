use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

use super::validation::{Validator, ValidationError, StringValidator, NumberValidator};

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Collection {
    pub id: String,
    pub media_id: String,
    pub user_tags: String, // JSON array as string
    pub personal_rating: Option<f32>,
    pub watch_status: String,
    pub watch_progress: Option<f32>,
    pub notes: Option<String>,
    pub is_favorite: bool,
    pub added_at: DateTime<Utc>,
    pub last_watched: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum WatchStatus {
    WantToWatch,
    Watching,
    Completed,
    OnHold,
    Dropped,
}

impl std::fmt::Display for WatchStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WatchStatus::WantToWatch => write!(f, "WantToWatch"),
            WatchStatus::Watching => write!(f, "Watching"),
            WatchStatus::Completed => write!(f, "Completed"),
            WatchStatus::OnHold => write!(f, "OnHold"),
            WatchStatus::Dropped => write!(f, "Dropped"),
        }
    }
}

impl std::str::FromStr for WatchStatus {
    type Err = String;
    
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "WantToWatch" => Ok(WatchStatus::WantToWatch),
            "Watching" => Ok(WatchStatus::Watching),
            "Completed" => Ok(WatchStatus::Completed),
            "OnHold" => Ok(WatchStatus::OnHold),
            "Dropped" => Ok(WatchStatus::Dropped),
            _ => Err(format!("Invalid watch status: {}", s)),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AddToCollectionRequest {
    pub media_id: String,
    pub user_tags: Option<Vec<String>>,
    pub personal_rating: Option<f32>,
    pub watch_status: Option<WatchStatus>,
    pub notes: Option<String>,
    pub is_favorite: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateCollectionRequest {
    pub user_tags: Option<Vec<String>>,
    pub personal_rating: Option<f32>,
    pub watch_status: Option<WatchStatus>,
    pub watch_progress: Option<f32>,
    pub notes: Option<String>,
    pub is_favorite: Option<bool>,
}

impl Collection {
    /// 创建新的收藏项目
    pub fn new(media_id: String, watch_status: WatchStatus) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            media_id,
            user_tags: "[]".to_string(),
            personal_rating: None,
            watch_status: watch_status.to_string(),
            watch_progress: None,
            notes: None,
            is_favorite: false,
            added_at: now,
            last_watched: None,
            completed_at: None,
        }
    }
    
    /// 从添加请求创建收藏
    pub fn from_add_request(request: AddToCollectionRequest) -> Result<Self, ValidationError> {
        let watch_status = request.watch_status.unwrap_or(WatchStatus::WantToWatch);
        let mut collection = Self::new(request.media_id, watch_status);
        
        if let Some(tags) = request.user_tags {
            collection.set_user_tags(&tags)?;
        }
        
        if let Some(rating) = request.personal_rating {
            collection.set_personal_rating(Some(rating))?;
        }
        
        if let Some(notes) = request.notes {
            collection.set_notes(Some(notes))?;
        }
        
        if let Some(is_favorite) = request.is_favorite {
            collection.is_favorite = is_favorite;
        }
        
        Ok(collection)
    }
    
    /// 应用更新请求
    pub fn apply_update(&mut self, request: UpdateCollectionRequest) -> Result<(), ValidationError> {
        if let Some(tags) = request.user_tags {
            self.set_user_tags(&tags)?;
        }
        
        if let Some(rating) = request.personal_rating {
            self.set_personal_rating(Some(rating))?;
        }
        
        if let Some(status) = request.watch_status {
            self.set_watch_status(status);
        }
        
        if let Some(progress) = request.watch_progress {
            self.update_progress(progress)?;
        }
        
        if let Some(notes) = request.notes {
            self.set_notes(Some(notes))?;
        }
        
        if let Some(is_favorite) = request.is_favorite {
            self.is_favorite = is_favorite;
        }
        
        Ok(())
    }
    
    /// 解析用户标签
    pub fn get_user_tags(&self) -> Result<Vec<String>, serde_json::Error> {
        serde_json::from_str(&self.user_tags)
    }
    
    /// 设置用户标签（带验证）
    pub fn set_user_tags(&mut self, tags: &[String]) -> Result<(), ValidationError> {
        // 验证标签数量和长度
        if tags.len() > 20 {
            return Err(ValidationError::TooManyGenres); // 复用这个错误类型
        }
        
        for tag in tags {
            if tag.len() > 50 {
                return Err(ValidationError::GenreNameTooLong); // 复用这个错误类型
            }
        }
        
        self.user_tags = serde_json::to_string(tags)
            .map_err(|_| ValidationError::TooManyGenres)?;
        Ok(())
    }
    
    /// 添加用户标签
    pub fn add_user_tag(&mut self, tag: String) -> Result<(), ValidationError> {
        let mut tags = self.get_user_tags().unwrap_or_default();
        if !tags.contains(&tag) {
            tags.push(tag);
            self.set_user_tags(&tags)?;
        }
        Ok(())
    }
    
    /// 移除用户标签
    pub fn remove_user_tag(&mut self, tag: &str) -> Result<(), ValidationError> {
        let mut tags = self.get_user_tags().unwrap_or_default();
        tags.retain(|t| t != tag);
        self.set_user_tags(&tags)?;
        Ok(())
    }
    
    /// 获取观看状态枚举
    pub fn get_watch_status(&self) -> Result<WatchStatus, String> {
        self.watch_status.parse()
    }
    
    /// 设置观看状态
    pub fn set_watch_status(&mut self, status: WatchStatus) {
        self.watch_status = status.to_string();
        
        // 如果状态变为已完成，设置完成时间和进度
        if matches!(status, WatchStatus::Completed) {
            if self.completed_at.is_none() {
                self.completed_at = Some(Utc::now());
            }
            if self.watch_progress.map_or(true, |p| p < 1.0) {
                self.watch_progress = Some(1.0);
            }
        }
        
        // 如果状态从已完成变为其他状态，清除完成时间
        if !matches!(status, WatchStatus::Completed) {
            self.completed_at = None;
        }
    }
    
    /// 设置个人评分（带验证）
    pub fn set_personal_rating(&mut self, rating: Option<f32>) -> Result<(), ValidationError> {
        NumberValidator::validate_rating(&rating)?;
        self.personal_rating = rating;
        Ok(())
    }
    
    /// 设置笔记（带验证）
    pub fn set_notes(&mut self, notes: Option<String>) -> Result<(), ValidationError> {
        StringValidator::validate_notes(&notes)?;
        self.notes = notes;
        Ok(())
    }
    
    /// 更新观看进度（带验证）
    pub fn update_progress(&mut self, progress: f32) -> Result<(), ValidationError> {
        NumberValidator::validate_progress(&Some(progress))?;
        
        self.watch_progress = Some(progress.clamp(0.0, 1.0));
        self.last_watched = Some(Utc::now());
        
        // 如果进度达到100%，自动设置为已完成
        if progress >= 1.0 {
            self.set_watch_status(WatchStatus::Completed);
        } else if matches!(self.get_watch_status(), Ok(WatchStatus::WantToWatch)) {
            // 如果开始观看，自动设置为正在观看
            self.set_watch_status(WatchStatus::Watching);
        }
        
        Ok(())
    }
    
    /// 标记为收藏/取消收藏
    pub fn toggle_favorite(&mut self) {
        self.is_favorite = !self.is_favorite;
    }
    
    /// 获取观看进度百分比
    pub fn progress_percentage(&self) -> i32 {
        (self.watch_progress.unwrap_or(0.0) * 100.0) as i32
    }
    
    /// 获取观看状态显示文本
    pub fn status_display(&self) -> &str {
        match self.get_watch_status() {
            Ok(WatchStatus::WantToWatch) => "想看",
            Ok(WatchStatus::Watching) => "在看",
            Ok(WatchStatus::Completed) => "看过",
            Ok(WatchStatus::OnHold) => "暂停",
            Ok(WatchStatus::Dropped) => "弃坑",
            Err(_) => "未知",
        }
    }
    
    /// 获取评分显示文本
    pub fn rating_display(&self) -> String {
        self.personal_rating
            .map_or("未评分".to_string(), |r| format!("{:.1}分", r))
    }
    
    /// 检查是否已完成
    pub fn is_completed(&self) -> bool {
        matches!(self.get_watch_status(), Ok(WatchStatus::Completed))
    }
    
    /// 检查是否正在观看
    pub fn is_watching(&self) -> bool {
        matches!(self.get_watch_status(), Ok(WatchStatus::Watching))
    }
    
    /// 获取添加时间的友好显示
    pub fn added_time_display(&self) -> String {
        let now = Utc::now();
        let duration = now.signed_duration_since(self.added_at);
        
        if duration.num_days() > 0 {
            format!("{}天前", duration.num_days())
        } else if duration.num_hours() > 0 {
            format!("{}小时前", duration.num_hours())
        } else if duration.num_minutes() > 0 {
            format!("{}分钟前", duration.num_minutes())
        } else {
            "刚刚".to_string()
        }
    }
}

impl Validator for Collection {
    type Error = ValidationError;
    
    fn validate(&self) -> Result<(), Self::Error> {
        // 验证媒体ID不为空
        if self.media_id.trim().is_empty() {
            return Err(ValidationError::EmptyTitle); // 复用这个错误类型
        }
        
        // 验证个人评分
        NumberValidator::validate_rating(&self.personal_rating)?;
        
        // 验证观看进度
        NumberValidator::validate_progress(&self.watch_progress)?;
        
        // 验证笔记
        StringValidator::validate_notes(&self.notes)?;
        
        // 验证用户标签
        let tags = self.get_user_tags().map_err(|_| ValidationError::TooManyGenres)?;
        if tags.len() > 20 {
            return Err(ValidationError::TooManyGenres);
        }
        
        for tag in &tags {
            if tag.len() > 50 {
                return Err(ValidationError::GenreNameTooLong);
            }
        }
        
        // 验证观看状态
        self.get_watch_status().map_err(|_| ValidationError::EmptyTitle)?;
        
        Ok(())
    }
}