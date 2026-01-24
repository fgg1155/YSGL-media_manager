use sqlx::SqlitePool;
use crate::models::{
    Actor, ActorMedia, ActorWithWorkCount, ActorFilmography, 
    ActorDetailResponse, MediaActor, CreateActorRequest, UpdateActorRequest,
    ActorSearchFilters, ActorListResponse,
};

/// 创建演员（从请求）
pub async fn create_actor(pool: &SqlitePool, request: CreateActorRequest) -> Result<Actor, sqlx::Error> {
    let actor = Actor::from_create_request(request)
        .map_err(|e| sqlx::Error::Protocol(format!("Validation error: {}", e)))?;
    insert_actor(pool, &actor).await?;
    Ok(actor)
}

/// 插入演员（从 Actor 对象）
pub async fn insert_actor(pool: &SqlitePool, actor: &Actor) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO actors (id, name, avatar_url, photo_url, poster_url, backdrop_url, biography, birth_date, nationality, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#
    )
    .bind(&actor.id)
    .bind(&actor.name)
    .bind(&actor.avatar_url)
    .bind(&actor.photo_url)
    .bind(&actor.poster_url)
    .bind(&actor.backdrop_url)
    .bind(&actor.biography)
    .bind(&actor.birth_date)
    .bind(&actor.nationality)
    .bind(&actor.created_at)
    .bind(&actor.updated_at)
    .execute(pool)
    .await?;
    
    Ok(())
}

/// 获取演员
pub async fn get_actor(pool: &SqlitePool, id: &str) -> Result<Option<Actor>, sqlx::Error> {
    sqlx::query_as::<_, Actor>(
        "SELECT * FROM actors WHERE id = ?"
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// 根据名字查找演员
pub async fn find_actor_by_name(pool: &SqlitePool, name: &str) -> Result<Option<Actor>, sqlx::Error> {
    sqlx::query_as::<_, Actor>(
        "SELECT * FROM actors WHERE name = ? COLLATE NOCASE"
    )
    .bind(name)
    .fetch_optional(pool)
    .await
}

/// 更新演员
pub async fn update_actor(pool: &SqlitePool, id: &str, request: UpdateActorRequest) -> Result<Option<Actor>, sqlx::Error> {
    let actor = get_actor(pool, id).await?;
    
    if let Some(mut actor) = actor {
        actor.apply_update(request);
        
        sqlx::query(
            r#"
            UPDATE actors 
            SET name = ?, avatar_url = ?, photo_url = ?, poster_url = ?, backdrop_url = ?, biography = ?, birth_date = ?, nationality = ?, updated_at = ?
            WHERE id = ?
            "#
        )
        .bind(&actor.name)
        .bind(&actor.avatar_url)
        .bind(&actor.photo_url)
        .bind(&actor.poster_url)
        .bind(&actor.backdrop_url)
        .bind(&actor.biography)
        .bind(&actor.birth_date)
        .bind(&actor.nationality)
        .bind(&actor.updated_at)
        .bind(&actor.id)
        .execute(pool)
        .await?;
        
        Ok(Some(actor))
    } else {
        Ok(None)
    }
}

/// 直接更新演员对象
pub async fn update_actor_direct(pool: &SqlitePool, actor: &Actor) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE actors 
        SET name = ?, avatar_url = ?, photo_url = ?, poster_url = ?, backdrop_url = ?, biography = ?, birth_date = ?, nationality = ?, updated_at = datetime('now')
        WHERE id = ?
        "#
    )
    .bind(&actor.name)
    .bind(&actor.avatar_url)
    .bind(&actor.photo_url)
    .bind(&actor.poster_url)
    .bind(&actor.backdrop_url)
    .bind(&actor.biography)
    .bind(&actor.birth_date)
    .bind(&actor.nationality)
    .bind(&actor.id)
    .execute(pool)
    .await?;
    
    Ok(())
}

