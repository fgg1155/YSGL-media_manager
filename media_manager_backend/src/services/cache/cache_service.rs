// 缓存服务 - 协调所有缓存组件，提供统一的缓存管理接口
//
// 本模块是缓存功能的核心服务，负责：
// - 检测临时 URL 并自动开启缓存
// - 执行缓存下载和转换
// - 处理媒体保存时的缓存逻辑
// - 提供缓存统计和清理功能

use crate::services::cache::{
    CacheError, CacheField, ConfigManager, ImageDownloader, UrlDetector, VideoSelector,
    PreviewVideoUrl, DownloadTask, CachePath,
};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Sqlite};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::fs;
use tracing::{debug, error, info, warn};

/// 缓存服务
///
/// 协调所有缓存组件，提供统一的缓存管理接口
#[derive(Clone)]
pub struct CacheService {
    /// 配置管理器
    config_manager: Arc<ConfigManager>,

    /// 图片下载器
    downloader: Arc<ImageDownloader>,

    /// 视频选择器
    video_selector: VideoSelector,

    /// URL 检测器
    url_detector: UrlDetector,

    /// 数据库连接池
    db_pool: Pool<Sqlite>,
}

impl CacheService {
    /// 创建新的缓存服务
    ///
    /// # 参数
    /// - `cache_dir`: 缓存根目录路径（相对或绝对路径）
    /// - `db_pool`: 数据库连接池
    ///
    /// # 返回
    /// - `Result<Self, CacheError>`: 缓存服务实例或错误
    pub async fn new(
        cache_dir: PathBuf,
        db_pool: Pool<Sqlite>,
    ) -> Result<Self, CacheError> {
        // 支持环境变量配置路径，默认使用 None（由 ConfigManager 使用默认路径）
        let config_path = std::env::var("CACHE_CONFIG_PATH")
            .ok()
            .map(PathBuf::from);
        
        let config_manager = Arc::new(ConfigManager::load(config_path).await?);

        // 创建图片下载器
        let downloader = Arc::new(ImageDownloader::new(cache_dir).await?);

        Ok(Self {
            config_manager,
            downloader,
            video_selector: VideoSelector,
            url_detector: UrlDetector,
            db_pool,
        })
    }

    /// 处理媒体保存时的缓存逻辑
    ///
    /// 这是缓存服务的主入口，在媒体保存成功后调用。
    /// 包含完整的缓存流程：检测临时 URL -> 自动开启缓存 -> 执行缓存下载
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    /// - `media_data`: 媒体数据（包含所有 URL）
    /// - `scraper_name`: 刮削器名称
    ///
    /// # 返回
    /// - `Ok(())`: 缓存处理成功（或不需要缓存）
    /// - `Err(CacheError)`: 缓存处理失败
    ///
    /// # 行为
    /// - 异步执行，不阻塞媒体保存流程
    /// - 先检测并自动开启缓存
    /// - 再判断是否需要缓存
    /// - 最后执行缓存下载
    pub async fn handle_media_save(
        &self,
        media_id: &str,
        media_data: &MediaData,
        scraper_name: &str,
    ) -> Result<(), CacheError> {
        info!("开始处理媒体缓存: media_id={}, scraper={}", media_id, scraper_name);

        // 1. 检测并自动开启缓存
        self.check_and_auto_enable(media_data, scraper_name).await?;

        // 2. 判断是否应该缓存
        if !self.config_manager.should_cache(scraper_name).await {
            debug!("刮削器 {} 未开启缓存，跳过", scraper_name);
            return Ok(());
        }

        // 3. 异步执行缓存下载（不阻塞主流程）
        let service = self.clone_for_task();
        let media_id = media_id.to_string();
        let media_data = media_data.clone();
        let scraper_name = scraper_name.to_string();

        tokio::spawn(async move {
            if let Err(e) = service.execute_cache(&media_id, &media_data, &scraper_name).await {
                error!("缓存执行失败: media_id={}, error={:?}", media_id, e);
            }
        });

        Ok(())
    }

