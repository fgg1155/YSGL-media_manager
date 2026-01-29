// 缓存配置数据结构
//
// 定义了缓存配置的核心数据结构，包括：
// - 全局缓存配置
// - 单个刮削器配置
// - 可缓存的字段类型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 缓存配置（存储在 cache_config.json）
///
/// 包含全局缓存开关和各刮削器的独立配置
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CacheConfig {
    /// 全局缓存开关
    /// - true: 所有刮削器的图片都缓存
    /// - false: 根据单个刮削器的配置决定
    pub global_cache_enabled: bool,

    /// 各刮削器的缓存配置
    /// Key: 刮削器名称（如 "maturenl", "mindgeek"）
    /// Value: 该刮削器的缓存配置
    #[serde(default)]
    pub scrapers: HashMap<String, ScraperCacheConfig>,
}

/// 单个刮削器的缓存配置
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ScraperCacheConfig {
    /// 是否开启缓存
    pub cache_enabled: bool,

    /// 是否为自动开启
    /// - true: 系统检测到临时 URL 后自动开启
    /// - false: 用户手动开启
    #[serde(default)]
    pub auto_enabled: bool,

    /// 自动开启的时间戳
    /// 仅当 auto_enabled=true 时有值
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto_enabled_at: Option<DateTime<Utc>>,

    /// 需要缓存的字段列表
    /// 例如: ["poster", "backdrop", "preview"]
    #[serde(default)]
    pub cache_fields: Vec<CacheField>,
}

/// 可缓存的字段类型
///
/// 定义了哪些媒体字段可以被缓存
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum CacheField {
    /// 封面图
    Poster,

    /// 背景图
    Backdrop,

    /// 预览图
    Preview,

    /// 预览视频
    PreviewVideo,

    /// 封面视频
    CoverVideo,
}

impl Default for CacheConfig {
    /// 默认配置：全局缓存关闭，无刮削器配置
    fn default() -> Self {
        Self {
            global_cache_enabled: false,
            scrapers: HashMap::new(),
        }
    }
}

impl Default for ScraperCacheConfig {
    /// 默认刮削器配置：缓存关闭，非自动开启，缓存所有字段
    fn default() -> Self {
        Self {
            cache_enabled: false,
            auto_enabled: false,
            auto_enabled_at: None,
            cache_fields: vec![
                CacheField::Poster,
                CacheField::Backdrop,
                CacheField::Preview,
            ],
        }
    }
}

impl CacheField {
    /// 将字段类型转换为字符串名称
    pub fn as_str(&self) -> &str {
        match self {
            CacheField::Poster => "poster",
            CacheField::Backdrop => "backdrop",
            CacheField::Preview => "preview",
            CacheField::PreviewVideo => "preview_video",
            CacheField::CoverVideo => "cover_video",
        }
    }

    /// 从字符串解析字段类型
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "poster" => Some(CacheField::Poster),
            "backdrop" => Some(CacheField::Backdrop),
            "preview" => Some(CacheField::Preview),
            "preview_video" => Some(CacheField::PreviewVideo),
            "cover_video" => Some(CacheField::CoverVideo),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_cache_config() {
        let config = CacheConfig::default();
        assert!(!config.global_cache_enabled);
        assert!(config.scrapers.is_empty());
    }

    #[test]
    fn test_default_scraper_config() {
        let config = ScraperCacheConfig::default();
        assert!(!config.cache_enabled);
        assert!(!config.auto_enabled);
        assert!(config.auto_enabled_at.is_none());
        assert_eq!(config.cache_fields.len(), 3);
    }

    #[test]
    fn test_cache_field_as_str() {
        assert_eq!(CacheField::Poster.as_str(), "poster");
        assert_eq!(CacheField::Backdrop.as_str(), "backdrop");
        assert_eq!(CacheField::Preview.as_str(), "preview");
        assert_eq!(CacheField::PreviewVideo.as_str(), "preview_video");
        assert_eq!(CacheField::CoverVideo.as_str(), "cover_video");
    }

    #[test]
    fn test_cache_field_from_str() {
        assert_eq!(CacheField::from_str("poster"), Some(CacheField::Poster));
        assert_eq!(CacheField::from_str("backdrop"), Some(CacheField::Backdrop));
        assert_eq!(CacheField::from_str("preview"), Some(CacheField::Preview));
        assert_eq!(
            CacheField::from_str("preview_video"),
            Some(CacheField::PreviewVideo)
        );
        assert_eq!(
            CacheField::from_str("cover_video"),
            Some(CacheField::CoverVideo)
        );
        assert_eq!(CacheField::from_str("invalid"), None);
    }

    #[test]
    fn test_config_serialization() {
        let config = CacheConfig {
            global_cache_enabled: true,
            scrapers: HashMap::from([(
                "maturenl".to_string(),
                ScraperCacheConfig {
                    cache_enabled: true,
                    auto_enabled: true,
                    auto_enabled_at: Some(Utc::now()),
                    cache_fields: vec![CacheField::Poster, CacheField::Backdrop],
                },
            )]),
        };

        // 测试序列化
        let json = serde_json::to_string(&config).unwrap();
        assert!(json.contains("global_cache_enabled"));
        assert!(json.contains("maturenl"));

        // 测试反序列化
        let deserialized: CacheConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.global_cache_enabled, config.global_cache_enabled);
        assert_eq!(deserialized.scrapers.len(), 1);
    }
}
