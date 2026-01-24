use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

/// 媒体文件模型 - 用于存储多分段视频文件
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct MediaFile {
    pub id: String,
    pub media_id: String,
    pub file_path: String,
    pub file_size: i64,
    pub part_number: Option<i32>,
    pub part_label: Option<String>,
    pub created_at: DateTime<Utc>,
}

impl MediaFile {
    /// 创建新的媒体文件记录
    pub fn new(
        media_id: String,
        file_path: String,
        file_size: i64,
        part_number: Option<i32>,
        part_label: Option<String>,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            media_id,
            file_path,
            file_size,
            part_number,
            part_label,
            created_at: Utc::now(),
        }
    }

    /// 获取显示名称
    pub fn display_name(&self) -> String {
        if let Some(ref label) = self.part_label {
            label.clone()
        } else if let Some(num) = self.part_number {
            format!("Part {}", num)
        } else {
            // 从文件路径提取文件名
            std::path::Path::new(&self.file_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("Unknown")
                .to_string()
        }
    }

    /// 格式化文件大小
    pub fn formatted_size(&self) -> String {
        format_file_size(self.file_size)
    }
}

/// 格式化文件大小为人类可读格式
pub fn format_file_size(size: i64) -> String {
    const KB: i64 = 1024;
    const MB: i64 = KB * 1024;
    const GB: i64 = MB * 1024;
    const TB: i64 = GB * 1024;

    if size >= TB {
        format!("{:.2} TB", size as f64 / TB as f64)
    } else if size >= GB {
        format!("{:.2} GB", size as f64 / GB as f64)
    } else if size >= MB {
        format!("{:.2} MB", size as f64 / MB as f64)
    } else if size >= KB {
        format!("{:.2} KB", size as f64 / KB as f64)
    } else {
        format!("{} B", size)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_file_size() {
        assert_eq!(format_file_size(500), "500 B");
        assert_eq!(format_file_size(1024), "1.00 KB");
        assert_eq!(format_file_size(1024 * 1024), "1.00 MB");
        assert_eq!(format_file_size(1024 * 1024 * 1024), "1.00 GB");
        assert_eq!(format_file_size(1536 * 1024 * 1024), "1.50 GB");
    }

    #[test]
    fn test_display_name() {
        let file1 = MediaFile::new(
            "media-123".to_string(),
            "/path/to/movie_CD1.mp4".to_string(),
            1024 * 1024 * 1024,
            Some(1),
            Some("CD1".to_string()),
        );
        assert_eq!(file1.display_name(), "CD1");

        let file2 = MediaFile::new(
            "media-123".to_string(),
            "/path/to/movie_part2.mp4".to_string(),
            1024 * 1024 * 1024,
            Some(2),
            None,
        );
        assert_eq!(file2.display_name(), "Part 2");

        let file3 = MediaFile::new(
            "media-123".to_string(),
            "/path/to/movie.mp4".to_string(),
            1024 * 1024 * 1024,
            None,
            None,
        );
        assert_eq!(file3.display_name(), "movie.mp4");
    }
}