    /// 检测并自动开启缓存
    ///
    /// 检测媒体数据中的所有 URL，如果发现临时 URL 且该刮削器的缓存未开启，
    /// 则自动开启缓存功能。
    ///
    /// # 参数
    /// - `media_data`: 媒体数据
    /// - `scraper_name`: 刮削器名称
    ///
    /// # 返回
    /// - `Ok(())`: 检测完成（可能已自动开启缓存）
    /// - `Err(CacheError)`: 检测或开启失败
    async fn check_and_auto_enable(
        &self,
        media_data: &MediaData,
        scraper_name: &str,
    ) -> Result<(), CacheError> {
        // 收集所有 URL
        let mut urls = Vec::new();

        if let Some(ref poster_url) = media_data.poster_url {
            urls.push(poster_url.as_str());
        }

        for backdrop_url in &media_data.backdrop_urls {
            urls.push(backdrop_url.as_str());
        }

        for preview_url in &media_data.preview_urls {
            urls.push(preview_url.as_str());
        }

        for video_url in &media_data.preview_video_urls {
            urls.push(video_url.url.as_str());
        }

        // 检测是否包含临时 URL
        if UrlDetector::detect_temporary_urls(&urls) {
            debug!("检测到刮削器 {} 返回临时 URL", scraper_name);

            // 自动开启缓存
            self.config_manager.auto_enable_cache(scraper_name).await?;
        }

        Ok(())
    }

    /// 执行缓存下载
    ///
    /// 根据配置下载并缓存图片和视频，下载成功后更新数据库中的 URL。
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    /// - `media_data`: 媒体数据
    /// - `scraper_name`: 刮削器名称
    ///
    /// # 返回
    /// - `Ok(())`: 缓存执行成功
    /// - `Err(CacheError)`: 缓存执行失败
    async fn execute_cache(
        &self,
        media_id: &str,
        media_data: &MediaData,
        scraper_name: &str,
    ) -> Result<(), CacheError> {
        info!("开始执行缓存下载: media_id={}", media_id);

        // 获取刮削器配置
        let config = self.config_manager.get_config().await;
        let scraper_config = config.scrapers.get(scraper_name);

        if scraper_config.is_none() {
            debug!("刮削器 {} 无配置，使用默认配置", scraper_name);
            // 默认缓存 poster 和 backdrop
            return self.execute_cache_default(media_id, media_data).await;
        }

        let scraper_config = scraper_config.unwrap();
        let cache_fields = &scraper_config.cache_fields;

        // 构建下载任务列表
        let mut tasks = Vec::new();

        // 1. 处理 poster
        if cache_fields.contains(&CacheField::Poster) {
            if let Some(ref poster_url) = media_data.poster_url {
                let save_path = CachePath::image_path(media_id, "poster", None);
                tasks.push(DownloadTask::new(
                    "poster".to_string(),
                    None,
                    poster_url.clone(),
                    save_path,
                ));
            }
        }

        // 2. 处理 backdrop
        if cache_fields.contains(&CacheField::Backdrop) {
            for (index, backdrop_url) in media_data.backdrop_urls.iter().enumerate() {
                let save_path = CachePath::image_path(media_id, "backdrop", Some(index));
                tasks.push(DownloadTask::new(
                    format!("backdrop_{}", index),
                    Some(index),
                    backdrop_url.clone(),
                    save_path,
                ));
            }
        }

        // 3. 处理 preview
        if cache_fields.contains(&CacheField::Preview) {
            for (index, preview_url) in media_data.preview_urls.iter().enumerate() {
                let save_path = CachePath::image_path(media_id, "preview", Some(index));
                tasks.push(DownloadTask::new(
                    format!("preview_{}", index),
                    Some(index),
                    preview_url.clone(),
                    save_path,
                ));
            }
        }

        // 4. 批量下载图片
        if !tasks.is_empty() {
            let results = self.downloader.download_batch(tasks).await;
            self.update_image_urls(media_id, results).await?;
        }

        // 5. 处理 preview_video
        if cache_fields.contains(&CacheField::PreviewVideo) {
            self.cache_preview_video(media_id, media_data).await?;
        }

        info!("缓存下载完成: media_id={}", media_id);
        Ok(())
    }

