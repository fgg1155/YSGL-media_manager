use axum::{
    extract::Query,
    http::StatusCode,
    response::Response,
};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct ImageProxyParams {
    pub url: String,
}

#[derive(Debug, Deserialize)]
pub struct VideoProxyParams {
    pub url: String,
}

#[derive(Debug, Deserialize)]
pub struct HlsProxyParams {
    pub url: String,
}

/// 图片代理 - 解决 CORS 和防盗链问题
pub async fn proxy_image(
    Query(params): Query<ImageProxyParams>,
) -> Result<Response, StatusCode> {
    let url = params.url;
    
    // 验证 URL 是否合法
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // 构建请求客户端
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 发送请求，添加常见的浏览器 headers 来绕过防盗链
    let response = client
        .get(&url)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        .header("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
        .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        .header("Referer", extract_origin(&url))
        .send()
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch image: {}", e);
            StatusCode::BAD_GATEWAY
        })?;
    
    if !response.status().is_success() {
        tracing::error!("Image fetch failed with status: {}", response.status());
        return Err(StatusCode::BAD_GATEWAY);
    }
    
    // 获取 Content-Type
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("image/jpeg")
        .to_string();
    
    // 获取图片数据
    let bytes = response
        .bytes()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 构建响应
    let response = Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", content_type)
        .header("Cache-Control", "public, max-age=86400") // 缓存 1 天
        .header("Access-Control-Allow-Origin", "*")
        .body(axum::body::Body::from(bytes))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    Ok(response)
}

/// 视频代理 - 解决 CORS 和防盗链问题
pub async fn proxy_video(
    Query(params): Query<VideoProxyParams>,
) -> Result<Response, StatusCode> {
    let url = params.url;
    
    // 验证 URL 是否合法
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // 构建请求客户端
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60)) // 视频需要更长的超时时间
        .build()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 发送请求，添加常见的浏览器 headers 来绕过防盗链
    let response = client
        .get(&url)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        .header("Accept", "video/webm,video/ogg,video/*;q=0.9,application/ogg;q=0.7,audio/*;q=0.6,*/*;q=0.5")
        .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        .header("Referer", extract_origin(&url))
        .header("Range", "bytes=0-") // 支持视频流式传输
        .send()
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch video: {}", e);
            StatusCode::BAD_GATEWAY
        })?;
    
    // 使用 u16 比较状态码
    if !response.status().is_success() && response.status().as_u16() != 206 {
        tracing::error!("Video fetch failed with status: {}", response.status());
        return Err(StatusCode::BAD_GATEWAY);
    }
    
    // 获取 Content-Type
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("video/mp4")
        .to_string();
    
    // 获取视频数据
    let bytes = response
        .bytes()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 构建响应
    let response = Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", content_type)
        .header("Accept-Ranges", "bytes") // 支持范围请求
        .header("Cache-Control", "public, max-age=3600") // 缓存 1 小时
        .header("Access-Control-Allow-Origin", "*")
        .body(axum::body::Body::from(bytes))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    Ok(response)
}

/// 从 URL 提取 origin 作为 Referer
fn extract_origin(url: &str) -> String {
    if let Ok(parsed) = url::Url::parse(url) {
        format!("{}://{}/", parsed.scheme(), parsed.host_str().unwrap_or(""))
    } else {
        url.to_string()
    }
}

/// HLS 代理 - 代理 M3U8 播放列表
pub async fn proxy_hls(
    Query(params): Query<HlsProxyParams>,
) -> Result<Response, StatusCode> {
    let url = params.url;
    
    // 验证 URL 是否合法
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // 构建请求客户端
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 发送请求
    let response = client
        .get(&url)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .header("Accept", "*/*")
        .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        .header("Referer", extract_origin(&url))
        .header("Origin", extract_origin(&url).trim_end_matches('/'))
        .send()
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch HLS playlist: {}", e);
            StatusCode::BAD_GATEWAY
        })?;
    
    if !response.status().is_success() {
        tracing::error!("HLS fetch failed with status: {}", response.status());
        return Err(StatusCode::BAD_GATEWAY);
    }
    
    // 获取 M3U8 内容
    let content = response
        .text()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 解析并重写 M3U8 内容中的 URL
    let base_url = extract_base_url(&url);
    let rewritten_content = rewrite_m3u8_urls(&content, &base_url, &url);
    
    // 构建响应
    let response = Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/vnd.apple.mpegurl")
        .header("Access-Control-Allow-Origin", "*")
        .header("Cache-Control", "no-cache")
        .body(axum::body::Body::from(rewritten_content))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    Ok(response)
}

