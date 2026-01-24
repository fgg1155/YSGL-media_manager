use axum::{
    extract::{Path, State, Query},
    http::{header, StatusCode, HeaderMap},
    response::{IntoResponse, Response},
    body::Body,
};
use tokio::fs::File;
use tokio::io::AsyncReadExt;
use tokio_util::io::ReaderStream;
use std::path::PathBuf;
use sha2::{Sha256, Digest};

use crate::database::repository::DatabaseRepository;
use super::AppState;

/// 获取媒体缩略图
pub async fn get_media_thumbnail(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Result<Response, StatusCode> {
    // 从数据库获取媒体信息
    let _media = state.database.repository()
        .get_media_by_id(&id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    // 获取关联的文件
    let files = state.database.repository()
        .get_media_files(&id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if files.is_empty() {
        return Err(StatusCode::NOT_FOUND);
    }

    // 获取文件索引参数（默认为 0）
    let file_index = params.get("index")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(0);

    // 确保索引有效
    if file_index >= files.len() {
        return Err(StatusCode::BAD_REQUEST);
    }

    // 使用指定索引的文件生成缩略图
    let video_path = PathBuf::from(&files[file_index].file_path);
    
    if !video_path.exists() {
        return Err(StatusCode::NOT_FOUND);
    }

    // 生成缩略图（使用缓存）
    match generate_thumbnail_cached(&video_path, &id, file_index).await {
        Ok(thumbnail_data) => {
            Ok((
                [(header::CONTENT_TYPE, "image/jpeg")],
                thumbnail_data,
            ).into_response())
        }
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// 流式传输视频
pub async fn stream_video(
    State(state): State<AppState>,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> Result<Response, StatusCode> {
    // 从数据库获取媒体信息
    let _media = state.database.repository()
        .get_media_by_id(&id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    // 获取关联的文件
    let files = state.database.repository()
        .get_media_files(&id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if files.is_empty() {
        return Err(StatusCode::NOT_FOUND);
    }

    // 使用第一个文件
    let video_path = PathBuf::from(&files[0].file_path);
    
    if !video_path.exists() {
        return Err(StatusCode::NOT_FOUND);
    }

    // 获取文件大小
    let file_size = tokio::fs::metadata(&video_path)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .len();

    // 检查 Range 请求头（用于视频拖动）
    let range = headers.get(header::RANGE);
    
    if let Some(range_value) = range {
        // 处理 Range 请求
        if let Ok(range_str) = range_value.to_str() {
            if let Some(range_spec) = parse_range(range_str, file_size) {
                return stream_range(&video_path, range_spec, file_size).await;
            }
        }
    }

    // 完整文件流式传输
    stream_full_file(&video_path, file_size).await
}

/// 获取缩略图缓存目录
fn get_thumbnail_cache_dir() -> Result<PathBuf, std::io::Error> {
    // 优先使用环境变量 CACHE_DIR，如果没有设置则使用当前目录
    let base_dir = std::env::var("CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // 在开发模式下，使用 Cargo.toml 所在目录（项目根目录）
            // 在生产模式下，使用当前工作目录
            if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
                PathBuf::from(manifest_dir)
            } else {
                std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
            }
        });
    
    let cache_dir = base_dir
        .join("cache")
        .join("thumbnails");

    // 确保缓存目录存在
    if !cache_dir.exists() {
        std::fs::create_dir_all(&cache_dir)?;
    }

    tracing::info!("缩略图缓存目录: {}", cache_dir.display());

    Ok(cache_dir)
}

/// 生成缓存文件名（基于视频路径和文件索引的哈希）
fn generate_cache_filename(video_path: &PathBuf, media_id: &str, file_index: usize) -> String {
    // 使用视频路径 + media_id + file_index 生成唯一的哈希
    let mut hasher = Sha256::new();
    hasher.update(video_path.to_string_lossy().as_bytes());
    hasher.update(media_id.as_bytes());
    hasher.update(file_index.to_string().as_bytes());
    let hash = hasher.finalize();
    
    // 使用哈希的前32个字符作为文件名，然后添加 .jpg 扩展名
    let hash_str: String = format!("{:x}", hash).chars().take(32).collect();
    format!("{}.jpg", hash_str)
}

/// 生成视频缩略图（带缓存）
async fn generate_thumbnail_cached(
    video_path: &PathBuf,
    media_id: &str,
    file_index: usize,
) -> Result<Vec<u8>, std::io::Error> {
    // 获取缓存目录
    let cache_dir = get_thumbnail_cache_dir()?;
    tracing::info!("使用缓存目录: {}", cache_dir.display());
    
    // 生成缓存文件名
    let cache_filename = generate_cache_filename(video_path, media_id, file_index);
    let cache_path = cache_dir.join(&cache_filename);
    
    tracing::info!("缓存文件路径: {}", cache_path.display());
    
    // 检查缓存是否存在
    if cache_path.exists() {
        tracing::info!("使用缓存的缩略图: {}", cache_path.display());
        // 读取并返回缓存的缩略图
        return tokio::fs::read(&cache_path).await;
    }
    
    tracing::info!("缓存不存在，开始生成新缩略图");
    
    // 缓存不存在，生成新的缩略图
    use tokio::process::Command;

    // 使用 FFmpeg 生成缩略图
    let video_path_str = video_path.to_str()
        .ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Invalid video path encoding"
        ))?;
    
    let cache_path_str = cache_path.to_str()
        .ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Invalid cache path encoding"
        ))?;
    
    tracing::info!("FFmpeg 命令: ffmpeg -ss 00:00:02 -i {} -vframes 1 -update 1 -q:v 2 -y {}", 
        video_path_str, cache_path_str);
    
    let output = Command::new("ffmpeg")
        .args(&[
            "-ss", "00:00:02",           // 从第2秒开始
            "-i", video_path_str,
            "-vframes", "1",              // 只提取一帧
            "-update", "1",               // 允许输出单张图片
            // 不缩放，保持原始分辨率
            "-q:v", "2",                  // JPEG 质量（高质量）
            "-y",                         // 覆盖输出文件
            cache_path_str,
        ])
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        tracing::error!("FFmpeg 失败: {}", stderr);
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("FFmpeg failed to generate thumbnail: {}", stderr),
        ));
    }

    tracing::info!("FFmpeg 成功生成缩略图");

    // 读取缩略图数据
    let thumbnail_data = tokio::fs::read(&cache_path).await?;
    
    tracing::info!("成功读取缩略图数据，大小: {} bytes", thumbnail_data.len());

    Ok(thumbnail_data)
}