    /// 执行默认缓存（poster + backdrop）
    async fn execute_cache_default(
        &self,
        media_id: &str,
        media_data: &MediaData,
    ) -> Result<(), CacheError> {
        let mut tasks = Vec::new();

        // 缓存 poster
        if let Some(ref poster_url) = media_data.poster_url {
            let save_path = CachePath::image_path(media_id, "poster", None);
            tasks.push(DownloadTask::new(
                "poster".to_string(),
                None,
                poster_url.clone(),
                save_path,
            ));
        }

        // 缓存 backdrop
        for (index, backdrop_url) in media_data.backdrop_urls.iter().enumerate() {
            let save_path = CachePath::image_path(media_id, "backdrop", Some(index));
            tasks.push(DownloadTask::new(
                format!("backdrop_{}", index),
                Some(index),
                backdrop_url.clone(),
                save_path,
            ));
        }

        if !tasks.is_empty() {
            let results = self.downloader.download_batch(tasks).await;
            self.update_image_urls(media_id, results).await?;
        }

        Ok(())
    }

    /// 缓存预览视频（智能选择最高清晰度）
    async fn cache_preview_video(
        &self,
        media_id: &str,
        media_data: &MediaData,
    ) -> Result<(), CacheError> {
        if media_data.preview_video_urls.is_empty() {
            return Ok(());
        }

        // 选择最高清晰度的视频
        let best_video = VideoSelector::select_best_quality(&media_data.preview_video_urls);

        if let Some(video) = best_video {
            info!(
                "选择最高清晰度视频: media_id={}, quality={}",
                media_id, video.quality
            );

            // 下载视频
            let save_path = CachePath::video_path(media_id, "preview_video");
            match self.downloader.download_video(&video.url, save_path).await {
                Ok(local_path) => {
                    // 更新数据库：只保留本地路径，删除其他 URL
                    self.update_video_url(media_id, &video.quality, &local_path).await?;
                    info!("视频缓存成功: media_id={}, path={}", media_id, local_path);
                }
                Err(e) => {
                    warn!("视频下载失败，保留原始 URL: media_id={}, error={:?}", media_id, e);
                    // 下载失败，保留原始 URL（降级方案）
                }
            }
        }

        Ok(())
    }

    /// 更新图片 URL 到数据库
    async fn update_image_urls(
        &self,
        media_id: &str,
        results: Vec<crate::services::cache::image_downloader::DownloadResult>,
    ) -> Result<(), CacheError> {
        for result in results {
            match result.result {
                Ok(local_path) => {
                    // 根据字段名称更新对应的数据库字段
                    if result.field_name == "poster" {
                        self.update_poster_url(media_id, &local_path).await?;
                    } else if result.field_name.starts_with("backdrop_") {
                        if let Some(index) = result.index {
                            self.update_backdrop_url(media_id, index, &local_path).await?;
                        }
                    } else if result.field_name.starts_with("preview_") {
                        if let Some(index) = result.index {
                            self.update_preview_url(media_id, index, &local_path).await?;
                        }
                    }
                }
                Err(e) => {
                    warn!(
                        "图片下载失败，保留原始 URL: field={}, error={:?}",
                        result.field_name, e
                    );
                    // 下载失败，保留原始 URL（降级方案）
                }
            }
        }

        Ok(())
    }

    /// 更新 poster URL
    async fn update_poster_url(&self, media_id: &str, local_path: &str) -> Result<(), CacheError> {
        sqlx::query("UPDATE media SET poster_url = ? WHERE id = ?")
            .bind(local_path)
            .bind(media_id)
            .execute(&self.db_pool)
            .await
            .map_err(|e| CacheError::Database(format!("更新 poster URL 失败: {}", e)))?;

        debug!("已更新 poster URL: media_id={}, path={}", media_id, local_path);
        Ok(())
    }

    /// 更新 backdrop URL
    async fn update_backdrop_url(
        &self,
        media_id: &str,
        index: usize,
        local_path: &str,
    ) -> Result<(), CacheError> {
        // 获取当前的 backdrop_urls
        let row: (String,) = sqlx::query_as("SELECT backdrop_urls FROM media WHERE id = ?")
            .bind(media_id)
            .fetch_one(&self.db_pool)
            .await
            .map_err(|e| CacheError::Database(format!("查询 backdrop_urls 失败: {}", e)))?;

        let mut backdrop_urls: Vec<String> = serde_json::from_str(&row.0)
            .unwrap_or_default();

        // 更新指定索引的 URL
        if index < backdrop_urls.len() {
            backdrop_urls[index] = local_path.to_string();

            // 保存回数据库
            let json = serde_json::to_string(&backdrop_urls)
                .map_err(|e| CacheError::Config(format!("序列化 backdrop_urls 失败: {}", e)))?;

            sqlx::query("UPDATE media SET backdrop_urls = ? WHERE id = ?")
                .bind(json)
                .bind(media_id)
                .execute(&self.db_pool)
                .await
                .map_err(|e| CacheError::Database(format!("更新 backdrop_urls 失败: {}", e)))?;

            debug!("已更新 backdrop URL: media_id={}, index={}, path={}", media_id, index, local_path);
        }

        Ok(())
    }

