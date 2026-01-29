// 缓存模块 - 媒体图片缓存管理
//
// 本模块提供媒体图片的智能缓存功能，包括：
// - 临时 URL 检测
// - 自动开启缓存
// - 图片下载与 WebP 转换
// - 视频智能缓存
// - 缓存管理

pub mod cache_service;
pub mod config;
pub mod config_manager;
pub mod error;
pub mod image_downloader;
pub mod path;
pub mod url_detector;
pub mod video_selector;
pub mod webp_converter;

pub use cache_service::{CacheService, CacheStats, MediaData, ScraperCacheStats};
pub use config::{CacheConfig, CacheField, ScraperCacheConfig};
pub use config_manager::ConfigManager;
pub use error::{CacheError, ConversionError, DownloadError, FileSystemError};
pub use image_downloader::{DownloadTask, ImageDownloader};
pub use path::CachePath;
pub use url_detector::UrlDetector;
pub use video_selector::{PreviewVideoUrl, VideoQuality, VideoSelector};
pub use webp_converter::WebPConverter;
