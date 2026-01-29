// 缓存路径管理
//
// 提供统一的缓存文件路径生成和管理功能

use std::path::{Path, PathBuf};

/// 缓存路径生成器
///
/// 提供统一的路径生成规则，确保路径一致性
pub struct CachePath;

impl CachePath {
    /// 缓存根目录
    const CACHE_ROOT: &'static str = "cache";

    /// 图片缓存目录
    const IMAGES_DIR: &'static str = "images";

    /// 视频缓存目录
    const VIDEOS_DIR: &'static str = "videos";

    /// 媒体子目录
    const MEDIA_DIR: &'static str = "media";

    /// 生成图片缓存路径
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    /// - `field_name`: 字段名称（如 "poster", "backdrop"）
    /// - `index`: 可选的索引（用于多个同类型图片，如多个 backdrop）
    ///
    /// # 返回
    /// 本地文件路径，格式：
    /// - 单个图片: `cache/images/media/{media_id}/poster.webp`
    /// - 多个图片: `cache/images/media/{media_id}/backdrop_0.webp`
    ///
    /// # 示例
    /// ```
    /// use media_manager_backend::services::cache::CachePath;
    ///
    /// let path = CachePath::image_path("abc-123", "poster", None);
    /// assert_eq!(path.to_str().unwrap(), "cache/images/media/abc-123/poster.webp");
    ///
    /// let path = CachePath::image_path("abc-123", "backdrop", Some(0));
    /// assert_eq!(path.to_str().unwrap(), "cache/images/media/abc-123/backdrop_0.webp");
    /// ```
    pub fn image_path(media_id: &str, field_name: &str, index: Option<usize>) -> PathBuf {
        let filename = if let Some(idx) = index {
            format!("{}_{}.webp", field_name, idx)
        } else {
            format!("{}.webp", field_name)
        };

        PathBuf::from(Self::CACHE_ROOT)
            .join(Self::IMAGES_DIR)
            .join(Self::MEDIA_DIR)
            .join(media_id)
            .join(filename)
    }

    /// 生成视频缓存路径
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    /// - `field_name`: 字段名称（如 "preview_video", "cover_video"）
    ///
    /// # 返回
    /// 本地文件路径，格式：`cache/videos/media/{media_id}/preview_video.mp4`
    ///
    /// # 示例
    /// ```
    /// use media_manager_backend::services::cache::CachePath;
    ///
    /// let path = CachePath::video_path("abc-123", "preview_video");
    /// assert_eq!(path.to_str().unwrap(), "cache/videos/media/abc-123/preview_video.mp4");
    /// ```
    pub fn video_path(media_id: &str, field_name: &str) -> PathBuf {
        PathBuf::from(Self::CACHE_ROOT)
            .join(Self::VIDEOS_DIR)
            .join(Self::MEDIA_DIR)
            .join(media_id)
            .join(format!("{}.mp4", field_name))
    }

    /// 生成媒体缓存目录路径
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    /// - `is_video`: 是否为视频缓存
    ///
    /// # 返回
    /// 媒体缓存目录路径
    pub fn media_cache_dir(media_id: &str, is_video: bool) -> PathBuf {
        let subdir = if is_video {
            Self::VIDEOS_DIR
        } else {
            Self::IMAGES_DIR
        };

        PathBuf::from(Self::CACHE_ROOT)
            .join(subdir)
            .join(Self::MEDIA_DIR)
            .join(media_id)
    }

    /// 将本地路径转换为 API 路径
    ///
    /// # 参数
    /// - `local_path`: 本地文件路径
    ///
    /// # 返回
    /// API 路径字符串，格式：`/cache/images/media/{media_id}/poster.webp`
    ///
    /// # 示例
    /// ```
    /// use std::path::Path;
    /// use media_manager_backend::services::cache::CachePath;
    ///
    /// let local_path = Path::new("cache/images/media/abc-123/poster.webp");
    /// let api_path = CachePath::to_api_path(local_path);
    /// assert_eq!(api_path, "/cache/images/media/abc-123/poster.webp");
    /// ```
    pub fn to_api_path(local_path: &Path) -> String {
        format!("/{}", local_path.display())
    }