    /// 更新 preview URL
    async fn update_preview_url(
        &self,
        media_id: &str,
        index: usize,
        local_path: &str,
    ) -> Result<(), CacheError> {
        // 获取当前的 preview_urls
        let row: (String,) = sqlx::query_as("SELECT preview_urls FROM media WHERE id = ?")
            .bind(media_id)
            .fetch_one(&self.db_pool)
            .await
            .map_err(|e| CacheError::Database(format!("查询 preview_urls 失败: {}", e)))?;

        let mut preview_urls: Vec<String> = serde_json::from_str(&row.0)
            .unwrap_or_default();

        // 更新指定索引的 URL
        if index < preview_urls.len() {
            preview_urls[index] = local_path.to_string();

            // 保存回数据库
            let json = serde_json::to_string(&preview_urls)
                .map_err(|e| CacheError::Config(format!("序列化 preview_urls 失败: {}", e)))?;

            sqlx::query("UPDATE media SET preview_urls = ? WHERE id = ?")
                .bind(json)
                .bind(media_id)
                .execute(&self.db_pool)
                .await
                .map_err(|e| CacheError::Database(format!("更新 preview_urls 失败: {}", e)))?;

            debug!("已更新 preview URL: media_id={}, index={}, path={}", media_id, index, local_path);
        }

        Ok(())
    }

    /// 更新视频 URL（只保留最高清晰度的本地路径）
    async fn update_video_url(
        &self,
        media_id: &str,
        quality: &str,
        local_path: &str,
    ) -> Result<(), CacheError> {
        // 创建新的视频 URL 数组（只包含本地路径）
        let video_urls = vec![PreviewVideoUrl::new(
            quality.to_string(),
            local_path.to_string(),
        )];

        let json = serde_json::to_string(&video_urls)
            .map_err(|e| CacheError::Config(format!("序列化 preview_video_urls 失败: {}", e)))?;

        sqlx::query("UPDATE media SET preview_video_urls = ? WHERE id = ?")
            .bind(json)
            .bind(media_id)
            .execute(&self.db_pool)
            .await
            .map_err(|e| CacheError::Database(format!("更新 preview_video_urls 失败: {}", e)))?;

        debug!("已更新视频 URL: media_id={}, quality={}, path={}", media_id, quality, local_path);
        Ok(())
    }

    /// 克隆服务用于异步任务（内部方法）
    fn clone_for_task(&self) -> Self {
        Self {
            config_manager: Arc::clone(&self.config_manager),
            downloader: Arc::clone(&self.downloader),
            video_selector: VideoSelector,
            url_detector: UrlDetector,
            db_pool: self.db_pool.clone(),
        }
    }

    /// 获取配置管理器引用
    pub fn config_manager(&self) -> &Arc<ConfigManager> {
        &self.config_manager
    }

    /// 获取缓存统计
    ///
    /// 遍历缓存目录，计算文件大小和数量，按刮削器分组统计
    ///
    /// # 返回
    /// - `Ok(CacheStats)`: 缓存统计信息
    /// - `Err(CacheError)`: 统计失败
    ///
    /// # 实现细节
    /// - 遍历 `cache/images/media/` 和 `cache/videos/media/` 目录
    /// - 每个媒体 ID 对应一个子目录
    /// - 通过查询数据库获取媒体的刮削器名称
    /// - 按刮削器分组统计文件大小和数量
    pub async fn get_cache_stats(&self) -> Result<CacheStats, CacheError> {
        info!("开始统计缓存");

        let mut total_size: u64 = 0;
        let mut total_files: usize = 0;
        let mut by_scraper: HashMap<String, ScraperCacheStats> = HashMap::new();

        // 统计图片缓存
        let images_dir = CachePath::images_root().join("media");
        if images_dir.exists() {
            self.collect_cache_stats(&images_dir, &mut total_size, &mut total_files, &mut by_scraper)
                .await?;
        }

        // 统计视频缓存
        let videos_dir = CachePath::videos_root().join("media");
        if videos_dir.exists() {
            self.collect_cache_stats(&videos_dir, &mut total_size, &mut total_files, &mut by_scraper)
                .await?;
        }

        info!(
            "缓存统计完成: 总大小={} 字节, 总文件数={}, 刮削器数={}",
            total_size,
            total_files,
            by_scraper.len()
        );

        Ok(CacheStats {
            total_size,
            total_files,
            by_scraper,
        })
    }

