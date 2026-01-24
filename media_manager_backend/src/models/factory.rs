use chrono::Utc;

use super::{
    MediaItem, Collection, MediaType, WatchStatus, Person, ExternalIds,
    AddToCollectionRequest, ValidationError
};

/// 媒体项目工厂
pub struct MediaItemFactory;

impl MediaItemFactory {
    /// 创建电影
    pub fn create_movie(title: String) -> Result<MediaItem, ValidationError> {
        MediaItem::new(title, MediaType::Movie)
    }
    
    /// 创建场景
    pub fn create_scene(title: String) -> Result<MediaItem, ValidationError> {
        MediaItem::new(title, MediaType::Scene)
    }
    
    /// 创建纪录片
    pub fn create_documentary(title: String) -> Result<MediaItem, ValidationError> {
        MediaItem::new(title, MediaType::Documentary)
    }
    
    /// 创建动漫
    pub fn create_anime(title: String) -> Result<MediaItem, ValidationError> {
        MediaItem::new(title, MediaType::Anime)
    }
    
    /// 从外部API数据创建媒体项目
    pub fn from_external_data(
        title: String,
        media_type: MediaType,
        external_ids: ExternalIds,
        year: Option<i32>,
        overview: Option<String>,
        genres: Vec<String>,
        rating: Option<f32>,
        poster_url: Option<String>,
        backdrop_url: Option<String>,
    ) -> Result<MediaItem, ValidationError> {
        let mut media = MediaItem::new(title, media_type)?;
        
        // set_external_ids 返回 serde_json::Error，需要转换
        media.set_external_ids(&external_ids)
            .map_err(|_| ValidationError::InvalidJson)?;
        
        if let Some(year) = year {
            media.set_year(Some(year))?;
        }
        
        if let Some(overview) = overview {
            media.set_overview(Some(overview))?;
        }
        
        if !genres.is_empty() {
            media.set_genres(&genres)?;
        }
        
        if let Some(rating) = rating {
            media.set_rating(Some(rating))?;
        }
        
        if let Some(poster_url) = poster_url {
            media.set_poster_url(Some(poster_url))?;
        }
        
        if let Some(backdrop_url) = backdrop_url {
            media.set_backdrop_url(Some(backdrop_url))?;
        }
        
        Ok(media)
    }
    
    /// 创建示例媒体项目（用于测试）
    pub fn create_sample_movie() -> Result<MediaItem, ValidationError> {
        let mut media = Self::create_movie("示例电影".to_string())?;
        media.set_year(Some(2023))?;
        media.set_overview(Some("这是一个示例电影的简介".to_string()))?;
        media.set_genres(&["动作".to_string(), "科幻".to_string()])?;
        media.set_rating(Some(8.5))?;
        media.set_runtime(Some(120))?;
        
        let cast = vec![
            Person::with_character("演员A".to_string(), "主演".to_string(), "角色A".to_string()),
            Person::with_character("演员B".to_string(), "主演".to_string(), "角色B".to_string()),
        ];
        media.set_cast(&cast)?;
        
        let crew = vec![
            Person::new("导演A".to_string(), "导演".to_string()),
            Person::new("编剧B".to_string(), "编剧".to_string()),
        ];
        media.set_crew(&crew)?;
        
        Ok(media)
    }
}

/// 收藏工厂
pub struct CollectionFactory;

impl CollectionFactory {
    /// 创建想看收藏
    pub fn create_want_to_watch(media_id: String) -> Collection {
        Collection::new(media_id, WatchStatus::WantToWatch)
    }
    
    /// 创建正在观看收藏
    pub fn create_watching(media_id: String) -> Collection {
        Collection::new(media_id, WatchStatus::Watching)
    }
    
    /// 创建已完成收藏
    pub fn create_completed(media_id: String) -> Collection {
        let mut collection = Collection::new(media_id, WatchStatus::Completed);
        collection.watch_progress = Some(1.0);
        collection.completed_at = Some(Utc::now());
        collection
    }
    
    /// 从请求创建收藏（带默认值）
    pub fn from_request_with_defaults(mut request: AddToCollectionRequest) -> Result<Collection, ValidationError> {
        // 设置默认值
        if request.watch_status.is_none() {
            request.watch_status = Some(WatchStatus::WantToWatch);
        }
        
        if request.user_tags.is_none() {
            request.user_tags = Some(Vec::new());
        }
        
        if request.is_favorite.is_none() {
            request.is_favorite = Some(false);
        }
        
        Collection::from_add_request(request)
    }
}

/// 人员工厂
pub struct PersonFactory;

impl PersonFactory {
    /// 创建演员
    pub fn create_actor(name: String, character: String) -> Person {
        Person::with_character(name, "演员".to_string(), character)
    }
    
    /// 创建导演
    pub fn create_director(name: String) -> Person {
        Person::new(name, "导演".to_string())
    }
    
    /// 创建编剧
    pub fn create_writer(name: String) -> Person {
        Person::new(name, "编剧".to_string())
    }
    
    /// 创建制片人
    pub fn create_producer(name: String) -> Person {
        Person::new(name, "制片人".to_string())
    }
    
    /// 创建摄影师
    pub fn create_cinematographer(name: String) -> Person {
        Person::new(name, "摄影师".to_string())
    }
    
    /// 创建音乐制作人
    pub fn create_composer(name: String) -> Person {
        Person::new(name, "音乐".to_string())
    }
}

/// 外部ID工厂
pub struct ExternalIdsFactory;

impl ExternalIdsFactory {
    /// 创建TMDB ID
    pub fn with_tmdb(tmdb_id: i32) -> ExternalIds {
        ExternalIds {
            tmdb_id: Some(tmdb_id),
            imdb_id: None,
            omdb_id: None,
        }
    }
    
    /// 创建IMDB ID
    pub fn with_imdb(imdb_id: String) -> ExternalIds {
        ExternalIds {
            tmdb_id: None,
            imdb_id: Some(imdb_id),
            omdb_id: None,
        }
    }
    
    /// 创建完整的外部ID
    pub fn complete(tmdb_id: Option<i32>, imdb_id: Option<String>, omdb_id: Option<String>) -> ExternalIds {
        ExternalIds {
            tmdb_id,
            imdb_id,
            omdb_id,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_media_item_factory() {
        let movie = MediaItemFactory::create_movie("测试电影".to_string())
            .expect("Should create movie");
        assert_eq!(movie.title, "测试电影");
        assert_eq!(
            movie.get_media_type().expect("Should get media type"),
            MediaType::Movie
        );
    }
    
    #[test]
    fn test_collection_factory() {
        let collection = CollectionFactory::create_want_to_watch("test_id".to_string());
        assert_eq!(collection.media_id, "test_id");
        assert_eq!(
            collection.get_watch_status().expect("Should get watch status"),
            WatchStatus::WantToWatch
        );
    }
    
    #[test]
    fn test_person_factory() {
        let actor = PersonFactory::create_actor("演员名".to_string(), "角色名".to_string());
        assert_eq!(actor.name, "演员名");
        assert_eq!(actor.role, "演员");
        assert_eq!(actor.character, Some("角色名".to_string()));
        
        let director = PersonFactory::create_director("导演名".to_string());
        assert_eq!(director.name, "导演名");
        assert_eq!(director.role, "导演");
        assert_eq!(director.character, None);
    }
}