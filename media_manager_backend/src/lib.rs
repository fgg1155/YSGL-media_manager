// 媒体管理后端库
//
// 本库提供媒体管理的核心功能，包括：
// - API 路由
// - 数据库操作
// - 外部 API 集成
// - 缓存管理
// - 插件系统

#![allow(dead_code)]
#![allow(unused_imports)]

pub mod api;
pub mod database;
pub mod external;
pub mod models;
pub mod services;
pub mod plugins;
