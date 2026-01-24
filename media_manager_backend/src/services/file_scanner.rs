use std::path::Path;
use std::fs;
use regex::Regex;
use serde::{Deserialize, Serialize};

/// 支持的视频文件扩展名
const VIDEO_EXTENSIONS: &[&str] = &[
    "mp4", "mkv", "avi", "wmv", "flv", "mov", "m4v", "mpg", "mpeg", "webm", "ts", "m2ts"
];

/// 扫描的视频文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScannedFile {
    pub file_path: String,
    pub file_name: String,
    pub file_size: u64,
    pub parsed_code: Option<String>,
    pub parsed_title: Option<String>,
    pub parsed_year: Option<i32>,
}

/// 扫描结果
#[derive(Debug, Serialize, Deserialize)]
pub struct ScanResult {
    pub total_files: usize,
    pub scanned_files: Vec<ScannedFile>,
}

/// 文件扫描器
pub struct FileScanner {
    code_regex: Regex,
    year_regex: Regex,
}

impl FileScanner {
    pub fn new() -> Self {
        Self {
            // 匹配识别号格式: ABC-123, ABCD-1234, ABC123 等
            // 这些正则表达式是硬编码的，应该总是有效的
            code_regex: Regex::new(r"([A-Z]{2,6})-?(\d{3,5})")
                .expect("Invalid code regex pattern - this is a programming error"),
            // 匹配年份: 2020, 2021 等
            year_regex: Regex::new(r"\b(19\d{2}|20\d{2})\b")
                .expect("Invalid year regex pattern - this is a programming error"),
        }
    }

    /// 扫描指定目录
    pub fn scan_directory(&self, path: &str, recursive: bool) -> Result<ScanResult, String> {
        let path = Path::new(path);
        
        if !path.exists() {
            return Err(format!("路径不存在: {}", path.display()));
        }

        if !path.is_dir() {
            return Err(format!("不是有效的目录: {}", path.display()));
        }

        let mut scanned_files = Vec::new();
        self.scan_dir_recursive(path, recursive, &mut scanned_files)?;

        Ok(ScanResult {
            total_files: scanned_files.len(),
            scanned_files,
        })
    }

    /// 递归扫描目录
    fn scan_dir_recursive(
        &self,
        dir: &Path,
        recursive: bool,
        files: &mut Vec<ScannedFile>,
    ) -> Result<(), String> {
        let entries = fs::read_dir(dir)
            .map_err(|e| format!("无法读取目录 {}: {}", dir.display(), e))?;

        for entry in entries {
            let entry = entry.map_err(|e| format!("读取目录项失败: {}", e))?;
            let path = entry.path();

            if path.is_file() {
                if self.is_video_file(&path) {
                    if let Some(scanned_file) = self.parse_file(&path) {
                        files.push(scanned_file);
                    }
                }
            } else if path.is_dir() && recursive {
                // 递归扫描子目录
                self.scan_dir_recursive(&path, recursive, files)?;
            }
        }

        Ok(())
    }

    /// 判断是否为视频文件
    fn is_video_file(&self, path: &Path) -> bool {
        if let Some(ext) = path.extension() {
            // 使用 to_string_lossy 来处理非 UTF-8 扩展名
            let ext_str = ext.to_string_lossy().to_lowercase();
            return VIDEO_EXTENSIONS.contains(&ext_str.as_str());
        }
        false
    }

    /// 解析文件信息
    fn parse_file(&self, path: &Path) -> Option<ScannedFile> {
        // 使用 to_string_lossy 来处理非 UTF-8 路径（包括中文路径）
        let file_name = path.file_name()?.to_string_lossy().to_string();
        let file_path = path.to_string_lossy().to_string();
        
        let metadata = fs::metadata(path).ok()?;
        let file_size = metadata.len();

        // 解析文件名
        let (parsed_code, parsed_title, parsed_year) = self.parse_filename(&file_name);

        Some(ScannedFile {
            file_path,
            file_name,
            file_size,
            parsed_code,
            parsed_title,
            parsed_year,
        })
    }

    /// 解析文件名，提取识别号、标题、年份
    fn parse_filename(&self, filename: &str) -> (Option<String>, Option<String>, Option<i32>) {
        // 移除文件扩展名
        let name_without_ext = filename.rsplit_once('.').map(|(n, _)| n).unwrap_or(filename);

        // 提取识别号
        let parsed_code = self.code_regex.captures(name_without_ext).map(|cap| {
            format!("{}-{}", &cap[1], &cap[2])
        });

        // 提取年份
        let parsed_year = self.year_regex.captures(name_without_ext)
            .and_then(|cap| cap[1].parse::<i32>().ok());

        // 提取标题（简单处理：移除识别号、年份、特殊标记后的内容）
        let mut title = name_without_ext.to_string();
        
        // 移除识别号
        if let Some(ref code) = parsed_code {
            title = title.replace(code, "");
            title = title.replace(&code.replace("-", ""), "");
        }
        
        // 移除年份
        if let Some(year) = parsed_year {
            title = title.replace(&year.to_string(), "");
        }
        
        // 移除常见标记
        let markers = vec![
            r"\[.*?\]",  // [1080p], [中文字幕] 等
            r"\(.*?\)",  // (2023) 等
            r"1080p", "720p", "480p", "4K", "2160p",
            r"BluRay", "WEB-DL", "WEBRip", "HDRip",
            r"x264", "x265", "H264", "H265", "HEVC",
            r"AAC", "AC3", "DTS",
        ];
        
        for marker in markers {
            // 动态正则表达式可能失败，需要处理错误
            if let Ok(re) = Regex::new(marker) {
                title = re.replace_all(&title, "").to_string();
            } else {
                tracing::warn!("Invalid regex marker pattern: {}", marker);
            }
        }
        
        // 清理标题
        title = title
            .replace("_", " ")
            .replace(".", " ")
            .replace("-", " ")
            .trim()
            .to_string();

        let parsed_title = if title.is_empty() {
            None
        } else {
            Some(title)
        };

        (parsed_code, parsed_title, parsed_year)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_filename() {
        let scanner = FileScanner::new();

        // 测试识别号格式
        let (code, title, year) = scanner.parse_filename("ABC-123 标题名称 [1080p].mp4");
        assert_eq!(code, Some("ABC-123".to_string()));
        assert!(title.is_some());

        // 测试年份
        let (_, _, year) = scanner.parse_filename("电影标题.2023.1080p.mp4");
        assert_eq!(year, Some(2023));

        // 测试复杂文件名
        let (code, _, _) = scanner.parse_filename("[ABC-123] 标题 (2023) [1080p] [中文字幕].mkv");
        assert_eq!(code, Some("ABC-123".to_string()));
    }
}