    /// 收集缓存统计（内部方法）
    ///
    /// # 参数
    /// - `dir`: 要统计的目录（images/media 或 videos/media）
    /// - `total_size`: 累计总大小
    /// - `total_files`: 累计总文件数
    /// - `by_scraper`: 按刮削器分组的统计
    async fn collect_cache_stats(
        &self,
        dir: &PathBuf,
        total_size: &mut u64,
        total_files: &mut usize,
        by_scraper: &mut HashMap<String, ScraperCacheStats>,
    ) -> Result<(), CacheError> {
        let mut entries = fs::read_dir(dir).await.map_err(|e| {
            CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
        })?;

        while let Some(entry) = entries.next_entry().await.map_err(|e| {
            CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
        })? {
            let path = entry.path();

            // 跳过非目录
            if !path.is_dir() {
                continue;
            }

            // 获取媒体 ID（目录名）
            let media_id = match path.file_name().and_then(|n| n.to_str()) {
                Some(id) => id,
                None => continue,
            };

            // 查询数据库获取刮削器名称
            let scraper_name = match self.get_scraper_name_by_media_id(media_id).await {
                Ok(name) => name,
                Err(e) => {
                    warn!("无法获取媒体 {} 的刮削器名称: {:?}", media_id, e);
                    "unknown".to_string()
                }
            };

            // 统计该媒体的缓存文件
            let (dir_size, dir_files) = self.calculate_dir_size(&path).await?;

            *total_size += dir_size;
            *total_files += dir_files;

            // 更新刮削器统计
            let scraper_stats = by_scraper
                .entry(scraper_name)
                .or_insert_with(|| ScraperCacheStats {
                    size: 0,
                    files: 0,
                });

            scraper_stats.size += dir_size;
            scraper_stats.files += dir_files;
        }

        Ok(())
    }

    /// 计算目录大小和文件数（递归）
    ///
    /// # 参数
    /// - `dir`: 要计算的目录
    ///
    /// # 返回
    /// - `(size, files)`: 目录大小（字节）和文件数
    fn calculate_dir_size<'a>(
        &'a self,
        dir: &'a PathBuf,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(u64, usize), CacheError>> + Send + 'a>> {
        Box::pin(async move {
            let mut total_size: u64 = 0;
            let mut total_files: usize = 0;

            let mut entries = fs::read_dir(dir).await.map_err(|e| {
                CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
            })?;

            while let Some(entry) = entries.next_entry().await.map_err(|e| {
                CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
            })? {
                let path = entry.path();
                let metadata = entry.metadata().await.map_err(|e| {
                    CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
                })?;

                if metadata.is_file() {
                    total_size += metadata.len();
                    total_files += 1;
                } else if metadata.is_dir() {
                    // 递归计算子目录
                    let (sub_size, sub_files) = self.calculate_dir_size(&path).await?;
                    total_size += sub_size;
                    total_files += sub_files;
                }
            }

            Ok((total_size, total_files))
        })
    }

    /// 根据媒体 ID 查询刮削器名称
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    ///
    /// # 返回
    /// - `Ok(String)`: 刮削器名称
    /// - `Err(CacheError)`: 查询失败
    async fn get_scraper_name_by_media_id(&self, media_id: &str) -> Result<String, CacheError> {
        let row: (Option<String>,) = sqlx::query_as("SELECT scraper_name FROM media_items WHERE id = ?")
            .bind(media_id)
            .fetch_one(&self.db_pool)
            .await
            .map_err(|e| CacheError::Database(format!("查询刮削器名称失败: {}", e)))?;

        Ok(row.0.unwrap_or_else(|| "unknown".to_string()))
    }

