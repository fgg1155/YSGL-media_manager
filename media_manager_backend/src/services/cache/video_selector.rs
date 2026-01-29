// 视频选择器 - 智能选择最高清晰度的视频
//
// 本模块提供视频清晰度解析和选择功能，用于：
// - 解析视频清晰度字符串（4K、1080P、720P 等）
// - 从多个视频 URL 中选择最高清晰度的版本
// - 支持预览视频的智能缓存策略

use serde::{Deserialize, Serialize};

/// 预览视频 URL（包含清晰度信息）
///
/// 用于存储视频 URL 及其对应的清晰度标识
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PreviewVideoUrl {
    /// 清晰度标识（如 "4K", "1080P", "720P", "480P", "trailer", "Unknown"）
    pub quality: String,
    
    /// 视频 URL
    pub url: String,
}

impl PreviewVideoUrl {
    /// 创建新的预览视频 URL
    pub fn new(quality: String, url: String) -> Self {
        Self { quality, url }
    }
}

/// 视频清晰度枚举
///
/// 定义了支持的视频清晰度级别，按优先级排序
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum VideoQuality {
    /// 未知清晰度（最低优先级）
    Unknown = 0,
    
    /// 预告片/片花（低优先级）
    Trailer = 1,
    
    /// 480P 标清
    P480 = 2,
    
    /// 720P 高清
    P720 = 3,
    
    /// 1080P 全高清
    P1080 = 4,
    
    /// 4K 超高清（最高优先级）
    FourK = 5,
}

impl VideoQuality {
    /// 从字符串解析清晰度
    ///
    /// 支持多种格式：
    /// - "4K", "4k", "2160P", "2160p"
    /// - "1080P", "1080p", "FHD", "fhd"
    /// - "720P", "720p", "HD", "hd"
    /// - "480P", "480p", "SD", "sd"
    /// - "trailer", "Trailer", "TRAILER"
    /// - 其他任何字符串 -> Unknown
    pub fn parse(quality_str: &str) -> Self {
        let normalized = quality_str.trim().to_lowercase();
        
        // 4K / 2160P
        if normalized.contains("4k") || normalized.contains("2160") {
            return VideoQuality::FourK;
        }
        
        // 1080P / FHD
        if normalized.contains("1080") || normalized == "fhd" {
            return VideoQuality::P1080;
        }
        
        // 720P / HD
        if normalized.contains("720") || normalized == "hd" {
            return VideoQuality::P720;
        }
        
        // 480P / SD
        if normalized.contains("480") || normalized == "sd" {
            return VideoQuality::P480;
        }
        
        // Trailer
        if normalized.contains("trailer") {
            return VideoQuality::Trailer;
        }
        
        // Unknown
        VideoQuality::Unknown
    }
    
    /// 转换为字符串表示
    pub fn as_str(&self) -> &'static str {
        match self {
            VideoQuality::FourK => "4K",
            VideoQuality::P1080 => "1080P",
            VideoQuality::P720 => "720P",
            VideoQuality::P480 => "480P",
            VideoQuality::Trailer => "trailer",
            VideoQuality::Unknown => "Unknown",
        }
    }
}

/// 视频选择器
///
/// 提供视频清晰度选择功能
#[derive(Clone, Copy)]
pub struct VideoSelector;

