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
    pub parsed_code: Option<String>,      // JAV 番号（如 IPX-177）
    pub parsed_title: Option<String>,     // 标题
    pub parsed_year: Option<i32>,         // 年份
    pub parsed_series: Option<String>,    // 系列名（欧美，如 Straplez）
    pub parsed_date: Option<String>,      // 发布日期（欧美，如 2026-01-23）
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
    western_series_date_regex: Regex,
    western_series_title_regex: Regex,
}

impl FileScanner {
    pub fn new() -> Self {
        Self {
            // 匹配 JAV 番号格式: ABC-123, ABCD-1234, ABC123 等
            code_regex: Regex::new(r"([A-Z]{2,6})-?(\d{3,5})")
                .expect("Invalid code regex pattern - this is a programming error"),
            // 匹配年份: 2020, 2021 等
            year_regex: Regex::new(r"\b(19\d{2}|20\d{2})\b")
                .expect("Invalid year regex pattern - this is a programming error"),
            // 匹配欧美系列+日期格式: Series.YY.MM.DD 或 Series YY MM DD（支持空格和点号分隔，支持大小写）
            western_series_date_regex: Regex::new(r"^([a-zA-Z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)*)[.\s](\d{2})[.\s](\d{2})[.\s](\d{2})")
                .expect("Invalid western series date regex pattern - this is a programming error"),
            // 匹配欧美系列+标题格式: Series-Title 或 Series.Title（支持大小写）
            western_series_title_regex: Regex::new(r"^([a-zA-Z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)*)[-\.](.+)")
                .expect("Invalid western series title regex pattern - this is a programming error"),
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
        let (parsed_code, parsed_title, parsed_year, parsed_series, parsed_date) = self.parse_filename(&file_name);

        Some(ScannedFile {
            file_path,
            file_name,
            file_size,
            parsed_code,
            parsed_title,
            parsed_year,
            parsed_series,
            parsed_date,
        })
    }

    /// 解析文件名，提取识别号、标题、年份、系列、日期
    fn parse_filename(&self, filename: &str) -> (Option<String>, Option<String>, Option<i32>, Option<String>, Option<String>) {
        // 移除文件扩展名
        let name_without_ext = filename.rsplit_once('.').map(|(n, _)| n).unwrap_or(filename);

        // 1. 尝试识别欧美格式：系列.YY.MM.DD 或 系列 YY MM DD（只识别系列和日期，不提取标题）
        if let Some(cap) = self.western_series_date_regex.captures(name_without_ext) {
            let mut series = cap[1].to_string();
            let year = &cap[2];
            let month = &cap[3];
            let day = &cap[4];
            
            // 将系列名转换为首字母大写格式（EvilAngel, Straplez 等）
            if !series.is_empty() {
                let mut chars = series.chars();
                if let Some(first) = chars.next() {
                    series = first.to_uppercase().collect::<String>() + chars.as_str();
                }
            }
            
            // 构建完整日期：YYYY-MM-DD
            let full_year = format!("20{}", year);
            let release_date = format!("{}-{}-{}", full_year, month, day);
            let parsed_year = full_year.parse::<i32>().ok();
            
            return (
                None,                      // code: 欧美不使用 code
                None,                      // title: 不提取标题（不准确）
                parsed_year,               // year
                Some(series),              // series: 系列名（首字母大写）
                Some(release_date),        // date: 发布日期
            );
        }

        // 2. 尝试识别欧美格式：系列-标题 或 系列.标题
        if let Some(cap) = self.western_series_title_regex.captures(name_without_ext) {
            let mut series = cap[1].to_string();
            let mut title = cap[2].to_string();
            
            // 将系列名转换为首字母大写格式
            if !series.is_empty() {
                let mut chars = series.chars();
                if let Some(first) = chars.next() {
                    series = first.to_uppercase().collect::<String>() + chars.as_str();
                }
            }
            
            // 检查标题是否以大写字母开头（排除 JAV 番号误匹配）
            if !title.is_empty() && title.chars().next().unwrap().is_uppercase() {
                // 清理标题
                title = title
                    .replace("_", " ")
                    .replace(".", " ")
                    .trim()
                    .to_string();
                
                // 移除常见标记
                title = self.remove_common_markers(&title);
                
                // 提取年份（如果有）
                let parsed_year = self.year_regex.captures(&title)
                    .and_then(|cap| cap[1].parse::<i32>().ok());
                
                // 从标题中移除年份
                if let Some(year) = parsed_year {
                    title = title.replace(&year.to_string(), "").trim().to_string();
                }
                
                let parsed_title = if title.is_empty() { None } else { Some(title) };
                
                return (
                    None,                      // code: 欧美不使用 code
                    parsed_title,              // title
                    parsed_year,               // year
                    Some(series),              // series: 系列名（首字母大写）
                    None,                      // date
                );
            }
        }

        // 3. 尝试识别 JAV 番号：ABC-123
        let parsed_code = self.code_regex.captures(name_without_ext).map(|cap| {
            format!("{}-{}", &cap[1], &cap[2])
        });

        // 4. 提取年份
        let parsed_year = self.year_regex.captures(name_without_ext)
            .and_then(|cap| cap[1].parse::<i32>().ok());

        // 5. 提取标题（移除识别号、年份、特殊标记后的内容）
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
        title = self.remove_common_markers(&title);
        
        // 清理标题
        title = title
            .replace("_", " ")
            .replace(".", " ")
            .replace("-", " ")
            .trim()
            .to_string();

        let parsed_title = if title.is_empty() { None } else { Some(title) };

        (
            parsed_code,     // code: JAV 番号
            parsed_title,    // title
            parsed_year,     // year
            None,            // series: JAV 不使用 series
            None,            // date
        )
    }

    /// 移除常见的视频质量标记
    fn remove_common_markers(&self, text: &str) -> String {
        let markers = vec![
            r"\[.*?\]",  // [1080p], [中文字幕] 等
            r"\(.*?\)",  // (2023) 等
            r"(?i)1080p", "(?i)720p", "(?i)480p", "(?i)4K", "(?i)2160p",
            r"(?i)BluRay", "(?i)WEB-DL", "(?i)WEBRip", "(?i)HDRip",
            r"(?i)x264", "(?i)x265", "(?i)H264", "(?i)H265", "(?i)HEVC",
            r"(?i)AAC", "(?i)AC3", "(?i)DTS",
        ];
        
        let mut result = text.to_string();
        for marker in markers {
            // 动态正则表达式可能失败，需要处理错误
            if let Ok(re) = Regex::new(marker) {
                result = re.replace_all(&result, "").to_string();
            } else {
                tracing::warn!("Invalid regex marker pattern: {}", marker);
            }
        }
        
        result.trim().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_filename() {
        let scanner = FileScanner::new();

        // 测试欧美系列+日期格式
        let (code, title, _year, series, date) = scanner.parse_filename("Straplez.26.01.23.mp4");
        assert_eq!(code, None);
        assert_eq!(title, None);  // 不提取标题
        assert_eq!(series, Some("Straplez".to_string()));
        assert_eq!(date, Some("2026-01-23".to_string()));

        // 测试欧美系列+标题格式
        let (code, title, _year, series, date) = scanner.parse_filename("Brazzers-Scene Title.mp4");
        assert_eq!(code, None);
        assert!(title.is_some());
        assert_eq!(series, Some("Brazzers".to_string()));
        assert_eq!(date, None);

        // 测试 JAV 番号格式
        let (code, title, _year, series, date) = scanner.parse_filename("ABC-123 标题名称 [1080p].mp4");
        assert_eq!(code, Some("ABC-123".to_string()));
        assert!(title.is_some());
        assert_eq!(series, None);
        assert_eq!(date, None);

        // 测试年份
        let (_, _, year, _, _) = scanner.parse_filename("电影标题.2023.1080p.mp4");
        assert_eq!(year, Some(2023));

        // 测试复杂文件名
        let (code, _, _, _, _) = scanner.parse_filename("[ABC-123] 标题 (2023) [1080p] [中文字幕].mkv");
        assert_eq!(code, Some("ABC-123".to_string()));

        // 测试纯标题+年份（括号格式）
        let (code, title, year, series, date) = scanner.parse_filename("Movie Title (2023).mp4");
        assert_eq!(code, None);
        assert_eq!(title, Some("Movie Title".to_string()));
        assert_eq!(year, Some(2023));
        assert_eq!(series, None);
        assert_eq!(date, None);

        // 测试纯标题+年份（空格格式）
        let (code, title, year, series, date) = scanner.parse_filename("Movie Title 2023.mp4");
        assert_eq!(code, None);
        assert_eq!(title, Some("Movie Title".to_string()));
        assert_eq!(year, Some(2023));
        assert_eq!(series, None);
        assert_eq!(date, None);
    }
}