    /// 清理指定媒体的缓存
    ///
    /// 删除该媒体的所有缓存文件（图片和视频），并将数据库中的 URL 恢复为原始 URL
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    ///
    /// # 返回
    /// - `Ok(())`: 清理成功
    /// - `Err(CacheError)`: 清理失败
    ///
    /// # 实现细节
    /// - 删除 `cache/images/media/{media_id}/` 目录
    /// - 删除 `cache/videos/media/{media_id}/` 目录
    /// - 注意：数据库中的 URL 已经是本地路径，无法恢复原始 URL
    /// - 因此只删除文件，不修改数据库（用户需要重新刮削）
    pub async fn clear_media_cache(&self, media_id: &str) -> Result<(), CacheError> {
        info!("开始清理媒体缓存: media_id={}", media_id);

        let mut deleted_files = 0;

        // 清理图片缓存
        let images_dir = CachePath::media_cache_dir(media_id, false);
        if images_dir.exists() {
            deleted_files += self.remove_dir_all(&images_dir).await?;
        }

        // 清理视频缓存
        let videos_dir = CachePath::media_cache_dir(media_id, true);
        if videos_dir.exists() {
            deleted_files += self.remove_dir_all(&videos_dir).await?;
        }

        info!(
            "媒体缓存清理完成: media_id={}, 删除文件数={}",
            media_id, deleted_files
        );

        Ok(())
    }

    /// 清理所有缓存
    ///
    /// 删除所有媒体的缓存文件
    ///
    /// # 返回
    /// - `Ok(())`: 清理成功
    /// - `Err(CacheError)`: 清理失败
    pub async fn clear_all_cache(&self) -> Result<(), CacheError> {
        info!("开始清理所有缓存");

        let mut deleted_files = 0;

        // 清理所有图片缓存
        let images_dir = CachePath::images_root().join("media");
        if images_dir.exists() {
            deleted_files += self.remove_dir_all(&images_dir).await?;
            // 重新创建 media 目录
            fs::create_dir_all(&images_dir).await.map_err(|e| {
                CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
            })?;
        }

        // 清理所有视频缓存
        let videos_dir = CachePath::videos_root().join("media");
        if videos_dir.exists() {
            deleted_files += self.remove_dir_all(&videos_dir).await?;
            // 重新创建 media 目录
            fs::create_dir_all(&videos_dir).await.map_err(|e| {
                CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
            })?;
        }

        info!("所有缓存清理完成: 删除文件数={}", deleted_files);

        Ok(())
    }

    /// 清理孤立缓存
    ///
    /// 删除数据库中不存在的媒体的缓存文件
    ///
    /// # 返回
    /// - `Ok(())`: 清理成功
    /// - `Err(CacheError)`: 清理失败
    ///
    /// # 实现细节
    /// - 遍历缓存目录中的所有媒体 ID
    /// - 查询数据库检查媒体是否存在
    /// - 如果不存在，删除该媒体的缓存目录
    pub async fn clear_orphaned_cache(&self) -> Result<(), CacheError> {
        info!("开始清理孤立缓存");

        let mut deleted_files = 0;

        // 清理孤立的图片缓存
        let images_dir = CachePath::images_root().join("media");
        if images_dir.exists() {
            deleted_files += self.clear_orphaned_in_dir(&images_dir).await?;
        }

        // 清理孤立的视频缓存
        let videos_dir = CachePath::videos_root().join("media");
        if videos_dir.exists() {
            deleted_files += self.clear_orphaned_in_dir(&videos_dir).await?;
        }

        info!("孤立缓存清理完成: 删除文件数={}", deleted_files);

        Ok(())
    }