impl VideoSelector {
    /// 从多个视频 URL 中选择最高清晰度的版本
    ///
    /// # 参数
    /// - `urls`: 包含多个不同清晰度的视频 URL 列表
    ///
    /// # 返回
    /// - `Some(PreviewVideoUrl)`: 最高清晰度的视频 URL
    /// - `None`: 如果列表为空
    ///
    /// # 示例
    /// ```
    /// use media_manager_backend::services::cache::{VideoSelector, PreviewVideoUrl};
    ///
    /// let urls = vec![
    ///     PreviewVideoUrl::new("720P".to_string(), "https://example.com/720p.mp4".to_string()),
    ///     PreviewVideoUrl::new("1080P".to_string(), "https://example.com/1080p.mp4".to_string()),
    ///     PreviewVideoUrl::new("480P".to_string(), "https://example.com/480p.mp4".to_string()),
    /// ];
    ///
    /// let best = VideoSelector::select_best_quality(&urls);
    /// assert_eq!(best.unwrap().quality, "1080P");
    /// ```
    pub fn select_best_quality(urls: &[PreviewVideoUrl]) -> Option<PreviewVideoUrl> {
        if urls.is_empty() {
            return None;
        }
        
        // 找到最高清晰度的视频
        urls.iter()
            .max_by_key(|video| VideoQuality::parse(&video.quality))
            .cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_quality_parse_4k() {
        assert_eq!(VideoQuality::parse("4K"), VideoQuality::FourK);
        assert_eq!(VideoQuality::parse("4k"), VideoQuality::FourK);
        assert_eq!(VideoQuality::parse("2160P"), VideoQuality::FourK);
        assert_eq!(VideoQuality::parse("2160p"), VideoQuality::FourK);
    }

    #[test]
    fn test_video_quality_parse_1080p() {
        assert_eq!(VideoQuality::parse("1080P"), VideoQuality::P1080);
        assert_eq!(VideoQuality::parse("1080p"), VideoQuality::P1080);
        assert_eq!(VideoQuality::parse("FHD"), VideoQuality::P1080);
        assert_eq!(VideoQuality::parse("fhd"), VideoQuality::P1080);
    }

    #[test]
    fn test_video_quality_parse_720p() {
        assert_eq!(VideoQuality::parse("720P"), VideoQuality::P720);
        assert_eq!(VideoQuality::parse("720p"), VideoQuality::P720);
        assert_eq!(VideoQuality::parse("HD"), VideoQuality::P720);
        assert_eq!(VideoQuality::parse("hd"), VideoQuality::P720);
    }

    #[test]
    fn test_video_quality_parse_480p() {
        assert_eq!(VideoQuality::parse("480P"), VideoQuality::P480);
        assert_eq!(VideoQuality::parse("480p"), VideoQuality::P480);
        assert_eq!(VideoQuality::parse("SD"), VideoQuality::P480);
        assert_eq!(VideoQuality::parse("sd"), VideoQuality::P480);
    }

    #[test]
    fn test_video_quality_parse_trailer() {
        assert_eq!(VideoQuality::parse("trailer"), VideoQuality::Trailer);
        assert_eq!(VideoQuality::parse("Trailer"), VideoQuality::Trailer);
        assert_eq!(VideoQuality::parse("TRAILER"), VideoQuality::Trailer);
    }

    #[test]
    fn test_video_quality_parse_unknown() {
        assert_eq!(VideoQuality::parse(""), VideoQuality::Unknown);
        assert_eq!(VideoQuality::parse("unknown"), VideoQuality::Unknown);
        assert_eq!(VideoQuality::parse("xyz"), VideoQuality::Unknown);
    }

    #[test]
    fn test_video_quality_ordering() {
        // 测试清晰度优先级排序
        assert!(VideoQuality::FourK > VideoQuality::P1080);
        assert!(VideoQuality::P1080 > VideoQuality::P720);
        assert!(VideoQuality::P720 > VideoQuality::P480);
        assert!(VideoQuality::P480 > VideoQuality::Trailer);
        assert!(VideoQuality::Trailer > VideoQuality::Unknown);
    }

    #[test]
    fn test_video_quality_as_str() {
        assert_eq!(VideoQuality::FourK.as_str(), "4K");
        assert_eq!(VideoQuality::P1080.as_str(), "1080P");
        assert_eq!(VideoQuality::P720.as_str(), "720P");
        assert_eq!(VideoQuality::P480.as_str(), "480P");
        assert_eq!(VideoQuality::Trailer.as_str(), "trailer");
        assert_eq!(VideoQuality::Unknown.as_str(), "Unknown");
    }

    #[test]
    fn test_select_best_quality_empty() {
        let urls: Vec<PreviewVideoUrl> = vec![];
        assert_eq!(VideoSelector::select_best_quality(&urls), None);
    }

    #[test]
    fn test_select_best_quality_single() {
        let urls = vec![PreviewVideoUrl::new(
            "720P".to_string(),
            "https://example.com/720p.mp4".to_string(),
        )];
        
        let best = VideoSelector::select_best_quality(&urls);
        assert!(best.is_some());
        assert_eq!(best.unwrap().quality, "720P");
    }

    #[test]
    fn test_select_best_quality_multiple() {
        let urls = vec![
            PreviewVideoUrl::new("720P".to_string(), "https://example.com/720p.mp4".to_string()),
            PreviewVideoUrl::new("1080P".to_string(), "https://example.com/1080p.mp4".to_string()),
            PreviewVideoUrl::new("480P".to_string(), "https://example.com/480p.mp4".to_string()),
        ];
        
        let best = VideoSelector::select_best_quality(&urls);
        assert!(best.is_some());
        let best = best.unwrap();
        assert_eq!(best.quality, "1080P");
        assert_eq!(best.url, "https://example.com/1080p.mp4");
    }

    #[test]
    fn test_select_best_quality_with_4k() {
        let urls = vec![
            PreviewVideoUrl::new("720P".to_string(), "https://example.com/720p.mp4".to_string()),
            PreviewVideoUrl::new("4K".to_string(), "https://example.com/4k.mp4".to_string()),
            PreviewVideoUrl::new("1080P".to_string(), "https://example.com/1080p.mp4".to_string()),
        ];
        
        let best = VideoSelector::select_best_quality(&urls);
        assert!(best.is_some());
        let best = best.unwrap();
        assert_eq!(best.quality, "4K");
        assert_eq!(best.url, "https://example.com/4k.mp4");
    }

    #[test]
    fn test_select_best_quality_with_trailer() {
        let urls = vec![
            PreviewVideoUrl::new("trailer".to_string(), "https://example.com/trailer.mp4".to_string()),
            PreviewVideoUrl::new("480P".to_string(), "https://example.com/480p.mp4".to_string()),
        ];
        
        let best = VideoSelector::select_best_quality(&urls);
        assert!(best.is_some());
        let best = best.unwrap();
        assert_eq!(best.quality, "480P");
        assert_eq!(best.url, "https://example.com/480p.mp4");
    }

    #[test]
    fn test_select_best_quality_with_unknown() {
        let urls = vec![
            PreviewVideoUrl::new("unknown".to_string(), "https://example.com/unknown.mp4".to_string()),
            PreviewVideoUrl::new("720P".to_string(), "https://example.com/720p.mp4".to_string()),
        ];
        
        let best = VideoSelector::select_best_quality(&urls);
        assert!(best.is_some());
        let best = best.unwrap();
        assert_eq!(best.quality, "720P");
        assert_eq!(best.url, "https://example.com/720p.mp4");
    }

    #[test]
    fn test_select_best_quality_all_unknown() {
        let urls = vec![
            PreviewVideoUrl::new("unknown1".to_string(), "https://example.com/1.mp4".to_string()),
            PreviewVideoUrl::new("unknown2".to_string(), "https://example.com/2.mp4".to_string()),
        ];
        
        let best = VideoSelector::select_best_quality(&urls);
        assert!(best.is_some());
        // 当所有清晰度都是 Unknown 时，max_by_key 返回最后一个相同优先级的元素
        let best = best.unwrap();
        assert!(best.quality == "unknown1" || best.quality == "unknown2");
    }

    #[test]
    fn test_preview_video_url_creation() {
        let video = PreviewVideoUrl::new(
            "1080P".to_string(),
            "https://example.com/video.mp4".to_string(),
        );
        
        assert_eq!(video.quality, "1080P");
        assert_eq!(video.url, "https://example.com/video.mp4");
    }

    #[test]
    fn test_preview_video_url_serialization() {
        let video = PreviewVideoUrl::new(
            "1080P".to_string(),
            "https://example.com/video.mp4".to_string(),
        );
        
        // 测试序列化
        let json = serde_json::to_string(&video).unwrap();
        assert!(json.contains("1080P"));
        assert!(json.contains("https://example.com/video.mp4"));
        
        // 测试反序列化
        let deserialized: PreviewVideoUrl = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized, video);
    }
}
