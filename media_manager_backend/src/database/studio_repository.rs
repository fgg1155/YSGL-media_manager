use anyhow::Result;
use sqlx::{Pool, Sqlite};
use crate::models::{
    Studio, Series, StudioWithSeries, SeriesWithStudio,
    CreateStudioRequest, UpdateStudioRequest,
    CreateSeriesRequest, UpdateSeriesRequest,
    StudioListResponse, SeriesListResponse,
    SeriesMatchResult, SeriesMatchType,
};

// ============ Studio CRUD ============

/// 创建厂商
pub async fn create_studio(pool: &Pool<Sqlite>, req: CreateStudioRequest) -> Result<Studio> {
    let studio = Studio::new(req.name);
    
    sqlx::query(
        r#"INSERT INTO studios (id, name, logo_url, description, media_count, created_at, updated_at)
           VALUES (?, ?, ?, ?, 0, datetime('now'), datetime('now'))"#
    )
    .bind(&studio.id)
    .bind(&studio.name)
    .bind(&req.logo_url)
    .bind(&req.description)
    .execute(pool)
    .await?;
    
    get_studio_by_id(pool, &studio.id).await
}

/// 根据ID获取厂商
pub async fn get_studio_by_id(pool: &Pool<Sqlite>, id: &str) -> Result<Studio> {
    let studio: Studio = sqlx::query_as(
        "SELECT * FROM studios WHERE id = ?"
    )
    .bind(id)
    .fetch_one(pool)
    .await?;
    
    Ok(studio)
}

/// 根据名称获取厂商
pub async fn get_studio_by_name(pool: &Pool<Sqlite>, name: &str) -> Result<Option<Studio>> {
    let studio: Option<Studio> = sqlx::query_as(
        "SELECT * FROM studios WHERE name = ? COLLATE NOCASE"
    )
    .bind(name)
    .fetch_optional(pool)
    .await?;
    
    Ok(studio)
}

/// 获取或创建厂商（按名称）
pub async fn find_or_create_studio(pool: &Pool<Sqlite>, name: &str) -> Result<Studio> {
    if let Some(studio) = get_studio_by_name(pool, name).await? {
        return Ok(studio);
    }
    
    create_studio(pool, CreateStudioRequest {
        name: name.to_string(),
        logo_url: None,
        description: None,
    }).await
}

/// 更新厂商
pub async fn update_studio(pool: &Pool<Sqlite>, id: &str, req: UpdateStudioRequest) -> Result<Studio> {
    let mut updates = Vec::new();
    let mut params: Vec<String> = Vec::new();
    
    if let Some(ref name) = req.name {
        updates.push("name = ?");
        params.push(name.clone());
    }
    if let Some(ref logo_url) = req.logo_url {
        updates.push("logo_url = ?");
        params.push(logo_url.clone());
    }
    if let Some(ref description) = req.description {
        updates.push("description = ?");
        params.push(description.clone());
    }
    
    if updates.is_empty() {
        return get_studio_by_id(pool, id).await;
    }
    
    let sql = format!(
        "UPDATE studios SET {} WHERE id = ?",
        updates.join(", ")
    );
    
    let mut query = sqlx::query(&sql);
    for param in &params {
        query = query.bind(param);
    }
    query = query.bind(id);
    query.execute(pool).await?;
    
    get_studio_by_id(pool, id).await
}