/// 生成视频缩略图（旧版本，不使用缓存）
#[allow(dead_code)]
async fn generate_thumbnail(video_path: &PathBuf) -> Result<Vec<u8>, std::io::Error> {
    use tokio::process::Command;

    // 创建临时文件
    let temp_dir = std::env::temp_dir();
    let thumbnail_path = temp_dir.join(format!("thumb_{}.jpg", uuid::Uuid::new_v4()));

    // 使用 FFmpeg 生成缩略图
    let video_path_str = video_path.to_str()
        .ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Invalid video path encoding"
        ))?;
    
    let thumbnail_path_str = thumbnail_path.to_str()
        .ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Invalid thumbnail path encoding"
        ))?;
    
    let output = Command::new("ffmpeg")
        .args(&[
            "-ss", "00:00:02",           // 从第2秒开始
            "-i", video_path_str,
            "-vframes", "1",              // 只提取一帧
            // 不缩放，保持原始分辨率
            "-q:v", "2",                  // JPEG 质量（高质量）
            "-y",                         // 覆盖输出文件
            thumbnail_path_str,
        ])
        .output()
        .await?;

    if !output.status.success() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "FFmpeg failed to generate thumbnail",
        ));
    }

    // 读取缩略图数据
    let thumbnail_data = tokio::fs::read(&thumbnail_path).await?;

    // 删除临时文件
    let _ = tokio::fs::remove_file(&thumbnail_path).await;

    Ok(thumbnail_data)
}

/// 解析 Range 请求头
fn parse_range(range_str: &str, file_size: u64) -> Option<(u64, u64)> {
    // 格式: "bytes=start-end"
    if !range_str.starts_with("bytes=") {
        return None;
    }

    let range_part = &range_str[6..];
    let parts: Vec<&str> = range_part.split('-').collect();

    if parts.len() != 2 {
        return None;
    }

    let start = parts[0].parse::<u64>().ok()?;
    let end = if parts[1].is_empty() {
        file_size - 1
    } else {
        parts[1].parse::<u64>().ok()?
    };

    Some((start, end))
}

/// 流式传输指定范围的文件
async fn stream_range(
    path: &PathBuf,
    range: (u64, u64),
    file_size: u64,
) -> Result<Response, StatusCode> {
    let (start, end) = range;
    let content_length = end - start + 1;

    let mut file = File::open(path)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // 跳到起始位置
    use tokio::io::AsyncSeekExt;
    file.seek(std::io::SeekFrom::Start(start))
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // 创建限制读取长度的流
    let limited_file = file.take(content_length);
    let stream = ReaderStream::new(limited_file);
    let body = Body::from_stream(stream);

    Ok((
        StatusCode::PARTIAL_CONTENT,
        [
            (header::CONTENT_TYPE, "video/mp4"),
            (header::CONTENT_LENGTH, content_length.to_string().as_str()),
            (header::CONTENT_RANGE, format!("bytes {}-{}/{}", start, end, file_size).as_str()),
            (header::ACCEPT_RANGES, "bytes"),
        ],
        body,
    ).into_response())
}

/// 流式传输完整文件
async fn stream_full_file(
    path: &PathBuf,
    file_size: u64,
) -> Result<Response, StatusCode> {
    let file = File::open(path)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let stream = ReaderStream::new(file);
    let body = Body::from_stream(stream);

    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, "video/mp4"),
            (header::CONTENT_LENGTH, file_size.to_string().as_str()),
            (header::ACCEPT_RANGES, "bytes"),
        ],
        body,
    ).into_response())
}