/// HLS 分片代理 - 代理 TS 分片文件
pub async fn proxy_hls_segment(
    Query(params): Query<HlsProxyParams>,
) -> Result<Response, StatusCode> {
    let url = params.url;
    
    // 验证 URL 是否合法
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // 构建请求客户端
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 发送请求
    let response = client
        .get(&url)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .header("Accept", "*/*")
        .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        .header("Referer", extract_origin(&url))
        .header("Origin", extract_origin(&url).trim_end_matches('/'))
        .send()
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch HLS segment: {}", e);
            StatusCode::BAD_GATEWAY
        })?;
    
    if !response.status().is_success() {
        tracing::error!("HLS segment fetch failed with status: {}", response.status());
        return Err(StatusCode::BAD_GATEWAY);
    }
    
    // 获取 Content-Type
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("video/mp2t")
        .to_string();
    
    // 获取分片数据
    let bytes = response
        .bytes()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 构建响应
    let response = Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", content_type)
        .header("Access-Control-Allow-Origin", "*")
        .header("Cache-Control", "public, max-age=3600")
        .body(axum::body::Body::from(bytes))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    Ok(response)
}

/// 重写 M3U8 文件中的 URL，使其通过代理访问
fn rewrite_m3u8_urls(content: &str, base_url: &str, original_url: &str) -> String {
    let mut result = String::new();
    
    for line in content.lines() {
        let trimmed = line.trim();
        
        // 跳过注释和空行
        if trimmed.starts_with('#') || trimmed.is_empty() {
            result.push_str(line);
            result.push('\n');
            continue;
        }
        
        // 处理 URL 行
        let absolute_url = if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
            // 已经是绝对 URL
            trimmed.to_string()
        } else if trimmed.starts_with('/') {
            // 绝对路径
            let origin = extract_origin(original_url);
            let origin = origin.trim_end_matches('/');
            format!("{}{}", origin, trimmed)
        } else {
            // 相对路径
            format!("{}/{}", base_url.trim_end_matches('/'), trimmed)
        };
        
        // 判断是 M3U8 还是 TS 分片
        // 提取文件路径部分（去掉查询参数和片段）
        let path_only = absolute_url
            .split('?').next().unwrap_or(&absolute_url)
            .split('#').next().unwrap_or(&absolute_url);
        
        let is_m3u8 = path_only.ends_with(".m3u8");
        
        tracing::info!("URL: {} -> path: {} -> is_m3u8: {}", trimmed, path_only, is_m3u8);
        
        if is_m3u8 {
            // 子播放列表，通过 HLS 代理
            let proxy_url = format!("http://localhost:3000/api/proxy/hls?url={}", urlencoding::encode(&absolute_url));
            result.push_str(&proxy_url);
        } else {
            // TS 分片或其他文件，通过分片代理
            let proxy_url = format!("http://localhost:3000/api/proxy/hls/segment?url={}", urlencoding::encode(&absolute_url));
            result.push_str(&proxy_url);
        }
        
        result.push('\n');
    }
    
    result
}

/// 从 URL 提取基础 URL（去掉文件名和查询参数）
fn extract_base_url(url: &str) -> String {
    // 先去掉查询参数和片段
    let url_without_query = url.split('?').next().unwrap_or(url);
    let url_without_fragment = url_without_query.split('#').next().unwrap_or(url_without_query);
    
    // 再去掉文件名
    if let Some(last_slash) = url_without_fragment.rfind('/') {
        url_without_fragment[..last_slash].to_string()
    } else {
        url_without_fragment.to_string()
    }
}