    /// 清理指定目录中的孤立缓存（内部方法）
    ///
    /// # 参数
    /// - `dir`: 要清理的目录（images/media 或 videos/media）
    ///
    /// # 返回
    /// - `Ok(usize)`: 删除的文件数
    /// - `Err(CacheError)`: 清理失败
    async fn clear_orphaned_in_dir(&self, dir: &PathBuf) -> Result<usize, CacheError> {
        let mut deleted_files = 0;

        let mut entries = fs::read_dir(dir).await.map_err(|e| {
            CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
        })?;

        while let Some(entry) = entries.next_entry().await.map_err(|e| {
            CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
        })? {
            let path = entry.path();

            // 跳过非目录
            if !path.is_dir() {
                continue;
            }

            // 获取媒体 ID（目录名）
            let media_id = match path.file_name().and_then(|n| n.to_str()) {
                Some(id) => id,
                None => continue,
            };

            // 检查媒体是否存在于数据库
            let exists = self.media_exists(media_id).await?;

            if !exists {
                // 媒体不存在，删除缓存
                debug!("发现孤立缓存: media_id={}", media_id);
                deleted_files += self.remove_dir_all(&path).await?;
            }
        }

        Ok(deleted_files)
    }

    /// 检查媒体是否存在于数据库
    ///
    /// # 参数
    /// - `media_id`: 媒体 ID
    ///
    /// # 返回
    /// - `Ok(bool)`: 是否存在
    /// - `Err(CacheError)`: 查询失败
    async fn media_exists(&self, media_id: &str) -> Result<bool, CacheError> {
        let result: Option<(i64,)> = sqlx::query_as("SELECT COUNT(*) FROM media WHERE id = ?")
            .bind(media_id)
            .fetch_optional(&self.db_pool)
            .await
            .map_err(|e| CacheError::Database(format!("查询媒体是否存在失败: {}", e)))?;

        Ok(result.map(|(count,)| count > 0).unwrap_or(false))
    }

    /// 递归删除目录及其所有内容
    ///
    /// # 参数
    /// - `dir`: 要删除的目录
    ///
    /// # 返回
    /// - `Ok(usize)`: 删除的文件数
    /// - `Err(CacheError)`: 删除失败
    async fn remove_dir_all(&self, dir: &PathBuf) -> Result<usize, CacheError> {
        let mut deleted_files = 0;

        // 先统计文件数
        let (_, files) = self.calculate_dir_size(dir).await?;
        deleted_files += files;

        // 删除目录
        fs::remove_dir_all(dir).await.map_err(|e| {
            CacheError::FileSystem(crate::services::cache::FileSystemError::IoError(e))
        })?;

        debug!("已删除目录: {:?}, 文件数={}", dir, files);

        Ok(deleted_files)
    }
}


/// 缓存统计信息
///
/// 提供缓存的总体统计和按刮削器分组的统计
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheStats {
    /// 总缓存大小（字节）
    pub total_size: u64,

    /// 总文件数
    pub total_files: usize,

    /// 按刮削器统计
    pub by_scraper: HashMap<String, ScraperCacheStats>,
}

/// 单个刮削器的缓存统计
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScraperCacheStats {
    /// 缓存大小（字节）
    pub size: u64,

    /// 文件数
    pub files: usize,
}

/// 媒体数据（用于缓存服务）
///
/// 这是一个简化的媒体数据结构，只包含缓存所需的字段
#[derive(Debug, Clone)]
pub struct MediaData {
    /// 封面图 URL
    pub poster_url: Option<String>,

    /// 背景图 URLs
    pub backdrop_urls: Vec<String>,

    /// 预览图 URLs
    pub preview_urls: Vec<String>,

    /// 预览视频 URLs（包含清晰度信息）
    pub preview_video_urls: Vec<PreviewVideoUrl>,
}

impl MediaData {
    /// 从数据库媒体项创建
    pub fn from_media_item(item: &crate::models::media::MediaItem) -> Self {
        // 解析 backdrop_urls（JSON 数组）
        let backdrop_urls = item
            .backdrop_url
            .as_ref()
            .and_then(|s| serde_json::from_str::<Vec<String>>(s).ok())
            .unwrap_or_default();

        // 解析 preview_urls（JSON 数组）
        let preview_urls = item
            .preview_urls
            .as_ref()
            .and_then(|s| serde_json::from_str::<Vec<String>>(s).ok())
            .unwrap_or_default();

        // 解析 preview_video_urls（JSON 数组）
        let preview_video_urls = item
            .preview_video_urls
            .as_ref()
            .and_then(|s| serde_json::from_str::<Vec<PreviewVideoUrl>>(s).ok())
            .unwrap_or_default();

        Self {
            poster_url: item.poster_url.clone(),
            backdrop_urls,
            preview_urls,
            preview_video_urls,
        }
    }
}
