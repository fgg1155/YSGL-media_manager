// 缓存模块错误类型定义
//
// 定义了缓存操作中可能出现的各种错误类型

use std::path::PathBuf;
use thiserror::Error;

/// 缓存操作的统一错误类型
#[derive(Debug, Error)]
pub enum CacheError {
    #[error("下载错误: {0}")]
    Download(#[from] DownloadError),

    #[error("转换错误: {0}")]
    Conversion(#[from] ConversionError),

    #[error("文件系统错误: {0}")]
    FileSystem(#[from] FileSystemError),

    #[error("配置错误: {0}")]
    Config(String),

    #[error("数据库错误: {0}")]
    Database(String),

    #[error("IO 错误: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON 序列化错误: {0}")]
    Json(#[from] serde_json::Error),
}

/// 下载相关错误
#[derive(Debug, Error)]
pub enum DownloadError {
    #[error("网络错误: {0}")]
    NetworkError(String),

    #[error("下载超时")]
    Timeout,

    #[error("无效的 URL: {0}")]
    InvalidUrl(String),

    #[error("HTTP 错误: 状态码 {0}")]
    HttpError(u16),

    #[error("请求错误: {0}")]
    RequestError(String),
}

/// 图片转换相关错误
#[derive(Debug, Error)]
pub enum ConversionError {
    #[error("不支持的图片格式: {0}")]
    UnsupportedFormat(String),

    #[error("图片数据损坏")]
    CorruptedData,

    #[error("转换失败: {0}")]
    ConversionFailed(String),

    #[error("图片解码失败: {0}")]
    DecodeFailed(String),

    #[error("图片编码失败: {0}")]
    EncodeFailed(String),
}

/// 文件系统相关错误
#[derive(Debug, Error)]
pub enum FileSystemError {
    #[error("磁盘空间不足")]
    DiskFull,

    #[error("权限被拒绝")]
    PermissionDenied,

    #[error("路径不存在: {0}")]
    PathNotFound(PathBuf),

    #[error("IO 错误: {0}")]
    IoError(#[from] std::io::Error),

    #[error("创建目录失败: {0}")]
    CreateDirFailed(String),

    #[error("写入文件失败: {0}")]
    WriteFileFailed(String),
}

// 实现从 reqwest::Error 到 DownloadError 的转换
impl From<reqwest::Error> for DownloadError {
    fn from(err: reqwest::Error) -> Self {
        if err.is_timeout() {
            DownloadError::Timeout
        } else if err.is_status() {
            if let Some(status) = err.status() {
                DownloadError::HttpError(status.as_u16())
            } else {
                DownloadError::NetworkError(err.to_string())
            }
        } else {
            DownloadError::NetworkError(err.to_string())
        }
    }
}

// 实现从 reqwest::Error 到 CacheError 的转换
impl From<reqwest::Error> for CacheError {
    fn from(err: reqwest::Error) -> Self {
        CacheError::Download(DownloadError::from(err))
    }
}
