// URL 检测器 - 检测临时签名 URL
//
// 本模块提供临时 URL 的检测功能，用于识别包含时效参数的 URL
// 支持检测的参数：validfrom、validto、expires、exp、signature、sig、token

use regex::Regex;
use std::sync::OnceLock;

/// URL 检测器
///
/// 用于检测 URL 是否为临时签名 URL（包含时效参数）
#[derive(Clone, Copy)]
pub struct UrlDetector;

impl UrlDetector {
    /// 检测 URL 是否为临时签名 URL
    ///
    /// # 检测规则
    /// URL 包含以下任一参数时被视为临时 URL：
    /// - validfrom, validto
    /// - expires, exp
    /// - signature, sig, token
    ///
    /// # 参数
    /// - `url`: 要检测的 URL 字符串
    ///
    /// # 返回值
    /// - `true`: URL 包含时效参数，是临时 URL
    /// - `false`: URL 不包含时效参数，不是临时 URL
    ///
    /// # 示例
    /// ```
    /// use media_manager_backend::services::cache::UrlDetector;
    ///
    /// let url1 = "https://example.com/image.jpg?validfrom=123&validto=456";
    /// assert!(UrlDetector::is_temporary_url(url1));
    ///
    /// let url2 = "https://example.com/image.jpg";
    /// assert!(!UrlDetector::is_temporary_url(url2));
    /// ```
    pub fn is_temporary_url(url: &str) -> bool {
        // 使用静态正则表达式，避免重复编译
        static TEMP_URL_REGEX: OnceLock<Regex> = OnceLock::new();
        
        let regex = TEMP_URL_REGEX.get_or_init(|| {
            // 匹配 URL 参数中的时效参数
            // 模式：(validfrom|validto|expires|exp|signature|sig|token)=
            Regex::new(r"[?&](validfrom|validto|expires|exp|signature|sig|token)=")
                .expect("临时 URL 正则表达式编译失败")
        });

        regex.is_match(url)
    }

    /// 批量检测媒体数据中的所有 URL
    ///
    /// 检查媒体数据中的所有 URL 字段，判断是否包含临时 URL
    ///
    /// # 参数
    /// - `urls`: URL 字符串切片
    ///
    /// # 返回值
    /// - `true`: 至少有一个 URL 是临时 URL
    /// - `false`: 所有 URL 都不是临时 URL
    ///
    /// # 示例
    /// ```
    /// use media_manager_backend::services::cache::UrlDetector;
    ///
    /// let urls = vec![
    ///     "https://example.com/image1.jpg",
    ///     "https://example.com/image2.jpg?validfrom=123&validto=456",
    /// ];
    /// assert!(UrlDetector::detect_temporary_urls(&urls));
    /// ```
    pub fn detect_temporary_urls(urls: &[&str]) -> bool {
        urls.iter().any(|url| Self::is_temporary_url(url))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_temporary_url_with_validfrom_validto() {
        // MatureNL 风格的临时 URL
        let url = "https://s.cdn.mature.nl/update_support/2/16151/tl_hard.jpg?validfrom=1769524082&validto=1769531282&h=xxx";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_temporary_url_with_expires() {
        let url = "https://example.com/image.jpg?expires=1234567890";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_temporary_url_with_exp() {
        let url = "https://example.com/image.jpg?exp=1234567890";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_temporary_url_with_signature() {
        let url = "https://example.com/image.jpg?signature=abc123";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_temporary_url_with_sig() {
        let url = "https://example.com/image.jpg?sig=abc123";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_temporary_url_with_token() {
        let url = "https://example.com/image.jpg?token=abc123";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_temporary_url_with_multiple_params() {
        let url = "https://example.com/image.jpg?width=100&validfrom=123&height=200";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_not_temporary_url() {
        let url = "https://example.com/image.jpg";
        assert!(!UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_not_temporary_url_with_other_params() {
        let url = "https://example.com/image.jpg?width=100&height=200&quality=high";
        assert!(!UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_not_temporary_url_empty_string() {
        let url = "";
        assert!(!UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_is_not_temporary_url_no_query_params() {
        let url = "https://example.com/path/to/image.jpg";
        assert!(!UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_detect_temporary_urls_with_one_temporary() {
        let urls = vec![
            "https://example.com/image1.jpg",
            "https://example.com/image2.jpg?validfrom=123&validto=456",
            "https://example.com/image3.jpg",
        ];
        assert!(UrlDetector::detect_temporary_urls(&urls));
    }

    #[test]
    fn test_detect_temporary_urls_with_all_temporary() {
        let urls = vec![
            "https://example.com/image1.jpg?expires=123",
            "https://example.com/image2.jpg?token=abc",
            "https://example.com/image3.jpg?sig=xyz",
        ];
        assert!(UrlDetector::detect_temporary_urls(&urls));
    }

    #[test]
    fn test_detect_temporary_urls_with_none_temporary() {
        let urls = vec![
            "https://example.com/image1.jpg",
            "https://example.com/image2.jpg?width=100",
            "https://example.com/image3.jpg?quality=high",
        ];
        assert!(!UrlDetector::detect_temporary_urls(&urls));
    }

    #[test]
    fn test_detect_temporary_urls_empty_list() {
        let urls: Vec<&str> = vec![];
        assert!(!UrlDetector::detect_temporary_urls(&urls));
    }

    #[test]
    fn test_case_sensitivity() {
        // 参数名应该是大小写敏感的（小写）
        let url_lowercase = "https://example.com/image.jpg?validfrom=123";
        let url_uppercase = "https://example.com/image.jpg?VALIDFROM=123";
        
        assert!(UrlDetector::is_temporary_url(url_lowercase));
        // 大写参数不应该被识别为临时 URL（根据规范，参数名是小写）
        assert!(!UrlDetector::is_temporary_url(url_uppercase));
    }

    #[test]
    fn test_url_with_fragment() {
        let url = "https://example.com/image.jpg?validfrom=123#section";
        assert!(UrlDetector::is_temporary_url(url));
    }

    #[test]
    fn test_url_with_ampersand_separator() {
        let url = "https://example.com/image.jpg?param1=value1&expires=123&param2=value2";
        assert!(UrlDetector::is_temporary_url(url));
    }
}
