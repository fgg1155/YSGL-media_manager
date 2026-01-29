// 允许未使用的代码（预留功能）
#![allow(dead_code)]
#![allow(unused_imports)]

use axum::{
    routing::{get, post},
    Router,
};
use std::net::SocketAddr;
use tower_http::cors::CorsLayer;
use tracing_subscriber;
use std::time::Duration;
use std::sync::Arc;
use tokio::sync::RwLock;

mod api;
mod database;
mod external;
mod models;
mod services;
mod plugins;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load environment variables
    dotenv::dotenv().ok();

    // Initialize database
    let database = database::Database::new().await?;
    
    // Initialize database service
    let db_service = services::DatabaseService::new(database.repository().clone());
    
    // Initialize external API client
    let external_client = external::ExternalApiClient::new();
    
    // Initialize plugin manager
    let plugins_dir = std::env::var("PLUGINS_DIR").unwrap_or_else(|_| "./plugins".to_string());
    let mut plugin_manager = plugins::manager::PluginManager::new(&plugins_dir);
    if let Err(e) = plugin_manager.scan_plugins().await {
        tracing::warn!("Failed to scan plugins: {}", e);
    }
    let plugin_manager = Arc::new(RwLock::new(plugin_manager));
    
    // Start cache cleanup task
    let cache_for_cleanup = external_client.cache.clone();
    let cache_cleanup_task = external::cache::CacheCleanupTask::new(
        cache_for_cleanup,
        Duration::from_secs(5 * 60), // 每5分钟清理一次
    );
    tokio::spawn(cache_cleanup_task.start());
    
    // Initialize sync trigger state
    let sync_trigger_state = Arc::new(api::sync::SyncTriggerState::new());
    
    // Build our application with routes
    let app = Router::new()
        .route("/", get(|| async { "Media Manager Backend API v1.0" }))
        // Health and stats
        .route("/api/health", get(api::health::health_check))
        .route("/api/stats", get(api::health::get_stats))
        .route("/api/cache/cleanup", post(api::health::cleanup_cache))
        .route("/api/cache/clear", post(api::health::clear_cache))
        // Media management
        .route("/api/media", get(api::media::get_media_list))
        .route("/api/media/filters", get(api::media::get_filter_options))
        .route("/api/media/:id", get(api::media::get_media_detail))
        .route("/api/media", post(api::media::create_media))
        .route("/api/media/:id", axum::routing::put(api::media::update_media))
        .route("/api/media/:id", axum::routing::delete(api::media::delete_media))
        // Collections
        .route("/api/collections", get(api::collections::get_collections))
        .route("/api/collections", post(api::collections::add_to_collection))
        .route("/api/collections/:media_id", axum::routing::delete(api::collections::remove_from_collection))
        .route("/api/collections/:media_id/status", axum::routing::put(api::collections::update_collection_status))
        // TMDB integration
        .route("/api/tmdb/details", get(api::media::get_tmdb_details))
        .route("/api/tmdb/popular", get(api::media::get_popular_content))
        .route("/api/tmdb/save", post(api::media::save_tmdb_media))
        // Batch operations
        .route("/api/batch/import", post(api::media::batch_import_media))
        .route("/api/batch/collection", post(api::media::batch_collection_operation))
        .route("/api/batch/delete", post(api::media::batch_delete_media))
        .route("/api/batch/edit", post(api::media::batch_edit_media))
        // Data export/import
        .route("/api/data/export", get(api::media::export_all_data))
        .route("/api/data/import", post(api::media::import_data))
        // Search
        .route("/api/search", get(api::search::search_media))
        .route("/api/search/advanced", post(api::search::advanced_search))
        .route("/api/search/suggestions", get(api::search::get_search_suggestions))
        .route("/api/search/trending", get(api::search::get_trending_searches))
        // Actors
        .route("/api/actors", get(api::actors::list_actors_handler))
        .route("/api/actors", post(api::actors::create_actor_handler))
        .route("/api/actors/:id", get(api::actors::get_actor_handler))
        .route("/api/actors/:id", axum::routing::put(api::actors::update_actor_handler))
        .route("/api/actors/:id", axum::routing::delete(api::actors::delete_actor_handler))
        // Actor-Media relationships
        .route("/api/media/:id/actors", get(api::actors::get_media_actors_handler))
        .route("/api/media/:id/actors", post(api::actors::add_actor_to_media_handler))
        .route("/api/media/:media_id/actors/:actor_id", axum::routing::delete(api::actors::remove_actor_from_media_handler))
        // Studios
        .route("/api/studios", get(api::studios::list_studios_handler))
        .route("/api/studios", post(api::studios::create_studio_handler))
        .route("/api/studios/search", get(api::studios::search_studios_handler))
        .route("/api/studios/:id", get(api::studios::get_studio_handler))
        .route("/api/studios/:id", axum::routing::put(api::studios::update_studio_handler))
        .route("/api/studios/:id", axum::routing::delete(api::studios::delete_studio_handler))
        // Series
        .route("/api/series", get(api::studios::list_series_handler))
        .route("/api/series", post(api::studios::create_series_handler))
        .route("/api/series/search", get(api::studios::search_series_handler))
        .route("/api/series/:id", get(api::studios::get_series_handler))
        .route("/api/series/:id", axum::routing::put(api::studios::update_series_handler))
        .route("/api/series/:id", axum::routing::delete(api::studios::delete_series_handler))
        .route("/api/studios-series/sync-counts", post(api::studios::sync_counts_handler))
        // Scrape plugins
        .route("/api/scrape/plugins", get(api::scrape::list_plugins))
        .route("/api/scrape/plugins/reload", post(api::scrape::reload_plugins))
        // 统一刮削API
        .route("/api/scrape/media/:media_id", post(api::scrape::scrape_media))
        .route("/api/scrape/media/:media_id/multiple", post(api::scrape::scrape_media_multiple))
        .route("/api/scrape/media/batch", post(api::scrape::batch_scrape_media_unified))
        .route("/api/scrape/media/batch-import", post(api::scrape::batch_import_media))
        .route("/api/scrape/actor/:actor_id", post(api::actors::scrape_actor))
        .route("/api/scrape/actor/batch", post(api::actors::batch_scrape_actor_unified))
        // 统一进度查询端点（媒体和演员刮削共用）
        .route("/api/scrape/progress/:session_id", get(api::scrape::get_scrape_progress))
        // 磁力搜索和通用刮削
        .route("/api/scrape/magnets/progress/:session_id", get(api::scrape::get_magnet_search_progress))
        .route("/api/scrape/magnets/:plugin_id", get(api::scrape::search_magnets))
        .route("/api/scrape/:id", get(api::scrape::scrape_auto))
        .route("/api/scrape/:plugin_id/:id", get(api::scrape::scrape_with_plugin))
        .route("/api/scrape/:plugin_id/search", get(api::scrape::search_with_plugin))
        // Image proxy
        .route("/api/proxy/image", get(api::proxy::proxy_image))
        // Video proxy
        .route("/api/proxy/video", get(api::proxy::proxy_video))
        // HLS proxy
        .route("/api/proxy/hls", get(api::proxy::proxy_hls))
        .route("/api/proxy/hls/segment", get(api::proxy::proxy_hls_segment))
        // File scan
        .route("/api/scan/start", post(api::file_scan::start_scan))
        .route("/api/scan/match", post(api::file_scan::match_files))
        .route("/api/scan/confirm", post(api::file_scan::confirm_matches))
        .route("/api/scan/auto-scrape", post(api::file_scan::auto_scrape_unmatched))
        .route("/api/scan/auto-scrape/progress/:session_id", get(api::file_scan::get_auto_scrape_progress))
        .route("/api/scan/ignore", post(api::file_scan::ignore_file))
        .route("/api/scan/ignored", get(api::file_scan::get_ignored_files))
        .route("/api/scan/ignored/remove", post(api::file_scan::remove_ignored_file))
        .route("/api/media/:id/files", get(api::file_scan::get_media_files))  // 新增：获取媒体文件列表
        // Streaming
        .route("/api/media/:id/thumbnail", get(api::streaming::get_media_thumbnail))
        .route("/api/media/:id/video", get(api::streaming::stream_video))
        .layer(CorsLayer::permissive())
        .with_state(api::AppState {
            database: database.clone(),
            db_service: std::sync::Arc::new(db_service),
            external_client,
            plugin_manager: plugin_manager.clone(),
        });
    
    // Add sync routes with separate state
    let sync_routes = Router::new()
        .route("/api/sync/trigger", post(api::sync::trigger_sync))
        .route("/api/sync/check", get(api::sync::check_sync_request))
        .route("/api/sync/complete", post(api::sync::complete_sync))
        .route("/api/sync/status", get(api::sync::get_sync_status))
        .layer(CorsLayer::permissive())
        .with_state(sync_trigger_state);
    
    // Merge routes
    let app = app.merge(sync_routes);

    // Run the server - 从环境变量读取配置，支持手机访问
    let host = std::env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "3000".to_string())
        .parse()
        .unwrap_or(3000);
    
    let addr: SocketAddr = format!("{}:{}", host, port).parse()?;
    tracing::info!("🚀 Server listening on {}", addr);
    tracing::info!("📊 Cache cleanup task started (interval: 5 minutes)");
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}