/// 删除厂商
pub async fn delete_studio(pool: &Pool<Sqlite>, id: &str) -> Result<()> {
    // 将关联的系列设为无厂商
    sqlx::query("UPDATE series SET studio_id = NULL WHERE studio_id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    
    sqlx::query("DELETE FROM studios WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    
    Ok(())
}

/// 获取厂商列表（带系列）
pub async fn list_studios(pool: &Pool<Sqlite>, limit: Option<i32>, offset: Option<i32>) -> Result<StudioListResponse> {
    let limit = limit.unwrap_or(100);
    let offset = offset.unwrap_or(0);
    
    // 获取总数
    let (total,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM studios")
        .fetch_one(pool)
        .await?;
    
    // 获取厂商列表
    let studios: Vec<Studio> = sqlx::query_as(
        "SELECT * FROM studios ORDER BY media_count DESC, name COLLATE NOCASE LIMIT ? OFFSET ?"
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;
    
    // 一次性获取所有相关系列，避免 N+1 查询
    let studio_ids: Vec<String> = studios.iter().map(|s| s.id.clone()).collect();
    
    // 使用 IN 查询一次性获取所有系列
    let all_series: Vec<Series> = if !studio_ids.is_empty() {
        // 构建 IN 子句的占位符
        let placeholders = studio_ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
        let query_str = format!(
            "SELECT * FROM series WHERE studio_id IN ({}) ORDER BY media_count DESC, name COLLATE NOCASE",
            placeholders
        );
        
        let mut query = sqlx::query_as(&query_str);
        for id in &studio_ids {
            query = query.bind(id);
        }
        
        query.fetch_all(pool).await?
    } else {
        Vec::new()
    };
    
    // 在内存中按 studio_id 分组
    let mut series_by_studio: std::collections::HashMap<String, Vec<Series>> = std::collections::HashMap::new();
    for series in all_series {
        if let Some(studio_id) = series.studio_id.clone() {
            series_by_studio
                .entry(studio_id)
                .or_insert_with(Vec::new)
                .push(series);
        }
    }
    
    // 组装结果
    let mut result = Vec::new();
    for studio in studios {
        let series_list = series_by_studio.remove(&studio.id).unwrap_or_default();
        result.push(StudioWithSeries { studio, series_list });
    }
    
    Ok(StudioListResponse { studios: result, total })
}

/// 搜索厂商（模糊匹配）
pub async fn search_studios(pool: &Pool<Sqlite>, query: &str, limit: Option<i32>) -> Result<Vec<Studio>> {
    let limit = limit.unwrap_or(10);
    let search_pattern = format!("%{}%", query);
    
    let studios: Vec<Studio> = sqlx::query_as(
        "SELECT * FROM studios WHERE name LIKE ? COLLATE NOCASE ORDER BY media_count DESC, name COLLATE NOCASE LIMIT ?"
    )
    .bind(&search_pattern)
    .bind(limit)
    .fetch_all(pool)
    .await?;
    
    Ok(studios)
}

/// 搜索系列（模糊匹配）
pub async fn search_series(pool: &Pool<Sqlite>, query: &str, studio_id: Option<&str>, limit: Option<i32>) -> Result<Vec<SeriesWithStudio>> {
    let limit = limit.unwrap_or(10);
    let search_pattern = format!("%{}%", query);
    
    let series_list: Vec<Series> = if let Some(studio_id) = studio_id {
        sqlx::query_as(
            "SELECT * FROM series WHERE name LIKE ? COLLATE NOCASE AND studio_id = ? ORDER BY media_count DESC, name COLLATE NOCASE LIMIT ?"
        )
        .bind(&search_pattern)
        .bind(studio_id)
        .bind(limit)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as(
            "SELECT * FROM series WHERE name LIKE ? COLLATE NOCASE ORDER BY media_count DESC, name COLLATE NOCASE LIMIT ?"
        )
        .bind(&search_pattern)
        .bind(limit)
        .fetch_all(pool)
        .await?
    };
    
    // 获取厂商名称
    let mut result = Vec::new();
    for series in series_list {
        let studio_name = if let Some(ref studio_id) = series.studio_id {
            get_studio_by_id(pool, studio_id).await.ok().map(|s| s.name)
        } else {
            None
        };
        
        result.push(SeriesWithStudio { series, studio_name });
    }
    
    Ok(result)
}


// ============ Series CRUD ============

/// 创建系列
pub async fn create_series(pool: &Pool<Sqlite>, req: CreateSeriesRequest) -> Result<Series> {
    // 如果提供了厂商名称但没有ID，尝试查找或创建厂商
    let studio_id = if req.studio_id.is_some() {
        req.studio_id
    } else if let Some(ref studio_name) = req.studio_name {
        if !studio_name.is_empty() {
            let studio = find_or_create_studio(pool, studio_name).await?;
            Some(studio.id)
        } else {
            None
        }
    } else {
        None
    };
    
    let series = Series::new(req.name, studio_id.clone());
    
    sqlx::query(
        r#"INSERT INTO series (id, name, studio_id, description, cover_url, media_count, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, 0, datetime('now'), datetime('now'))"#
    )
    .bind(&series.id)
    .bind(&series.name)
    .bind(&studio_id)
    .bind(&req.description)
    .bind(&req.cover_url)
    .execute(pool)
    .await?;
    
    get_series_by_id(pool, &series.id).await
}

/// 根据ID获取系列
pub async fn get_series_by_id(pool: &Pool<Sqlite>, id: &str) -> Result<Series> {
    let series: Series = sqlx::query_as(
        "SELECT * FROM series WHERE id = ?"
    )
    .bind(id)
    .fetch_one(pool)
    .await?;
    
    Ok(series)
}

/// 根据名称获取系列（可能返回多个，因为不同厂商可能有同名系列）
pub async fn get_series_by_name(pool: &Pool<Sqlite>, name: &str) -> Result<Vec<Series>> {
    let series: Vec<Series> = sqlx::query_as(
        "SELECT * FROM series WHERE name = ? COLLATE NOCASE"
    )
    .bind(name)
    .fetch_all(pool)
    .await?;
    
    Ok(series)
}

/// 根据名称和厂商ID获取系列
pub async fn get_series_by_name_and_studio(pool: &Pool<Sqlite>, name: &str, studio_id: Option<&str>) -> Result<Option<Series>> {
    let series: Option<Series> = match studio_id {
        Some(sid) => {
            sqlx::query_as(
                "SELECT * FROM series WHERE name = ? COLLATE NOCASE AND studio_id = ?"
            )
            .bind(name)
            .bind(sid)
            .fetch_optional(pool)
            .await?
        }
        None => {
            sqlx::query_as(
                "SELECT * FROM series WHERE name = ? COLLATE NOCASE AND studio_id IS NULL"
            )
            .bind(name)
            .fetch_optional(pool)
            .await?
        }
    };
    
    Ok(series)
}

/// 智能匹配或创建系列
/// 逻辑：
/// 1. 如果提供了厂商，精确匹配厂商+系列
/// 2. 如果只提供系列名：
///    - 如果系列名唯一存在，自动关联到该厂商
///    - 如果系列名存在于多个厂商，返回歧义状态
///    - 如果系列名不存在，创建新系列（无厂商）
pub async fn smart_match_or_create_series(
    pool: &Pool<Sqlite>,
    series_name: &str,
    studio_name: Option<&str>,
) -> Result<SeriesMatchResult> {
    // 如果提供了厂商名称
    if let Some(studio_name) = studio_name {
        if !studio_name.is_empty() {
            // 查找或创建厂商
            let studio = find_or_create_studio(pool, studio_name).await?;
            
            // 查找该厂商下的系列
            if let Some(series) = get_series_by_name_and_studio(pool, series_name, Some(&studio.id)).await? {
                return Ok(SeriesMatchResult {
                    series_id: series.id,
                    series_name: series.name,
                    studio_id: Some(studio.id),
                    studio_name: Some(studio.name),
                    match_type: SeriesMatchType::Exact,
                });
            }
            
            // 创建新系列
            let series = create_series(pool, CreateSeriesRequest {
                name: series_name.to_string(),
                studio_id: Some(studio.id.clone()),
                studio_name: None,
                description: None,
                cover_url: None,
            }).await?;
            
            return Ok(SeriesMatchResult {
                series_id: series.id,
                series_name: series.name,
                studio_id: Some(studio.id),
                studio_name: Some(studio.name),
                match_type: SeriesMatchType::NewSeries,
            });
        }
    }
    
    // 只提供了系列名，尝试智能匹配
    let existing_series = get_series_by_name(pool, series_name).await?;
    
    match existing_series.len() {
        0 => {
            // 系列不存在，创建新系列（无厂商）
            let series = create_series(pool, CreateSeriesRequest {
                name: series_name.to_string(),
                studio_id: None,
                studio_name: None,
                description: None,
                cover_url: None,
            }).await?;
            
            Ok(SeriesMatchResult {
                series_id: series.id,
                series_name: series.name,
                studio_id: None,
                studio_name: None,
                match_type: SeriesMatchType::NewSeries,
            })
        }
        1 => {
            // 系列名唯一，自动关联到该厂商
            let series = &existing_series[0];
            let studio_name = if let Some(ref studio_id) = series.studio_id {
                get_studio_by_id(pool, studio_id).await.ok().map(|s| s.name)
            } else {
                None
            };
            
            Ok(SeriesMatchResult {
                series_id: series.id.clone(),
                series_name: series.name.clone(),
                studio_id: series.studio_id.clone(),
                studio_name,
                match_type: SeriesMatchType::UniqueByName,
            })
        }
        _ => {
            // 系列名存在于多个厂商，返回第一个但标记为歧义
            let series = &existing_series[0];
            let studio_name = if let Some(ref studio_id) = series.studio_id {
                get_studio_by_id(pool, studio_id).await.ok().map(|s| s.name)
            } else {
                None
            };
            
            Ok(SeriesMatchResult {
                series_id: series.id.clone(),
                series_name: series.name.clone(),
                studio_id: series.studio_id.clone(),
                studio_name,
                match_type: SeriesMatchType::Ambiguous,
            })
        }
    }
}

/// 更新系列
pub async fn update_series(pool: &Pool<Sqlite>, id: &str, req: UpdateSeriesRequest) -> Result<Series> {
    let mut updates = Vec::new();
    
    if req.name.is_some() {
        updates.push("name = ?1");
    }
    if req.studio_id.is_some() {
        updates.push("studio_id = ?2");
    }
    if req.description.is_some() {
        updates.push("description = ?3");
    }
    if req.cover_url.is_some() {
        updates.push("cover_url = ?4");
    }
    
    if updates.is_empty() {
        return get_series_by_id(pool, id).await;
    }
    
    // 使用动态SQL
    let current = get_series_by_id(pool, id).await?;
    
    sqlx::query(
        "UPDATE series SET name = ?, studio_id = ?, description = ?, cover_url = ? WHERE id = ?"
    )
    .bind(req.name.unwrap_or(current.name))
    .bind(req.studio_id.or(current.studio_id))
    .bind(req.description.or(current.description))
    .bind(req.cover_url.or(current.cover_url))
    .bind(id)
    .execute(pool)
    .await?;
    
    get_series_by_id(pool, id).await
}

/// 删除系列
pub async fn delete_series(pool: &Pool<Sqlite>, id: &str) -> Result<()> {
    sqlx::query("DELETE FROM series WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    
    Ok(())
}

/// 获取系列列表（带厂商信息）
pub async fn list_series(pool: &Pool<Sqlite>, studio_id: Option<&str>, limit: Option<i32>, offset: Option<i32>) -> Result<SeriesListResponse> {
    let limit = limit.unwrap_or(100);
    let offset = offset.unwrap_or(0);
    
    let (series_list, total): (Vec<Series>, i64) = if let Some(studio_id) = studio_id {
        let (count,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM series WHERE studio_id = ?")
            .bind(studio_id)
            .fetch_one(pool)
            .await?;
        
        let list: Vec<Series> = sqlx::query_as(
            "SELECT * FROM series WHERE studio_id = ? ORDER BY media_count DESC, name COLLATE NOCASE LIMIT ? OFFSET ?"
        )
        .bind(studio_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        
        (list, count)
    } else {
        let (count,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM series")
            .fetch_one(pool)
            .await?;
        
        let list: Vec<Series> = sqlx::query_as(
            "SELECT * FROM series ORDER BY media_count DESC, name COLLATE NOCASE LIMIT ? OFFSET ?"
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        
        (list, count)
    };
    
    // 获取厂商名称
    let mut result = Vec::new();
    for series in series_list {
        let studio_name = if let Some(ref studio_id) = series.studio_id {
            get_studio_by_id(pool, studio_id).await.ok().map(|s| s.name)
        } else {
            None
        };
        
        result.push(SeriesWithStudio { series, studio_name });
    }
    
    Ok(SeriesListResponse { series: result, total })
}

/// 更新厂商的媒体计数
pub async fn update_studio_media_count(pool: &Pool<Sqlite>, studio_name: &str) -> Result<()> {
    sqlx::query(
        r#"UPDATE studios SET media_count = (
            SELECT COUNT(*) FROM media_items WHERE studio = studios.name COLLATE NOCASE
        ) WHERE name = ? COLLATE NOCASE"#
    )
    .bind(studio_name)
    .execute(pool)
    .await?;
    
    Ok(())
}

/// 更新系列的媒体计数
pub async fn update_series_media_count(pool: &Pool<Sqlite>, series_name: &str) -> Result<()> {
    sqlx::query(
        r#"UPDATE series SET media_count = (
            SELECT COUNT(*) FROM media_items WHERE series = series.name COLLATE NOCASE
        ) WHERE name = ? COLLATE NOCASE"#
    )
    .bind(series_name)
    .execute(pool)
    .await?;
    
    Ok(())
}

/// 同步所有厂商和系列的媒体计数
pub async fn sync_all_counts(pool: &Pool<Sqlite>) -> Result<()> {
    // 更新所有厂商计数
    sqlx::query(
        r#"UPDATE studios SET media_count = (
            SELECT COUNT(*) FROM media_items WHERE studio = studios.name COLLATE NOCASE
        )"#
    )
    .execute(pool)
    .await?;
    
    // 更新所有系列计数
    sqlx::query(
        r#"UPDATE series SET media_count = (
            SELECT COUNT(*) FROM media_items WHERE series = series.name COLLATE NOCASE
        )"#
    )
    .execute(pool)
    .await?;
    
    Ok(())
}
