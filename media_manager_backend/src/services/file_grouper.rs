use crate::services::file_scanner::ScannedFile;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 分段模式类型
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum PartPatternType {
    CD,         // CD1, CD2, CD3
    Part,       // Part1, Part2, Part3
    Disc,       // Disc1, Disc2, Disc3
    Number,     // 01, 02, 03
    Underscore, // _1, _2, _3
    Hyphen,     // -1, -2, -3
}

/// 分段信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartInfo {
    pub part_number: i32,
    pub part_label: String,
    pub pattern_type: PartPatternType,
}

/// 带分段信息的扫描文件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScannedFileWithPart {
    pub scanned_file: ScannedFile,
    pub part_info: Option<PartInfo>,
}

/// 文件组
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileGroup {
    pub base_name: String,
    pub files: Vec<ScannedFileWithPart>,
    pub total_size: u64,
}

impl FileGroup {
    /// 获取排序后的文件列表
    pub fn sorted_files(&self) -> Vec<&ScannedFileWithPart> {
        let mut files: Vec<&ScannedFileWithPart> = self.files.iter().collect();
        files.sort_by_key(|f| {
            f.part_info
                .as_ref()
                .map(|p| p.part_number)
                .unwrap_or(i32::MAX)
        });
        files
    }
}

/// 文件分组器
pub struct FileGrouper {
    // 各种分段模式的正则表达式
    cd_regex: Regex,
    part_regex: Regex,
    disc_regex: Regex,
    number_regex: Regex,
    underscore_regex: Regex,
    hyphen_regex: Regex,
}

impl FileGrouper {
    pub fn new() -> Self {
        Self {
            // CD1, CD2, CD3 等（不区分大小写）
            // 这些正则表达式是硬编码的，应该总是有效的
            cd_regex: Regex::new(r"(?i)[-_\s]?cd[-_\s]?(\d+)")
                .expect("Invalid cd regex pattern - this is a programming error"),
            // Part1, Part2, Part3 等（不区分大小写）
            part_regex: Regex::new(r"(?i)[-_\s]?part[-_\s]?(\d+)")
                .expect("Invalid part regex pattern - this is a programming error"),
            // Disc1, Disc2, Disc3 等（不区分大小写）
            disc_regex: Regex::new(r"(?i)[-_\s]?disc[-_\s]?(\d+)")
                .expect("Invalid disc regex pattern - this is a programming error"),
            // 纯数字：01, 02, 03 等（文件名末尾）
            number_regex: Regex::new(r"[-_\s](\d{2,3})$")
                .expect("Invalid number regex pattern - this is a programming error"),
            // 下划线+数字：_1, _2, _3
            underscore_regex: Regex::new(r"_(\d+)$")
                .expect("Invalid underscore regex pattern - this is a programming error"),
            // 连字符+数字：-1, -2, -3（但不是识别号格式）
            hyphen_regex: Regex::new(r"-(\d+)$")
                .expect("Invalid hyphen regex pattern - this is a programming error"),
        }
    }

    /// 将扫描的文件按基础名称分组
    pub fn group_files(&self, files: Vec<ScannedFile>) -> Vec<FileGroup> {
        // 第一步：为每个文件解析分段信息
        let files_with_parts: Vec<ScannedFileWithPart> = files
            .into_iter()
            .map(|file| {
                let part_info = self.parse_part_info(&file.file_name);
                ScannedFileWithPart {
                    scanned_file: file,
                    part_info,
                }
            })
            .collect();

        // 第二步：按基础名称分组
        let mut groups: HashMap<String, Vec<ScannedFileWithPart>> = HashMap::new();

        for file_with_part in files_with_parts {
            let base_name = self.extract_base_name(&file_with_part.scanned_file.file_name);
            groups
                .entry(base_name)
                .or_insert_with(Vec::new)
                .push(file_with_part);
        }

        // 第三步：转换为 FileGroup 并计算总大小
        groups
            .into_iter()
            .map(|(base_name, files)| {
                let total_size: u64 = files.iter().map(|f| f.scanned_file.file_size).sum();
                FileGroup {
                    base_name,
                    files,
                    total_size,
                }
            })
            .collect()
    }

