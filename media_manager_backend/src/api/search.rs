use axum::{
    extract::{Query, State},
    response::{Json, IntoResponse},
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Instant;

use super::AppState;
use crate::api::response::success;
use crate::models::{MediaItem, MediaType, MediaItemResponse};

#[derive(Debug, Deserialize)]
pub struct SearchParams {
    pub q: Option<String>,
    pub media_type: Option<String>,
    pub page: Option<u32>,
    pub source: Option<String>, // "local", "tmdb", "all"
    pub limit: Option<u32>,
    pub actor_id: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SearchResponse {
    pub results: Vec<MediaItemResponse>,
    pub total: usize,
    pub page: u32,
    pub source: String,
    pub took_ms: u64,
    pub query: String,
}

#[derive(Debug, Deserialize)]
pub struct AdvancedSearchRequest {
    pub query: Option<String>,
    pub media_type: Option<MediaType>,
    pub year_from: Option<i32>,
    pub year_to: Option<i32>,
    pub genre: Option<String>,
    pub rating_min: Option<f32>,
    pub rating_max: Option<f32>,
    pub page: Option<u32>,
    pub source: Option<String>,
    pub limit: Option<u32>,
    pub actor_id: Option<String>,
    pub studio: Option<String>,
    pub series: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SearchSuggestion {
    pub text: String,
    pub type_: String, // "title", "genre", "person", "year"
    pub count: i32,
}

#[derive(Debug, Serialize)]
pub struct SearchSuggestionsResponse {
    pub suggestions: Vec<SearchSuggestion>,
    pub query: String,
}

pub async fn search_media(
    Query(params): Query<SearchParams>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let start_time = Instant::now();
    let query = params.q.unwrap_or_default();
    let page = params.page.unwrap_or(1);
    let source = params.source.unwrap_or_else(|| "all".to_string());
    
    if query.is_empty() {
        return success(SearchResponse {
            results: Vec::new(),
            total: 0,
            page,
            source,
            took_ms: start_time.elapsed().as_millis() as u64,
            query,
        });
    }
    
    // 记录搜索历史
    record_search_history(state.database.pool(), &query).await;
    
    let mut all_results = Vec::new();
    
    // 搜索本地数据库
    if source == "local" || source == "all" {
        match search_local_media(&state, &query, &params.media_type).await {
            Ok(local_results) => {
                all_results.extend(local_results);
            }
            Err(e) => {
                tracing::error!("Local search failed: {}", e);
            }
        }
    }
    
    // 搜索TMDB
    if (source == "tmdb" || source == "all") && state.external_client.is_tmdb_available() {
        match search_tmdb_media(&state, &query, &params.media_type, page).await {
            Ok(tmdb_results) => {
                all_results.extend(tmdb_results);
            }
            Err(e) => {
                tracing::error!("TMDB search failed: {}", e);
            }
        }
    }
    
    // 去重（基于external_ids中的tmdb_id）
    all_results = deduplicate_results(all_results);
    
    // 应用分页
    let limit = params.limit.unwrap_or(20) as usize;
    let offset = ((page - 1) * limit as u32) as usize;
    let total = all_results.len();
    let paginated_results = all_results.into_iter()
        .skip(offset)
        .take(limit)
        .map(MediaItemResponse::from)
        .collect();
    
    success(SearchResponse {
        results: paginated_results,
        total,
        page,
        source,
        took_ms: start_time.elapsed().as_millis() as u64,
        query,
    })
}

pub async fn advanced_search(
    State(state): State<AppState>,
    Json(request): Json<AdvancedSearchRequest>,
) -> impl IntoResponse {
    let start_time = Instant::now();
    let page = request.page.unwrap_or(1);
    let source = request.source.clone().unwrap_or_else(|| "all".to_string());
    let query = request.query.clone().unwrap_or_default();
    
    // 记录搜索历史
    if !query.is_empty() {
        record_search_history(state.database.pool(), &query).await;
    }
    
    let mut all_results = Vec::new();
    
    // 本地高级搜索
    if source == "local" || source == "all" {
        match advanced_search_local(&state, &request).await {
            Ok(local_results) => {
                all_results.extend(local_results);
            }
            Err(e) => {
                tracing::error!("Local advanced search failed: {}", e);
            }
        }
    }
    
    // TMDB搜索（基础搜索，因为TMDB API的高级搜索功能有限）
    if (source == "tmdb" || source == "all") && state.external_client.is_tmdb_available() {
        if let Some(ref query) = request.query {
            let media_type_str = request.media_type.as_ref().map(|mt| match mt {
                MediaType::Movie => "movie",
                MediaType::Scene => "tv",
                _ => "movie",
            });
            
            match search_tmdb_media(&state, query, &media_type_str.map(|s| s.to_string()), page).await {
                Ok(tmdb_results) => {
                    // 应用客户端过滤
                    let filtered_results = filter_tmdb_results(tmdb_results, &request);
                    all_results.extend(filtered_results);
                }
                Err(e) => {
                    tracing::error!("TMDB search in advanced search failed: {}", e);
                }
            }
        }
    }
    
    all_results = deduplicate_results(all_results);
    
    // 应用分页
    let limit = request.limit.unwrap_or(20) as usize;
    let offset = ((page - 1) * limit as u32) as usize;
    let total = all_results.len();
    let paginated_results = all_results.into_iter()
        .skip(offset)
        .take(limit)
        .map(MediaItemResponse::from)
        .collect();
    
    success(SearchResponse {
        results: paginated_results,
        total,
        page,
        source,
        took_ms: start_time.elapsed().as_millis() as u64,
        query,
    })
}

/// 获取搜索建议
pub async fn get_search_suggestions(
    Query(params): Query<HashMap<String, String>>,
    State(_state): State<AppState>,
) -> impl IntoResponse {
    let query = params.get("q").cloned().unwrap_or_default();
    
    if query.len() < 2 {
        return success(SearchSuggestionsResponse {
            suggestions: Vec::new(),
            query,
        });
    }
    
    // TODO: 实现搜索建议逻辑
    // 这里可以从数据库中获取匹配的标题、类型、演员等
    let suggestions = vec![
        SearchSuggestion {
            text: format!("{} (Movie)", query),
            type_: "title".to_string(),
            count: 5,
        },
        SearchSuggestion {
            text: format!("{} (TV Show)", query),
            type_: "title".to_string(),
            count: 3,
        },
    ];
    
    success(SearchSuggestionsResponse {
        suggestions,
        query,
    })
}

/// 获取热门搜索词
pub async fn get_trending_searches(
    State(state): State<AppState>,
) -> impl IntoResponse {
    let pool = state.database.pool();
    
    // 从搜索历史中获取最近30天内最热门的搜索词
    let trending: Vec<String> = sqlx::query_scalar(
        r#"
        SELECT query
        FROM search_history
        WHERE searched_at >= datetime('now', '-30 days')
        GROUP BY query COLLATE NOCASE
        ORDER BY COUNT(*) DESC, MAX(searched_at) DESC
        LIMIT 10
        "#
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    
    // 如果没有搜索历史，返回默认热门词
    if trending.is_empty() {
        return success(vec![
            "Marvel".to_string(),
            "Star Wars".to_string(),
            "Netflix".to_string(),
            "Action".to_string(),
            "Comedy".to_string(),
        ]);
    }
    
    success(trending)
}

/// 记录搜索历史
async fn record_search_history(pool: &sqlx::SqlitePool, query: &str) {
    if query.trim().is_empty() {
        return;
    }
    
    let id = uuid::Uuid::new_v4().to_string();
    let _ = sqlx::query(
        r#"
        INSERT INTO search_history (id, query, result_count, searched_at)
        VALUES (?, ?, 0, datetime('now'))
        "#
    )
    .bind(&id)
    .bind(query.trim())
    .execute(pool)
    .await;
}

async fn search_local_media(
    state: &AppState,
    query: &str,
    media_type: &Option<String>,
) -> Result<Vec<MediaItem>, anyhow::Error> {
    // 使用数据库服务进行搜索
    let results = state.db_service.search_media(query).await?;
    
    // 如果指定了媒体类型，进行过滤
    if let Some(media_type_str) = media_type {
        let filtered_results = results.into_iter()
            .filter(|item| {
                match media_type_str.as_str() {
                    "movie" => item.media_type == "Movie",
                    "tv" => item.media_type == "Scene",
                    _ => true,
                }
            })
            .collect();
        Ok(filtered_results)
    } else {
        Ok(results)
    }
}

async fn search_tmdb_media(
    state: &AppState,
    query: &str,
    media_type: &Option<String>,
    page: u32,
) -> Result<Vec<MediaItem>, anyhow::Error> {
    let mut results = Vec::new();
    
    match media_type.as_deref() {
        Some("movie") => {
            let movies = state.external_client.search_movies(query, Some(page)).await?;
            results.extend(movies);
        }
        Some("tv") => {
            let tv_shows = state.external_client.search_tv_shows(query, Some(page)).await?;
            results.extend(tv_shows);
        }
        _ => {
            // 搜索所有类型
            let movies = state.external_client.search_movies(query, Some(page)).await?;
            let tv_shows = state.external_client.search_tv_shows(query, Some(page)).await?;
            results.extend(movies);
            results.extend(tv_shows);
        }
    }
    
    Ok(results)
}

async fn advanced_search_local(
    state: &AppState,
    request: &AdvancedSearchRequest,
) -> Result<Vec<MediaItem>, anyhow::Error> {
    // 构建搜索过滤器
    let year_range = match (request.year_from, request.year_to) {
        (Some(from), Some(to)) => Some((from, to)),
        (Some(from), None) => Some((from, 2100)),
        (None, Some(to)) => Some((1800, to)),
        (None, None) => None,
    };
    
    let rating_range = match (request.rating_min, request.rating_max) {
        (Some(min), Some(max)) => Some((min, max)),
        (Some(min), None) => Some((min, 10.0)),
        (None, Some(max)) => Some((0.0, max)),
        (None, None) => None,
    };
    
    let genres = request.genre.clone().map(|g| vec![g]).unwrap_or_default();
    
    let filters = crate::models::SearchFilters {
        query: request.query.clone(),
        media_type: request.media_type.clone(),
        genres,
        year_range,
        rating_range,
        watch_status: None,
        actor_id: request.actor_id.clone(),
        studio: request.studio.clone(),
        series: request.series.clone(),
        sort_by: crate::models::SortOption::Rating,
        sort_order: crate::models::SortOrder::Descending,
        limit: Some(50),
        offset: Some(((request.page.unwrap_or(1) - 1) * 20) as i32),
    };
    
    // 使用数据库服务进行高级搜索
    state.db_service.search_with_filters(&filters).await
}

fn filter_tmdb_results(
    results: Vec<MediaItem>,
    request: &AdvancedSearchRequest,
) -> Vec<MediaItem> {
    results.into_iter()
        .filter(|item| {
            // 年份过滤
            if let (Some(year_from), Some(year)) = (request.year_from, item.year) {
                if year < year_from {
                    return false;
                }
            }
            
            if let (Some(year_to), Some(year)) = (request.year_to, item.year) {
                if year > year_to {
                    return false;
                }
            }
            
            // 评分过滤
            if let (Some(rating_min), Some(rating)) = (request.rating_min, item.rating) {
                if rating < rating_min {
                    return false;
                }
            }
            
            if let (Some(rating_max), Some(rating)) = (request.rating_max, item.rating) {
                if rating > rating_max {
                    return false;
                }
            }
            
            // 类型过滤
            if let Some(ref req_type) = request.media_type {
                let req_type_str = format!("{:?}", req_type);
                if item.media_type != req_type_str {
                    return false;
                }
            }
            
            // 类型过滤（基于genres）
            if let Some(ref genre) = request.genre {
                if let Ok(genres) = item.get_genres() {
                    if !genres.iter().any(|g: &String| g.to_lowercase().contains(&genre.to_lowercase())) {
                        return false;
                    }
                }
            }
            
            true
        })
        .collect()
}

fn deduplicate_results(mut results: Vec<MediaItem>) -> Vec<MediaItem> {
    // 基于TMDB ID去重，优先保留有更多信息的条目
    let mut seen_tmdb_ids = std::collections::HashSet::new();
    let mut unique_results = Vec::new();
    
    // 按信息完整度排序（有更多字段的排在前面）
    results.sort_by(|a, b| {
        let a_score = calculate_completeness_score(a);
        let b_score = calculate_completeness_score(b);
        b_score.cmp(&a_score)
    });
    
    for item in results {
        if let Ok(external_ids) = item.get_external_ids() {
            if let Some(tmdb_id) = external_ids.tmdb_id {
                if !seen_tmdb_ids.contains(&tmdb_id) {
                    seen_tmdb_ids.insert(tmdb_id);
                    unique_results.push(item);
                }
            } else {
                // 没有TMDB ID的项目直接添加
                unique_results.push(item);
            }
        } else {
            // 无法解析external_ids的项目直接添加
            unique_results.push(item);
        }
    }
    
    unique_results
}

fn calculate_completeness_score(item: &MediaItem) -> u32 {
    let mut score = 0u32;
    
    if item.overview.is_some() { score += 1; }
    if item.poster_url.is_some() { score += 1; }
    if item.backdrop_url.is_some() { score += 1; }
    if item.rating.is_some() { score += 1; }
    if let Ok(genres) = item.get_genres() {
        if !genres.is_empty() { score += 1; }
    }
    if let Ok(cast) = item.get_cast() {
        if !cast.is_empty() { score += 1; }
    }
    if let Ok(crew) = item.get_crew() {
        if !crew.is_empty() { score += 1; }
    }
    if item.runtime.is_some() { score += 1; }
    
    score
}