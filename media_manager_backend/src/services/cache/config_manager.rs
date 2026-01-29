// 配置管理器 - 管理缓存配置的读写和更新
//
// 本模块提供缓存配置的持久化管理功能，包括：
// - 从 JSON 文件加载配置
// - 保存配置到 JSON 文件
// - 判断是否应该缓存
// - 自动开启缓存
// - 更新刮削器配置

use crate::services::cache::{CacheConfig, CacheError, ScraperCacheConfig};
use chrono::Utc;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::fs;
use tokio::sync::RwLock;

/// 配置管理器
///
/// 负责管理缓存配置的读写和更新，使用 Arc<RwLock> 保证线程安全
pub struct ConfigManager {
    /// 配置文件路径
    config_path: PathBuf,

    /// 缓存配置（使用读写锁保证线程安全）
    config: Arc<RwLock<CacheConfig>>,
}

impl ConfigManager {
    /// 默认配置文件路径
    const DEFAULT_CONFIG_PATH: &'static str = "cache_config.json";

    /// 从配置文件加载配置
    ///
    /// # 参数
    /// - `config_path`: 可选的配置文件路径，如果为 None 则使用默认路径
    ///
    /// # 返回值
    /// - `Ok(ConfigManager)`: 成功加载配置
    /// - `Err(CacheError)`: 加载失败
    ///
    /// # 行为
    /// - 如果配置文件不存在，使用默认配置并创建文件
    /// - 如果配置文件损坏，使用默认配置并备份旧文件
    ///
    /// # 示例
    /// ```no_run
    /// use media_manager_backend::services::cache::ConfigManager;
    ///
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let manager = ConfigManager::load(None).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn load(config_path: Option<PathBuf>) -> Result<Self, CacheError> {
        let config_path = config_path
            .unwrap_or_else(|| PathBuf::from(Self::DEFAULT_CONFIG_PATH));

        let config = if config_path.exists() {
            // 尝试读取配置文件
            match fs::read_to_string(&config_path).await {
                Ok(content) => {
                    // 尝试解析 JSON
                    match serde_json::from_str::<CacheConfig>(&content) {
                        Ok(config) => {
                            tracing::info!("成功加载缓存配置: {:?}", config_path);
                            config
                        }
                        Err(e) => {
                            // 配置文件损坏，备份并使用默认配置
                            tracing::warn!("配置文件损坏，使用默认配置: {}", e);
                            Self::backup_corrupted_config(&config_path).await?;
                            CacheConfig::default()
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!("读取配置文件失败，使用默认配置: {}", e);
                    CacheConfig::default()
                }
            }
        } else {
            // 配置文件不存在，使用默认配置
            tracing::info!("配置文件不存在，使用默认配置");
            CacheConfig::default()
        };

        let manager = Self {
            config_path,
            config: Arc::new(RwLock::new(config)),
        };

        // 保存默认配置到文件
        if !manager.config_path.exists() {
            manager.save().await?;
        }

        Ok(manager)
    }

    /// 保存配置到文件
    ///
    /// # 返回值
    /// - `Ok(())`: 保存成功
    /// - `Err(CacheError)`: 保存失败
    ///
    /// # 示例
    /// ```no_run
    /// # use media_manager_backend::services::cache::ConfigManager;
    /// # async fn example(manager: &ConfigManager) -> Result<(), Box<dyn std::error::Error>> {
    /// manager.save().await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn save(&self) -> Result<(), CacheError> {
        let config = self.config.read().await;

        // 序列化配置为 JSON（格式化输出）
        let json = serde_json::to_string_pretty(&*config)?;

        // 确保父目录存在
        if let Some(parent) = self.config_path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent).await.map_err(|e| {
                    CacheError::Config(format!("创建配置目录失败: {}", e))
                })?;
            }
        }

        // 写入文件
        fs::write(&self.config_path, json).await.map_err(|e| {
            CacheError::Config(format!("写入配置文件失败: {}", e))
        })?;

        tracing::info!("成功保存缓存配置: {:?}", self.config_path);
        Ok(())
    }

    /// 判断是否应该缓存某个刮削器的图片
    ///
    /// # 参数
    /// - `scraper_name`: 刮削器名称
    ///
    /// # 返回值
    /// - `true`: 应该缓存
    /// - `false`: 不应该缓存
    ///
    /// # 优先级规则
    /// 1. 如果 `global_cache_enabled = true`，返回 true
    /// 2. 否则，返回该刮削器的 `cache_enabled` 值
    /// 3. 如果刮削器配置不存在，返回 false
    ///
    /// # 示例
    /// ```no_run
    /// # use media_manager_backend::services::cache::ConfigManager;
    /// # async fn example(manager: &ConfigManager) {
    /// let should_cache = manager.should_cache("maturenl").await;
    /// if should_cache {
    ///     println!("应该缓存 maturenl 的图片");
    /// }
    /// # }
    /// ```
    pub async fn should_cache(&self, scraper_name: &str) -> bool {
        let config = self.config.read().await;

        // 优先级 1: 全局开关
        if config.global_cache_enabled {
            return true;
        }

        // 优先级 2: 单个刮削器配置
        config
            .scrapers
            .get(scraper_name)
            .map(|scraper_config| scraper_config.cache_enabled)
            .unwrap_or(false)
    }

    /// 自动开启缓存
    ///
    /// 当检测到临时 URL 时，自动开启该刮削器的缓存功能
    ///
    /// # 参数
    /// - `scraper_name`: 刮削器名称
    ///
    /// # 返回值
    /// - `Ok(())`: 开启成功
    /// - `Err(CacheError)`: 开启失败
    ///
    /// # 行为
    /// - 设置 `cache_enabled = true`
    /// - 设置 `auto_enabled = true`
    /// - 记录 `auto_enabled_at` 时间戳
    /// - 如果已经开启，不重复设置时间戳（幂等性）
    /// - 自动保存配置到文件
    ///
    /// # 示例
    /// ```no_run
    /// # use media_manager_backend::services::cache::ConfigManager;
    /// # async fn example(manager: &ConfigManager) -> Result<(), Box<dyn std::error::Error>> {
    /// manager.auto_enable_cache("maturenl").await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn auto_enable_cache(&self, scraper_name: &str) -> Result<(), CacheError> {
        let mut config = self.config.write().await;

        // 获取或创建刮削器配置
        let scraper_config = config
            .scrapers
            .entry(scraper_name.to_string())
            .or_insert_with(ScraperCacheConfig::default);

        // 如果已经开启，不重复设置（幂等性）
        if scraper_config.cache_enabled && scraper_config.auto_enabled {
            tracing::debug!("刮削器 {} 的缓存已经自动开启，跳过", scraper_name);
            return Ok(());
        }

        // 开启缓存
        scraper_config.cache_enabled = true;
        scraper_config.auto_enabled = true;

        // 只在首次自动开启时设置时间戳
        if scraper_config.auto_enabled_at.is_none() {
            scraper_config.auto_enabled_at = Some(Utc::now());
        }

        tracing::info!(
            "检测到 {} 返回临时 URL，已自动开启缓存",
            scraper_name
        );

        // 释放写锁
        drop(config);

        // 保存配置
        self.save().await?;

        Ok(())
    }

    /// 更新刮削器配置
    ///
    /// # 参数
    /// - `scraper_name`: 刮削器名称
    /// - `new_config`: 新的刮削器配置
    ///
    /// # 返回值
    /// - `Ok(())`: 更新成功
    /// - `Err(CacheError)`: 更新失败
    ///
    /// # 行为
    /// - 更新指定刮削器的配置
    /// - 如果用户手动修改配置，清除 `auto_enabled` 标记
    /// - 自动保存配置到文件
    ///
    /// # 示例
    /// ```no_run
    /// # use media_manager_backend::services::cache::{ConfigManager, ScraperCacheConfig, CacheField};
    /// # async fn example(manager: &ConfigManager) -> Result<(), Box<dyn std::error::Error>> {
    /// let config = ScraperCacheConfig {
    ///     cache_enabled: true,
    ///     auto_enabled: false,
    ///     auto_enabled_at: None,
    ///     cache_fields: vec![CacheField::Poster, CacheField::Backdrop],
    /// };
    /// manager.update_scraper_config("maturenl", config).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn update_scraper_config(
        &self,
        scraper_name: &str,
        new_config: ScraperCacheConfig,
    ) -> Result<(), CacheError> {
        let mut config = self.config.write().await;

        config
            .scrapers
            .insert(scraper_name.to_string(), new_config);

        tracing::info!("更新刮削器 {} 的缓存配置", scraper_name);

        // 释放写锁
        drop(config);

        // 保存配置
        self.save().await?;

        Ok(())
    }

    /// 更新全局缓存开关
    ///
    /// # 参数
    /// - `enabled`: 是否开启全局缓存
    ///
    /// # 返回值
    /// - `Ok(())`: 更新成功
    /// - `Err(CacheError)`: 更新失败
    pub async fn update_global_cache(&self, enabled: bool) -> Result<(), CacheError> {
        let mut config = self.config.write().await;
        config.global_cache_enabled = enabled;

        tracing::info!("更新全局缓存开关: {}", enabled);

        // 释放写锁
        drop(config);

        // 保存配置
        self.save().await?;

        Ok(())
    }

    /// 获取完整配置（克隆）
    ///
    /// # 返回值
    /// 当前的缓存配置（克隆）
    ///
    /// # 示例
    /// ```no_run
    /// # use media_manager_backend::services::cache::ConfigManager;
    /// # async fn example(manager: &ConfigManager) {
    /// let config = manager.get_config().await;
    /// println!("全局缓存开关: {}", config.global_cache_enabled);
    /// # }
    /// ```
    pub async fn get_config(&self) -> CacheConfig {
        self.config.read().await.clone()
    }

    /// 获取配置的共享引用（用于高性能场景）
    ///
    /// # 返回值
    /// 配置的 Arc<RwLock> 引用
    pub fn get_config_ref(&self) -> Arc<RwLock<CacheConfig>> {
        Arc::clone(&self.config)
    }

    /// 备份损坏的配置文件
    async fn backup_corrupted_config(config_path: &PathBuf) -> Result<(), CacheError> {
        let backup_path = config_path.with_extension("json.backup");
        
        match fs::rename(config_path, &backup_path).await {
            Ok(_) => {
                tracing::info!("已备份损坏的配置文件到: {:?}", backup_path);
                Ok(())
            }
            Err(e) => {
                tracing::warn!("备份配置文件失败: {}", e);
                // 备份失败不影响主流程
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::cache::CacheField;
    use tempfile::TempDir;

    /// 创建临时配置文件路径
    fn create_temp_config_path() -> (TempDir, PathBuf) {
        let temp_dir = TempDir::new().unwrap();
        let config_path = temp_dir.path().join("test_cache_config.json");
        (temp_dir, config_path)
    }

    #[tokio::test]
    async fn test_load_with_nonexistent_file() {
        let (_temp_dir, config_path) = create_temp_config_path();

        let manager = ConfigManager::load(Some(config_path.clone()))
            .await
            .unwrap();

        // 应该使用默认配置
        let config = manager.get_config().await;
        assert!(!config.global_cache_enabled);
        assert!(config.scrapers.is_empty());

        // 应该创建配置文件
        assert!(config_path.exists());
    }

    #[tokio::test]
    async fn test_load_and_save() {
        let (_temp_dir, config_path) = create_temp_config_path();

        // 创建并保存配置
        let manager = ConfigManager::load(Some(config_path.clone()))
            .await
            .unwrap();

        {
            let mut config = manager.config.write().await;
            config.global_cache_enabled = true;
            config.scrapers.insert(
                "maturenl".to_string(),
                ScraperCacheConfig {
                    cache_enabled: true,
                    auto_enabled: true,
                    auto_enabled_at: Some(Utc::now()),
                    cache_fields: vec![CacheField::Poster, CacheField::Backdrop],
                },
            );
        }

        manager.save().await.unwrap();

        // 重新加载配置
        let manager2 = ConfigManager::load(Some(config_path)).await.unwrap();
        let config2 = manager2.get_config().await;

        assert!(config2.global_cache_enabled);
        assert_eq!(config2.scrapers.len(), 1);
        assert!(config2.scrapers.contains_key("maturenl"));
    }

    #[tokio::test]
    async fn test_should_cache_with_global_enabled() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 开启全局缓存
        manager.update_global_cache(true).await.unwrap();

        // 任何刮削器都应该缓存
        assert!(manager.should_cache("maturenl").await);
        assert!(manager.should_cache("mindgeek").await);
        assert!(manager.should_cache("unknown").await);
    }

    #[tokio::test]
    async fn test_should_cache_with_scraper_enabled() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 开启单个刮削器的缓存
        let scraper_config = ScraperCacheConfig {
            cache_enabled: true,
            auto_enabled: false,
            auto_enabled_at: None,
            cache_fields: vec![CacheField::Poster],
        };
        manager
            .update_scraper_config("maturenl", scraper_config)
            .await
            .unwrap();

        // 只有 maturenl 应该缓存
        assert!(manager.should_cache("maturenl").await);
        assert!(!manager.should_cache("mindgeek").await);
    }

    #[tokio::test]
    async fn test_should_cache_with_global_disabled() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 全局缓存关闭，无刮削器配置
        assert!(!manager.should_cache("maturenl").await);
    }

    #[tokio::test]
    async fn test_auto_enable_cache() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 自动开启缓存
        manager.auto_enable_cache("maturenl").await.unwrap();

        // 验证配置
        let config = manager.get_config().await;
        let scraper_config = config.scrapers.get("maturenl").unwrap();

        assert!(scraper_config.cache_enabled);
        assert!(scraper_config.auto_enabled);
        assert!(scraper_config.auto_enabled_at.is_some());

        // 应该能够缓存
        assert!(manager.should_cache("maturenl").await);
    }

    #[tokio::test]
    async fn test_auto_enable_cache_idempotent() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 第一次自动开启
        manager.auto_enable_cache("maturenl").await.unwrap();
        let config1 = manager.get_config().await;
        let timestamp1 = config1
            .scrapers
            .get("maturenl")
            .unwrap()
            .auto_enabled_at
            .unwrap();

        // 等待一小段时间
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // 第二次自动开启（应该是幂等的）
        manager.auto_enable_cache("maturenl").await.unwrap();
        let config2 = manager.get_config().await;
        let timestamp2 = config2
            .scrapers
            .get("maturenl")
            .unwrap()
            .auto_enabled_at
            .unwrap();

        // 时间戳应该相同（幂等性）
        assert_eq!(timestamp1, timestamp2);
    }

    #[tokio::test]
    async fn test_update_scraper_config() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 更新刮削器配置
        let new_config = ScraperCacheConfig {
            cache_enabled: true,
            auto_enabled: false,
            auto_enabled_at: None,
            cache_fields: vec![CacheField::Poster, CacheField::Backdrop, CacheField::Preview],
        };
        manager
            .update_scraper_config("maturenl", new_config.clone())
            .await
            .unwrap();

        // 验证配置
        let config = manager.get_config().await;
        let scraper_config = config.scrapers.get("maturenl").unwrap();

        assert_eq!(scraper_config.cache_enabled, new_config.cache_enabled);
        assert_eq!(scraper_config.auto_enabled, new_config.auto_enabled);
        assert_eq!(scraper_config.cache_fields, new_config.cache_fields);
    }

    #[tokio::test]
    async fn test_update_global_cache() {
        let (_temp_dir, config_path) = create_temp_config_path();
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();

        // 更新全局缓存开关
        manager.update_global_cache(true).await.unwrap();

        let config = manager.get_config().await;
        assert!(config.global_cache_enabled);

        // 再次更新
        manager.update_global_cache(false).await.unwrap();

        let config = manager.get_config().await;
        assert!(!config.global_cache_enabled);
    }

    #[tokio::test]
    async fn test_load_corrupted_config() {
        let (_temp_dir, config_path) = create_temp_config_path();

        // 写入损坏的 JSON
        fs::write(&config_path, "{ invalid json }")
            .await
            .unwrap();

        // 应该能够加载（使用默认配置）
        let manager = ConfigManager::load(Some(config_path.clone()))
            .await
            .unwrap();

        let config = manager.get_config().await;
        assert!(!config.global_cache_enabled);
        assert!(config.scrapers.is_empty());

        // 应该创建备份文件
        let backup_path = config_path.with_extension("json.backup");
        assert!(backup_path.exists());
    }

    #[tokio::test]
    async fn test_config_persistence() {
        let (_temp_dir, config_path) = create_temp_config_path();

        // 创建配置并保存
        {
            let manager = ConfigManager::load(Some(config_path.clone()))
                .await
                .unwrap();
            manager.auto_enable_cache("maturenl").await.unwrap();
            manager.update_global_cache(true).await.unwrap();
        }

        // 重新加载配置
        let manager = ConfigManager::load(Some(config_path)).await.unwrap();
        let config = manager.get_config().await;

        // 验证配置持久化
        assert!(config.global_cache_enabled);
        assert!(config.scrapers.contains_key("maturenl"));
        assert!(config.scrapers.get("maturenl").unwrap().cache_enabled);
    }
}
