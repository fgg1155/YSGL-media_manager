use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

/// 演员实体
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Actor {
    pub id: String,
    pub name: String,
    pub avatar_url: Option<String>,    // 演员头像（圆形小头像，用于媒体详情页演员列表）
    pub photo_url: Option<String>,     // 演员写真/照片（多图，用于演员详情页相册展示）
    pub poster_url: Option<String>,    // 演员封面（竖版海报图，用于演员列表/卡片显示）
    pub backdrop_url: Option<String>,  // 背景图（横版大图，用于演员详情页背景）
    pub biography: Option<String>,
    pub birth_date: Option<String>,
    pub nationality: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// 演员-媒体关联
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ActorMedia {
    pub id: String,
    pub actor_id: String,
    pub media_id: String,
    pub character_name: Option<String>,
    pub role: String,
    pub created_at: DateTime<Utc>,
}

/// 带作品数量的演员（用于列表）
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ActorWithWorkCount {
    // Actor 字段（展开）
    pub id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub photo_url: Option<String>,
    pub poster_url: Option<String>,
    pub backdrop_url: Option<String>,
    pub biography: Option<String>,
    pub birth_date: Option<String>,
    pub nationality: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    // 作品数量
    pub work_count: i32,
}

/// 演员作品信息（用于演员详情页的作品列表）
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ActorFilmography {
    pub media_id: String,
    pub title: String,
    pub year: Option<i32>,
    pub poster_url: Option<String>,
    pub character_name: Option<String>,
    pub role: String,
}

/// 演员详情响应（包含作品列表）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActorDetailResponse {
    #[serde(flatten)]
    pub actor: Actor,
    pub filmography: Vec<ActorFilmography>,
}

/// 媒体中的演员信息（用于媒体详情页）
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct MediaActor {
    pub id: String,
    pub name: String,
    pub avatar_url: Option<String>,       // 演员头像（圆形小头像，用于媒体详情页演员列表）
    pub photo_url: Option<String>,        // 演员写真/照片（备用）
    pub character_name: Option<String>,
    pub role: String,
}

/// 创建演员请求
#[derive(Debug, Serialize, Deserialize)]
pub struct CreateActorRequest {
    pub id: Option<String>,               // 客户端提供的 UUID（可选）
    pub name: String,
    pub avatar_url: Option<String>,       // 演员头像（圆形小头像）
    pub photo_url: Option<String>,        // 演员写真/照片（多图）
    pub poster_url: Option<String>,       // 演员封面（竖版海报）
    pub backdrop_url: Option<String>,     // 背景图（横版大图）
    pub biography: Option<String>,
    pub birth_date: Option<String>,
    pub nationality: Option<String>,
}

/// 更新演员请求
#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateActorRequest {
    pub name: Option<String>,
    pub avatar_url: Option<String>,       // 演员头像（圆形小头像）
    pub photo_url: Option<String>,        // 演员写真/照片（多图）
    pub poster_url: Option<String>,       // 演员封面（竖版海报）
    pub backdrop_url: Option<String>,     // 背景图（横版大图）
    pub biography: Option<String>,
    pub birth_date: Option<String>,
    pub nationality: Option<String>,
}

/// 添加演员到媒体请求
#[derive(Debug, Serialize, Deserialize)]
pub struct AddActorToMediaRequest {
    pub actor_id: String,
    pub character_name: Option<String>,
    pub role: Option<String>,
}

/// 演员列表响应
#[derive(Debug, Serialize, Deserialize)]
pub struct ActorListResponse {
    pub actors: Vec<ActorWithWorkCount>,
    pub total: i64,
    pub limit: i32,
    pub offset: i32,
}

/// 演员搜索过滤器
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct ActorSearchFilters {
    pub query: Option<String>,
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

impl Actor {
    pub fn new(name: String) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            avatar_url: None,
            photo_url: None,
            poster_url: None,
            backdrop_url: None,
            biography: None,
            birth_date: None,
            nationality: None,
            created_at: now,
            updated_at: now,
        }
    }

    /// 使用客户端提供的 ID 创建新的演员
    pub fn new_with_id(id: String, name: String) -> Result<Self, crate::models::ValidationError> {
        // 验证 UUID 格式
        uuid::Uuid::parse_str(&id)
            .map_err(|_| crate::models::ValidationError::InvalidId)?;
        
        let now = Utc::now();
        Ok(Self {
            id,  // 使用提供的 ID
            name,
            avatar_url: None,
            photo_url: None,
            poster_url: None,
            backdrop_url: None,
            biography: None,
            birth_date: None,
            nationality: None,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn from_create_request(request: CreateActorRequest) -> Result<Self, crate::models::ValidationError> {
        // 如果请求包含 ID，使用客户端提供的 ID；否则生成新 ID
        let actor = if let Some(id) = request.id {
            Self::new_with_id(id, request.name)?
        } else {
            Self::new(request.name)
        };
        
        // 应用其他字段
        let now = Utc::now();
        Ok(Self {
            id: actor.id,
            name: actor.name,
            avatar_url: request.avatar_url,
            photo_url: request.photo_url,
            poster_url: request.poster_url,
            backdrop_url: request.backdrop_url,
            biography: request.biography,
            birth_date: request.birth_date,
            nationality: request.nationality,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn apply_update(&mut self, request: UpdateActorRequest) {
        if let Some(name) = request.name {
            self.name = name;
        }
        if let Some(avatar_url) = request.avatar_url {
            self.avatar_url = Some(avatar_url);
        }
        if let Some(photo_url) = request.photo_url {
            self.photo_url = Some(photo_url);
        }
        if let Some(poster_url) = request.poster_url {
            self.poster_url = Some(poster_url);
        }
        if let Some(backdrop_url) = request.backdrop_url {
            self.backdrop_url = Some(backdrop_url);
        }
        if let Some(biography) = request.biography {
            self.biography = Some(biography);
        }
        if let Some(birth_date) = request.birth_date {
            self.birth_date = Some(birth_date);
        }
        if let Some(nationality) = request.nationality {
            self.nationality = Some(nationality);
        }
        self.updated_at = Utc::now();
    }
}

impl ActorMedia {
    pub fn new(actor_id: String, media_id: String, character_name: Option<String>, role: Option<String>) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            actor_id,
            media_id,
            character_name,
            role: role.unwrap_or_else(|| "Actor".to_string()),
            created_at: Utc::now(),
        }
    }
}
