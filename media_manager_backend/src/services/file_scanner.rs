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
    // 有码番号
    censored_code_regex: Regex,
    // 无码番号 - 一本道系列 (6位日期_3位编号)
    ippondo_regex: Regex,
    // 无码番号 - 10musume (6位日期_2位编号)
    tenmusume_regex: Regex,
    // 无码番号 - FC2
    fc2_regex: Regex,
    // 无码番号 - HEYZO
    heyzo_regex: Regex,
    // 无码番号 - Tokyo-Hot
    tokyohot_regex: Regex,
    // 年份
    year_regex: Regex,
    // 欧美系列+日期
    western_series_date_regex: Regex,
    // 欧美系列+标题
    western_series_title_regex: Regex,
    // 欧美纯标题（英文字母+空格，没有系列名）
    western_pure_title_regex: Regex,
}

impl FileScanner {
    pub fn new() -> Self {
        Self {
            // 有码番号: ABC-123, ABCD-1234, ABC123
            censored_code_regex: Regex::new(r"([A-Z]{2,6})-?(\d{3,5})")
                .expect("Invalid censored code regex pattern"),
            
            // 一本道系列: 012426_100, 082713-417 (6位日期 + 3位编号)
            // 包括: 1Pondo, Pacopacomama, Caribbeancom, CaribbeancomPR
            ippondo_regex: Regex::new(r"(\d{6})[-_](\d{3})")
                .expect("Invalid ippondo regex pattern"),
            
            // 10musume: 010120_01 (6位日期 + 2位编号)
            tenmusume_regex: Regex::new(r"(\d{6})[-_](\d{2})")
                .expect("Invalid 10musume regex pattern"),
            
            // FC2-PPV: FC2-PPV-1234567, FC2-1234567, FC21234567
            fc2_regex: Regex::new(r"(?i)FC2[-_]?(?:PPV[-_]?)?(\d{5,7})")
                .expect("Invalid FC2 regex pattern"),
            
            // HEYZO: HEYZO-1234, HEYZO1234
            heyzo_regex: Regex::new(r"(?i)HEYZO[-_]?(\d{4})")
                .expect("Invalid HEYZO regex pattern"),
            
            // Tokyo-Hot: N1234, K1234, RED-123, SKY-234
            tokyohot_regex: Regex::new(r"(?i)(?:RED|SKY|EX)[-_]?(\d{3,4})|([NK])(\d{4})")
                .expect("Invalid Tokyo-Hot regex pattern"),
            
            // 年份: 2020, 2021 等
            year_regex: Regex::new(r"\b(19\d{2}|20\d{2})\b")
                .expect("Invalid year regex pattern"),
            
            // 欧美系列+日期: Series.YY.MM.DD
            western_series_date_regex: Regex::new(r"^([a-zA-Z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)*)[.](\d{2})[.](\d{2})[.](\d{2})")
                .expect("Invalid western series date regex pattern"),
            
            // 欧美系列+标题: Series - Title (连字符两边必须有空格，标题内部可以用空格或 . 分隔)
            western_series_title_regex: Regex::new(r"^([a-zA-Z][a-zA-Z0-9]*)\s+-\s+(.+)")
                .expect("Invalid western series title regex pattern"),
            
            // 欧美纯标题: 英文字母+空格组成，至少包含一个空格（排除单词）
            western_pure_title_regex: Regex::new(r"^[a-zA-Z][a-zA-Z\s]+[a-zA-Z]$")
                .expect("Invalid western pure title regex pattern"),
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

        // 1. 尝试识别欧美格式：系列.YY.MM.DD（只支持 YY.MM.DD 格式）
        if let Some(cap) = self.western_series_date_regex.captures(name_without_ext) {
            let mut series = cap[1].to_string();
            let year_str = &cap[2];
            let month_str = &cap[3];
            let day_str = &cap[4];
            
            // 将系列名转换为首字母大写格式（EvilAngel, Straplez 等）
            if !series.is_empty() {
                let mut chars = series.chars();
                if let Some(first) = chars.next() {
                    series = first.to_uppercase().collect::<String>() + chars.as_str();
                }
            }
            
            // 解析 YY.MM.DD 格式的日期
            if let Some((year, month, day)) = Self::parse_date_format(year_str, month_str, day_str) {
                let release_date = format!("{}-{:02}-{:02}", year, month, day);
                let parsed_year = Some(year);
                
                return (
                    None,                      // code: 欧美不使用 code
                    None,                      // title: 不提取标题（不准确）
                    parsed_year,               // year
                    Some(series),              // series: 系列名（首字母大写）
                    Some(release_date),        // date: 发布日期
                );
            }
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

        // 3. 尝试识别欧美纯标题（英文字母+空格）
        if self.western_pure_title_regex.is_match(name_without_ext) {
            let mut title = name_without_ext.to_string();
            
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
                None,                      // series: 纯标题没有系列名
                None,                      // date
            );
        }

        // 4. 尝试识别 JAV 番号
        let parsed_code = self.parse_jav_code(name_without_ext);

        // 5. 提取年份
        let parsed_year = self.year_regex.captures(name_without_ext)
            .and_then(|cap| cap[1].parse::<i32>().ok());

        // 6. 提取标题（移除识别号、年份、特殊标记后的内容）
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

    /// 解析 JAV 番号（有码 + 无码）
    fn parse_jav_code(&self, name: &str) -> Option<String> {
        // 优先级1: FC2-PPV (最特殊，需要先匹配)
        if let Some(cap) = self.fc2_regex.captures(name) {
            let number = &cap[1];
            return Some(format!("FC2-PPV-{}", number));
        }
        
        // 优先级2: HEYZO
        if let Some(cap) = self.heyzo_regex.captures(name) {
            let number = &cap[1];
            return Some(format!("HEYZO-{}", number));
        }
        
        // 优先级3: Tokyo-Hot
        if let Some(cap) = self.tokyohot_regex.captures(name) {
            if let Some(prefix_match) = cap.get(1) {
                // RED-123, SKY-234, EX-0012
                let prefix = name[cap.get(0).unwrap().start()..prefix_match.start()].to_uppercase();
                let number = prefix_match.as_str();
                return Some(format!("{}-{}", prefix.trim_end_matches('-').trim_end_matches('_'), number));
            } else if let Some(letter) = cap.get(2) {
                // N1234, K1234
                let number = &cap[3];
                return Some(format!("{}{}", letter.as_str().to_uppercase(), number));
            }
        }
        
        // 优先级4: 一本道系列 (6位日期_3位编号)
        // 必须在 10musume 之前检查，因为格式更长
        if let Some(cap) = self.ippondo_regex.captures(name) {
            let date = &cap[1];
            let number = &cap[2];
            return Some(format!("{}_{}", date, number));
        }
        
        // 优先级5: 10musume (6位日期_2位编号)
        if let Some(cap) = self.tenmusume_regex.captures(name) {
            let date = &cap[1];
            let number = &cap[2];
            return Some(format!("{}_{}", date, number));
        }
        
        // 优先级6: 有码番号 (ABC-123)
        if let Some(cap) = self.censored_code_regex.captures(name) {
            let prefix = &cap[1];
            let number = &cap[2];
            return Some(format!("{}-{}", prefix, number));
        }
        
        None
    }
    
    /// 解析日期格式 (仅支持 YY.MM.DD)
    /// 返回: Some((year, month, day)) 或 None
    fn parse_date_format(num1: &str, num2: &str, num3: &str) -> Option<(i32, u32, u32)> {
        let year_part = num1.parse::<u32>().ok()?;
        let month = num2.parse::<u32>().ok()?;
        let day = num3.parse::<u32>().ok()?;
        
        // 验证月份和日期的合法性
        if month < 1 || month > 12 || day < 1 || day > 31 {
            return None;
        }
        
        // 将两位年份转换为四位年份
        let year = if year_part > 50 {
            1900 + year_part as i32
        } else {
            2000 + year_part as i32
        };
        
        Some((year, month, day))
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

        // ========== 欧美格式测试 ==========
        
        // 测试欧美系列+日期格式 (YY.MM.DD)
        let (code, title, year, series, date) = scanner.parse_filename("Straplez.26.01.23.mp4");
        assert_eq!(code, None);
        assert_eq!(title, None);
        assert_eq!(series, Some("Straplez".to_string()));
        assert_eq!(date, Some("2026-01-23".to_string()));
        assert_eq!(year, Some(2026));

        // 测试欧美系列+日期格式 (小写系列名)
        let (code, title, year, series, date) = scanner.parse_filename("brazzersexxtra.25.10.20.mp4");
        assert_eq!(code, None);
        assert_eq!(title, None);
        assert_eq!(series, Some("Brazzersexxtra".to_string()));
        assert_eq!(date, Some("2025-10-20".to_string()));
        assert_eq!(year, Some(2025));

        // 测试欧美系列+标题格式（连字符分隔）
        let (code, title, _year, series, date) = scanner.parse_filename("Brazzers-Scene Title.mp4");
        assert_eq!(code, None);
        assert!(title.is_some());
        assert_eq!(series, Some("Brazzers".to_string()));
        assert_eq!(date, None);
        
        // 测试欧美系列+标题格式（点号分隔）
        let (code, title, _year, series, date) = scanner.parse_filename("Brazzersexxtra.Miss.Lexa.These.Shades.mp4");
        assert_eq!(code, None);
        assert_eq!(series, Some("Brazzersexxtra".to_string()));
        assert_eq!(title, Some("Miss Lexa These Shades".to_string()));
        assert_eq!(date, None);

        // ========== JAV 有码格式测试 ==========
        
        // 测试有码番号 (带连字符)
        let (code, title, _year, series, date) = scanner.parse_filename("IPX-177 标题名称 [1080p].mp4");
        assert_eq!(code, Some("IPX-177".to_string()));
        assert!(title.is_some());
        assert_eq!(series, None);
        assert_eq!(date, None);

        // 测试有码番号 (无连字符)
        let (code, _, _, _, _) = scanner.parse_filename("SSNI644.mp4");
        assert_eq!(code, Some("SSNI-644".to_string()));

        // ========== JAV 无码格式测试 ==========
        
        // 测试一本道系列 (6位日期_3位编号)
        let (code, _, _, _, _) = scanner.parse_filename("012426_100.mp4");
        assert_eq!(code, Some("012426_100".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("082713-417.mp4");
        assert_eq!(code, Some("082713_417".to_string()));

        // 测试 10musume (6位日期_2位编号)
        let (code, _, _, _, _) = scanner.parse_filename("010120_01.mp4");
        assert_eq!(code, Some("010120_01".to_string()));

        // 测试 FC2-PPV
        let (code, _, _, _, _) = scanner.parse_filename("FC2-PPV-1234567.mp4");
        assert_eq!(code, Some("FC2-PPV-1234567".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("FC2-1234567.mp4");
        assert_eq!(code, Some("FC2-PPV-1234567".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("fc2ppv1234567.mp4");
        assert_eq!(code, Some("FC2-PPV-1234567".to_string()));

        // 测试 HEYZO
        let (code, _, _, _, _) = scanner.parse_filename("HEYZO-1234.mp4");
        assert_eq!(code, Some("HEYZO-1234".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("heyzo1234.mp4");
        assert_eq!(code, Some("HEYZO-1234".to_string()));

        // 测试 Tokyo-Hot
        let (code, _, _, _, _) = scanner.parse_filename("N1234.mp4");
        assert_eq!(code, Some("N1234".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("K5678.mp4");
        assert_eq!(code, Some("K5678".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("RED-123.mp4");
        assert_eq!(code, Some("RED-123".to_string()));

        let (code, _, _, _, _) = scanner.parse_filename("SKY-234.mp4");
        assert_eq!(code, Some("SKY-234".to_string()));

        // ========== 通用测试 ==========
        
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