    /// 识别文件的分段信息
    pub fn parse_part_info(&self, filename: &str) -> Option<PartInfo> {
        // 移除文件扩展名
        let name_without_ext = filename
            .rsplit_once('.')
            .map(|(n, _)| n)
            .unwrap_or(filename);

        // 按优先级尝试各种模式
        // 1. CD 模式
        if let Some(cap) = self.cd_regex.captures(name_without_ext) {
            if let Ok(num) = cap[1].parse::<i32>() {
                return Some(PartInfo {
                    part_number: num,
                    part_label: format!("CD{}", num),
                    pattern_type: PartPatternType::CD,
                });
            }
        }

        // 2. Part 模式
        if let Some(cap) = self.part_regex.captures(name_without_ext) {
            if let Ok(num) = cap[1].parse::<i32>() {
                return Some(PartInfo {
                    part_number: num,
                    part_label: format!("Part {}", num),
                    pattern_type: PartPatternType::Part,
                });
            }
        }

        // 3. Disc 模式
        if let Some(cap) = self.disc_regex.captures(name_without_ext) {
            if let Ok(num) = cap[1].parse::<i32>() {
                return Some(PartInfo {
                    part_number: num,
                    part_label: format!("Disc {}", num),
                    pattern_type: PartPatternType::Disc,
                });
            }
        }

        // 4. 下划线模式（优先于纯数字）
        if let Some(cap) = self.underscore_regex.captures(name_without_ext) {
            if let Ok(num) = cap[1].parse::<i32>() {
                return Some(PartInfo {
                    part_number: num,
                    part_label: format!("Part {}", num),
                    pattern_type: PartPatternType::Underscore,
                });
            }
        }

        // 5. 连字符模式（但要排除识别号格式）
        if let Some(cap) = self.hyphen_regex.captures(name_without_ext) {
            // 检查是否是识别号格式（如 ABC-123）
            if let Some(match_pos) = cap.get(0) {
                let before_hyphen = &name_without_ext[..match_pos.start()];
                if !before_hyphen.chars().rev().take(6).all(|c| c.is_ascii_uppercase()) {
                    if let Ok(num) = cap[1].parse::<i32>() {
                        return Some(PartInfo {
                            part_number: num,
                            part_label: format!("Part {}", num),
                            pattern_type: PartPatternType::Hyphen,
                        });
                    }
                }
            }
        }

        // 6. 纯数字模式（最低优先级）
        if let Some(cap) = self.number_regex.captures(name_without_ext) {
            if let Ok(num) = cap[1].parse::<i32>() {
                // 只有当数字小于等于 20 时才认为是分段（避免误判年份等）
                if num <= 20 {
                    return Some(PartInfo {
                        part_number: num,
                        part_label: format!("{:02}", num),
                        pattern_type: PartPatternType::Number,
                    });
                }
            }
        }

        None
    }

    /// 提取基础文件名（去除分段标记和扩展名）
    pub fn extract_base_name(&self, filename: &str) -> String {
        // 移除文件扩展名
        let name_without_ext = filename
            .rsplit_once('.')
            .map(|(n, _)| n)
            .unwrap_or(filename);

        // 移除各种分段标记
        let mut base_name = name_without_ext.to_string();

        // 按优先级移除模式
        if let Some(cap) = self.cd_regex.find(&base_name) {
            base_name = base_name[..cap.start()].to_string();
        } else if let Some(cap) = self.part_regex.find(&base_name) {
            base_name = base_name[..cap.start()].to_string();
        } else if let Some(cap) = self.disc_regex.find(&base_name) {
            base_name = base_name[..cap.start()].to_string();
        } else if let Some(cap) = self.underscore_regex.find(&base_name) {
            base_name = base_name[..cap.start()].to_string();
        } else if let Some(cap) = self.hyphen_regex.find(&base_name) {
            // 检查是否是识别号格式
            let before_hyphen = &base_name[..cap.start()];
            if !before_hyphen
                .chars()
                .rev()
                .take(6)
                .all(|c| c.is_ascii_uppercase())
            {
                base_name = base_name[..cap.start()].to_string();
            }
        } else if let Some(cap) = self.number_regex.find(&base_name) {
            if let Ok(num) = base_name[cap.start() + 1..cap.end()].parse::<i32>() {
                if num <= 20 {
                    base_name = base_name[..cap.start()].to_string();
                }
            }
        }

        // 清理末尾的空格、下划线、连字符
        base_name.trim_end_matches(&[' ', '_', '-'][..]).to_string()
    }
}

impl Default for FileGrouper {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_part_info_cd() {
        let grouper = FileGrouper::new();

        let info = grouper.parse_part_info("Movie-CD1.mp4");
        assert!(info.is_some());
        let info = info.expect("Should parse CD1 format");
        assert_eq!(info.part_number, 1);
        assert_eq!(info.part_label, "CD1");
        assert_eq!(info.pattern_type, PartPatternType::CD);

