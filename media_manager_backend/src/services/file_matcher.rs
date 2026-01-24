use crate::models::media::MediaItem;
use crate::services::file_scanner::ScannedFile;
use crate::services::file_grouper::FileGroup;
use serde::{Deserialize, Serialize};

/// 匹配结果类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum MatchType {
    Exact,      // 精确匹配
    Fuzzy,      // 模糊匹配
    None,       // 未匹配
}

/// 单个文件的匹配结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchResult {
    pub scanned_file: ScannedFile,
    pub match_type: MatchType,
    pub matched_media: Option<MediaItem>,
    pub confidence: f32,  // 匹配置信度 0.0-1.0
    pub suggestions: Vec<MediaItem>,  // 可能的匹配建议
}

/// 文件组的匹配结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMatchResult {
    pub file_group: FileGroup,
    pub match_type: MatchType,
    pub matched_media: Option<MediaItem>,
    pub confidence: f32,
    pub suggestions: Vec<MediaItem>,
}

/// 文件匹配器
pub struct FileMatcher;

impl FileMatcher {
    /// 匹配扫描的文件到数据库中的媒体
    pub fn match_files(
        scanned_files: Vec<ScannedFile>,
        all_media: Vec<MediaItem>,
    ) -> Vec<MatchResult> {
        scanned_files
            .into_iter()
            .map(|file| Self::match_single_file(file, &all_media))
            .collect()
    }

    /// 匹配文件组到数据库中的媒体
    pub fn match_file_groups(
        file_groups: Vec<FileGroup>,
        all_media: Vec<MediaItem>,
    ) -> Vec<GroupMatchResult> {
        file_groups
            .into_iter()
            .map(|group| Self::match_single_group(group, &all_media))
            .collect()
    }

    /// 匹配单个文件组
    fn match_single_group(group: FileGroup, all_media: &[MediaItem]) -> GroupMatchResult {
        // 使用第一个文件的信息进行匹配
        if let Some(first_file) = group.files.first() {
            let file = &first_file.scanned_file;

            // 1. 尝试通过识别号精确匹配
            if let Some(ref code) = file.parsed_code {
                if let Some(media) = Self::find_by_code(code, all_media) {
                    return GroupMatchResult {
                        file_group: group,
                        match_type: MatchType::Exact,
                        matched_media: Some(media.clone()),
                        confidence: 1.0,
                        suggestions: vec![],
                    };
                }
            }

            // 2. 尝试通过基础名称模糊匹配
            let fuzzy_matches = Self::find_by_title_fuzzy(&group.base_name, all_media, 0.6);

            if !fuzzy_matches.is_empty() {
                let best_match = &fuzzy_matches[0];
                let confidence = best_match.1;

                if confidence > 0.8 {
                    // 高置信度，认为是匹配
                    return GroupMatchResult {
                        file_group: group,
                        match_type: MatchType::Fuzzy,
                        matched_media: Some(best_match.0.clone()),
                        confidence,
                        suggestions: fuzzy_matches
                            .iter()
                            .skip(1)
                            .take(3)
                            .map(|(m, _)| (*m).clone())
                            .collect(),
                    };
                } else {
                    // 中等置信度，提供建议
                    return GroupMatchResult {
                        file_group: group,
                        match_type: MatchType::None,
                        matched_media: None,
                        confidence: 0.0,
                        suggestions: fuzzy_matches
                            .iter()
                            .take(5)
                            .map(|(m, _)| (*m).clone())
                            .collect(),
                    };
                }
            }
        }

        // 3. 未匹配
        GroupMatchResult {
            file_group: group,
            match_type: MatchType::None,
            matched_media: None,
            confidence: 0.0,
            suggestions: vec![],
        }
    }