/// 删除演员（级联删除关联）
pub async fn delete_actor(pool: &SqlitePool, id: &str) -> Result<bool, sqlx::Error> {
    // 先删除演员与媒体的关联
    sqlx::query("DELETE FROM actor_media WHERE actor_id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    
    // 再删除演员本身
    let result = sqlx::query("DELETE FROM actors WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    
    Ok(result.rows_affected() > 0)
}

/// 列出演员（带分页和搜索）
pub async fn list_actors(pool: &SqlitePool, filters: &ActorSearchFilters) -> Result<ActorListResponse, sqlx::Error> {
    let limit = filters.limit.unwrap_or(20);
    let offset = filters.offset.unwrap_or(0);
    
    // 使用 LEFT JOIN 一次性获取演员和作品数量，避免 N+1 查询
    let (actors_with_count, total) = if let Some(ref query) = filters.query {
        let search_pattern = format!("%{}%", query);
        
        // 查询演员列表和作品数量
        let actors_with_count: Vec<ActorWithWorkCount> = sqlx::query_as(
            r#"
            SELECT 
                a.id, a.name, a.avatar_url, a.photo_url, a.poster_url, 
                a.backdrop_url, a.biography, a.birth_date, a.nationality,
                a.created_at, a.updated_at,
                COUNT(am.id) as work_count
            FROM actors a
            LEFT JOIN actor_media am ON a.id = am.actor_id
            WHERE a.name LIKE ?
            GROUP BY a.id
            ORDER BY a.name ASC
            LIMIT ? OFFSET ?
            "#
        )
        .bind(&search_pattern)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        
        // 查询总数
        let total: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM actors WHERE name LIKE ?"
        )
        .bind(&search_pattern)
        .fetch_one(pool)
        .await?;
        
        (actors_with_count, total.0)
    } else {
        // 查询演员列表和作品数量
        let actors_with_count: Vec<ActorWithWorkCount> = sqlx::query_as(
            r#"
            SELECT 
                a.id, a.name, a.avatar_url, a.photo_url, a.poster_url, 
                a.backdrop_url, a.biography, a.birth_date, a.nationality,
                a.created_at, a.updated_at,
                COUNT(am.id) as work_count
            FROM actors a
            LEFT JOIN actor_media am ON a.id = am.actor_id
            GROUP BY a.id
            ORDER BY a.name ASC
            LIMIT ? OFFSET ?
            "#
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        
        // 查询总数
        let total: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM actors"
        )
        .fetch_one(pool)
        .await?;
        
        (actors_with_count, total.0)
    };
    
    Ok(ActorListResponse {
        actors: actors_with_count,
        total,
        limit,
        offset,
    })
}


/// 获取演员详情（包含作品列表）
pub async fn get_actor_with_filmography(pool: &SqlitePool, id: &str) -> Result<Option<ActorDetailResponse>, sqlx::Error> {
    let actor = get_actor(pool, id).await?;
    
    if let Some(actor) = actor {
        let filmography: Vec<ActorFilmography> = sqlx::query_as(
            r#"
            SELECT 
                m.id as media_id,
                m.title,
                m.year,
                m.poster_url,
                am.character_name,
                am.role
            FROM actor_media am
            JOIN media_items m ON am.media_id = m.id
            WHERE am.actor_id = ?
            ORDER BY m.year DESC NULLS LAST
            "#
        )
        .bind(&actor.id)
        .fetch_all(pool)
        .await?;
        
        Ok(Some(ActorDetailResponse {
            actor,
            filmography,
        }))
    } else {
        Ok(None)
    }
}

/// 按名称查找或创建演员
pub async fn find_or_create_actor_by_name(pool: &SqlitePool, name: &str) -> Result<Actor, sqlx::Error> {
    // 先查找
    let existing: Option<Actor> = sqlx::query_as(
        "SELECT * FROM actors WHERE name = ?"
    )
    .bind(name)
    .fetch_optional(pool)
    .await?;
    
    if let Some(actor) = existing {
        return Ok(actor);
    }
    
    // 不存在则创建
    let request = CreateActorRequest {
        id: None,  // 让后端生成 UUID
        name: name.to_string(),
        avatar_url: None,
        photo_url: None,
        poster_url: None,
        backdrop_url: None,
        biography: None,
        birth_date: None,
        nationality: None,
    };
    
    create_actor(pool, request).await
}

/// 添加演员到媒体
pub async fn add_actor_to_media(
    pool: &SqlitePool, 
    actor_id: &str, 
    media_id: &str, 
    character_name: Option<String>,
    role: Option<String>,
) -> Result<ActorMedia, sqlx::Error> {
    // 检查是否已存在
    let existing: Option<ActorMedia> = sqlx::query_as(
        "SELECT * FROM actor_media WHERE actor_id = ? AND media_id = ?"
    )
    .bind(actor_id)
    .bind(media_id)
    .fetch_optional(pool)
    .await?;
    
    if let Some(relation) = existing {
        return Ok(relation);
    }
    
    let relation = ActorMedia::new(
        actor_id.to_string(),
        media_id.to_string(),
        character_name,
        role,
    );
    
    sqlx::query(
        r#"
        INSERT INTO actor_media (id, actor_id, media_id, character_name, role, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        "#
    )
    .bind(&relation.id)
    .bind(&relation.actor_id)
    .bind(&relation.media_id)
    .bind(&relation.character_name)
    .bind(&relation.role)
    .bind(&relation.created_at)
    .execute(pool)
    .await?;
    
    Ok(relation)
}

/// 从媒体移除演员
pub async fn remove_actor_from_media(pool: &SqlitePool, actor_id: &str, media_id: &str) -> Result<bool, sqlx::Error> {
    let result = sqlx::query(
        "DELETE FROM actor_media WHERE actor_id = ? AND media_id = ?"
    )
    .bind(actor_id)
    .bind(media_id)
    .execute(pool)
    .await?;
    
    Ok(result.rows_affected() > 0)
}

/// 获取媒体的所有演员
pub async fn get_actors_for_media(pool: &SqlitePool, media_id: &str) -> Result<Vec<MediaActor>, sqlx::Error> {
    sqlx::query_as(
        r#"
        SELECT 
            a.id,
            a.name,
            a.avatar_url,
            a.photo_url,
            am.character_name,
            am.role
        FROM actor_media am
        JOIN actors a ON am.actor_id = a.id
        WHERE am.media_id = ?
        ORDER BY am.created_at ASC
        "#
    )
    .bind(media_id)
    .fetch_all(pool)
    .await
}

/// 获取演员的所有媒体ID
pub async fn get_media_ids_for_actor(pool: &SqlitePool, actor_id: &str) -> Result<Vec<String>, sqlx::Error> {
    let rows: Vec<(String,)> = sqlx::query_as(
        "SELECT media_id FROM actor_media WHERE actor_id = ?"
    )
    .bind(actor_id)
    .fetch_all(pool)
    .await?;
    
    Ok(rows.into_iter().map(|r| r.0).collect())
}