        let info = grouper.parse_part_info("Movie CD2.mkv");
        assert!(info.is_some());
        assert_eq!(info.expect("Should parse CD2 format").part_number, 2);
    }

    #[test]
    fn test_parse_part_info_part() {
        let grouper = FileGrouper::new();

        let info = grouper.parse_part_info("Movie-Part1.mp4");
        assert!(info.is_some());
        let info = info.expect("Should parse Part1 format");
        assert_eq!(info.part_number, 1);
        assert_eq!(info.part_label, "Part 1");
        assert_eq!(info.pattern_type, PartPatternType::Part);
    }

    #[test]
    fn test_parse_part_info_disc() {
        let grouper = FileGrouper::new();

        let info = grouper.parse_part_info("Movie-Disc1.mp4");
        assert!(info.is_some());
        let info = info.expect("Should parse Disc1 format");
        assert_eq!(info.part_number, 1);
        assert_eq!(info.pattern_type, PartPatternType::Disc);
    }

    #[test]
    fn test_parse_part_info_number() {
        let grouper = FileGrouper::new();

        let info = grouper.parse_part_info("Movie-01.mp4");
        assert!(info.is_some());
        assert_eq!(info.expect("Should parse number format").part_number, 1);

        // 大数字不应该被识别为分段
        let info = grouper.parse_part_info("Movie-2023.mp4");
        assert!(info.is_none());
    }

    #[test]
    fn test_parse_part_info_underscore() {
        let grouper = FileGrouper::new();

        let info = grouper.parse_part_info("Movie_1.mp4");
        assert!(info.is_some());
        assert_eq!(info.expect("Should parse underscore format").part_number, 1);
    }

    #[test]
    fn test_parse_part_info_hyphen() {
        let grouper = FileGrouper::new();

        let info = grouper.parse_part_info("Movie-1.mp4");
        assert!(info.is_some());
        assert_eq!(info.expect("Should parse hyphen format").part_number, 1);

        // 识别号格式不应该被识别为分段
        let info = grouper.parse_part_info("ABC-123.mp4");
        assert!(info.is_none());
    }

    #[test]
    fn test_extract_base_name() {
        let grouper = FileGrouper::new();

        assert_eq!(grouper.extract_base_name("Movie-CD1.mp4"), "Movie");
        assert_eq!(grouper.extract_base_name("Movie-Part1.mkv"), "Movie");
        assert_eq!(grouper.extract_base_name("Movie-Disc1.avi"), "Movie");
        assert_eq!(grouper.extract_base_name("Movie-01.mp4"), "Movie");
        assert_eq!(grouper.extract_base_name("Movie_1.mp4"), "Movie");

        // 识别号格式应该保留
        assert_eq!(grouper.extract_base_name("ABC-123.mp4"), "ABC-123");
    }

    #[test]
    fn test_group_files() {
        let grouper = FileGrouper::new();

        let files = vec![
            ScannedFile {
                file_path: "/path/Movie-CD1.mp4".to_string(),
                file_name: "Movie-CD1.mp4".to_string(),
                file_size: 1000,
                parsed_code: None,
                parsed_title: Some("Movie".to_string()),
                parsed_year: None,
                parsed_series: None,
                parsed_date: None,
            },
            ScannedFile {
                file_path: "/path/Movie-CD2.mp4".to_string(),
                file_name: "Movie-CD2.mp4".to_string(),
                file_size: 1000,
                parsed_code: None,
                parsed_title: Some("Movie".to_string()),
                parsed_year: None,
                parsed_series: None,
                parsed_date: None,
            },
            ScannedFile {
                file_path: "/path/Other.mp4".to_string(),
                file_name: "Other.mp4".to_string(),
                file_size: 500,
                parsed_code: None,
                parsed_title: Some("Other".to_string()),
                parsed_year: None,
                parsed_series: None,
                parsed_date: None,
            },
        ];

        let groups = grouper.group_files(files);

        assert_eq!(groups.len(), 2);

        // 找到 Movie 组
        let movie_group = groups.iter().find(|g| g.base_name == "Movie")
            .expect("Should find Movie group");
        assert_eq!(movie_group.files.len(), 2);
        assert_eq!(movie_group.total_size, 2000);

        // 找到 Other 组
        let other_group = groups.iter().find(|g| g.base_name == "Other")
            .expect("Should find Other group");
        assert_eq!(other_group.files.len(), 1);
        assert_eq!(other_group.total_size, 500);
    }
}