    /// 匹配单个文件
    fn match_single_file(file: ScannedFile, all_media: &[MediaItem]) -> MatchResult {
        // 1. 尝试通过识别号精确匹配
        if let Some(ref code) = file.parsed_code {
            if let Some(media) = Self::find_by_code(code, all_media) {
                return MatchResult {
                    scanned_file: file,
                    match_type: MatchType::Exact,
                    matched_media: Some(media.clone()),
                    confidence: 1.0,
                    suggestions: vec![],
                };
            }
        }

        // 2. 尝试通过标题模糊匹配
        if let Some(ref title) = file.parsed_title {
            let fuzzy_matches = Self::find_by_title_fuzzy(title, all_media, 0.6);
            
            if !fuzzy_matches.is_empty() {
                let best_match = &fuzzy_matches[0];
                let confidence = best_match.1;
                
                if confidence > 0.8 {
                    // 高置信度，认为是匹配
                    return MatchResult {
                        scanned_file: file,
                        match_type: MatchType::Fuzzy,
                        matched_media: Some(best_match.0.clone()),
                        confidence,
                        suggestions: fuzzy_matches.iter().skip(1).take(3).map(|(m, _)| (*m).clone()).collect(),
                    };
                } else {
                    // 中等置信度，提供建议
                    return MatchResult {
                        scanned_file: file,
                        match_type: MatchType::None,
                        matched_media: None,
                        confidence: 0.0,
                        suggestions: fuzzy_matches.iter().take(5).map(|(m, _)| (*m).clone()).collect(),
                    };
                }
            }
        }

        // 3. 未匹配
        MatchResult {
            scanned_file: file,
            match_type: MatchType::None,
            matched_media: None,
            confidence: 0.0,
            suggestions: vec![],
        }
    }

    /// 通过识别号查找媒体
    fn find_by_code<'a>(code: &str, all_media: &'a [MediaItem]) -> Option<&'a MediaItem> {
        // 标准化识别号：移除连字符、下划线，转为大写
        let normalized_code = Self::normalize_code(code);
        
        all_media.iter().find(|m| {
            if let Some(ref media_code) = m.code {
                let normalized_media_code = Self::normalize_code(media_code);
                normalized_code == normalized_media_code
            } else {
                false
            }
        })
    }
    
    /// 标准化识别号格式（移除连字符、下划线、空格，转为大写）
    fn normalize_code(code: &str) -> String {
        code.replace("-", "")
            .replace("_", "")
            .replace(" ", "")
            .to_uppercase()
    }

    /// 通过标题模糊匹配
    fn find_by_title_fuzzy<'a>(
        title: &str,
        all_media: &'a [MediaItem],
        threshold: f32,
    ) -> Vec<(&'a MediaItem, f32)> {
        let mut matches: Vec<(&MediaItem, f32)> = all_media
            .iter()
            .filter_map(|media| {
                let similarity = Self::calculate_similarity(title, &media.title);
                if similarity >= threshold {
                    Some((media, similarity))
                } else {
                    None
                }
            })
            .collect();

        // 按相似度降序排序
        matches.sort_by(|a, b| {
            b.1.partial_cmp(&a.1)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        matches
    }

    /// 计算字符串相似度（简单的 Jaccard 相似度）
    fn calculate_similarity(s1: &str, s2: &str) -> f32 {
        let s1_lower = s1.to_lowercase();
        let s2_lower = s2.to_lowercase();

        // 分词（按空格）
        let words1: std::collections::HashSet<&str> = s1_lower.split_whitespace().collect();
        let words2: std::collections::HashSet<&str> = s2_lower.split_whitespace().collect();

        if words1.is_empty() && words2.is_empty() {
            return 1.0;
        }

        if words1.is_empty() || words2.is_empty() {
            return 0.0;
        }

        // Jaccard 相似度
        let intersection = words1.intersection(&words2).count();
        let union = words1.union(&words2).count();

        intersection as f32 / union as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_similarity() {
        let sim = FileMatcher::calculate_similarity("hello world", "hello world");
        assert_eq!(sim, 1.0);

        let sim = FileMatcher::calculate_similarity("hello world", "world hello");
        assert_eq!(sim, 1.0);

        let sim = FileMatcher::calculate_similarity("hello", "world");
        assert_eq!(sim, 0.0);

        let sim = FileMatcher::calculate_similarity("hello world", "hello");
        assert!(sim > 0.0 && sim < 1.0);
    }
}