    /// 从 API 路径转换为本地路径
    ///
    /// # 参数
    /// - `api_path`: API 路径字符串
    ///
    /// # 返回
    /// 本地文件路径
    pub fn from_api_path(api_path: &str) -> PathBuf {
        PathBuf::from(api_path.trim_start_matches('/'))
    }

    /// 获取缓存根目录
    pub fn cache_root() -> PathBuf {
        PathBuf::from(Self::CACHE_ROOT)
    }

    /// 获取图片缓存根目录
    pub fn images_root() -> PathBuf {
        PathBuf::from(Self::CACHE_ROOT).join(Self::IMAGES_DIR)
    }

    /// 获取视频缓存根目录
    pub fn videos_root() -> PathBuf {
        PathBuf::from(Self::CACHE_ROOT).join(Self::VIDEOS_DIR)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_image_path_without_index() {
        let path = CachePath::image_path("abc-123", "poster", None);
        // 验证路径组件而不是字符串表示（跨平台兼容）
        assert_eq!(path.file_name().unwrap(), "poster.webp");
        assert!(path.to_string_lossy().contains("abc-123"));
        assert!(path.to_string_lossy().contains("cache"));
        assert!(path.to_string_lossy().contains("images"));
        assert!(path.to_string_lossy().contains("media"));
    }

    #[test]
    fn test_image_path_with_index() {
        let path = CachePath::image_path("abc-123", "backdrop", Some(0));
        assert_eq!(path.file_name().unwrap(), "backdrop_0.webp");
        assert!(path.to_string_lossy().contains("abc-123"));

        let path = CachePath::image_path("abc-123", "backdrop", Some(5));
        assert_eq!(path.file_name().unwrap(), "backdrop_5.webp");
        assert!(path.to_string_lossy().contains("abc-123"));
    }

    #[test]
    fn test_video_path() {
        let path = CachePath::video_path("abc-123", "preview_video");
        assert_eq!(path.file_name().unwrap(), "preview_video.mp4");
        assert!(path.to_string_lossy().contains("abc-123"));
        assert!(path.to_string_lossy().contains("cache"));
        assert!(path.to_string_lossy().contains("videos"));
    }

    #[test]
    fn test_media_cache_dir() {
        let path = CachePath::media_cache_dir("abc-123", false);
        assert!(path.to_string_lossy().contains("abc-123"));
        assert!(path.to_string_lossy().contains("images"));
        assert!(path.to_string_lossy().ends_with("abc-123"));

        let path = CachePath::media_cache_dir("abc-123", true);
        assert!(path.to_string_lossy().contains("abc-123"));
        assert!(path.to_string_lossy().contains("videos"));
        assert!(path.to_string_lossy().ends_with("abc-123"));
    }

    #[test]
    fn test_to_api_path() {
        let local_path = Path::new("cache/images/media/abc-123/poster.webp");
        let api_path = CachePath::to_api_path(local_path);
        assert_eq!(api_path, "/cache/images/media/abc-123/poster.webp");
    }

    #[test]
    fn test_from_api_path() {
        let api_path = "/cache/images/media/abc-123/poster.webp";
        let local_path = CachePath::from_api_path(api_path);
        // 验证路径组件
        assert_eq!(local_path.file_name().unwrap(), "poster.webp");
        assert!(local_path.to_string_lossy().contains("abc-123"));
    }

    #[test]
    fn test_cache_roots() {
        let cache_root = CachePath::cache_root();
        assert_eq!(cache_root.file_name().unwrap(), "cache");
        
        let images_root = CachePath::images_root();
        assert!(images_root.to_string_lossy().contains("cache"));
        assert!(images_root.to_string_lossy().ends_with("images"));
        
        let videos_root = CachePath::videos_root();
        assert!(videos_root.to_string_lossy().contains("cache"));
        assert!(videos_root.to_string_lossy().ends_with("videos"));
    }

    #[test]
    fn test_path_consistency() {
        // 测试相同输入生成相同路径
        let path1 = CachePath::image_path("test-id", "poster", None);
        let path2 = CachePath::image_path("test-id", "poster", None);
        assert_eq!(path1, path2);

        // 测试不同媒体 ID 生成不同路径
        let path1 = CachePath::image_path("id-1", "poster", None);
        let path2 = CachePath::image_path("id-2", "poster", None);
        assert_ne!(path1, path2);
    }
}
