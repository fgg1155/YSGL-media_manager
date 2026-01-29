pub mod media;
pub mod collections;
pub mod search;
pub mod health;
pub mod actors;
pub mod studios;
pub mod scrape;
pub mod proxy;
pub mod sync;
pub mod file_scan;
pub mod streaming;
pub mod cache;
pub mod error;
pub mod response;

use std::sync::Arc;
use tokio::sync::RwLock;
use crate::{database::Database, external::ExternalApiClient, services::{DatabaseService, CacheService}};
use crate::plugins::manager::PluginManager;

#[derive(Clone)]
pub struct AppState {
    pub database: Database,
    pub db_service: Arc<DatabaseService>,
    pub external_client: ExternalApiClient,
    pub plugin_manager: Arc<RwLock<PluginManager>>,
    pub cache_service: Arc<CacheService>,
}