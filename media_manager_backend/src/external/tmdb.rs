use reqwest::Client;
use serde::{Deserialize, Serialize};
use anyhow::{Result, anyhow};

use crate::models::{MediaItem, MediaType, Person, ExternalIds, MediaItemFactory};

/// TMDB API客户端
#[derive(Clone)]
pub struct TmdbClient {
    client: Client,
    api_key: String,
    base_url: String,
}

impl TmdbClient {
    pub fn new(api_key: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            base_url: "https://api.themoviedb.org/3".to_string(),
        }
    }
    
    /// 搜索电影
    pub async fn search_movies(&self, query: &str, page: Option<u32>) -> Result<TmdbSearchResponse> {
        let url = format!("{}/search/movie", self.base_url);
        let page = page.unwrap_or(1);
        
        let response = self.client
            .get(&url)
            .query(&[
                ("api_key", &self.api_key),
                ("query", &query.to_string()),
                ("page", &page.to_string()),
                ("language", &"zh-CN".to_string()),
            ])
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow!("TMDB API error: {}", response.status()));
        }
        
        let search_result: TmdbSearchResponse = response.json().await?;
        Ok(search_result)
    }
    
    /// 搜索电视剧
    pub async fn search_tv_shows(&self, query: &str, page: Option<u32>) -> Result<TmdbTvSearchResponse> {
        let url = format!("{}/search/tv", self.base_url);
        let page = page.unwrap_or(1);
        
        let response = self.client
            .get(&url)
            .query(&[
                ("api_key", &self.api_key),
                ("query", &query.to_string()),
                ("page", &page.to_string()),
                ("language", &"zh-CN".to_string()),
            ])
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow!("TMDB API error: {}", response.status()));
        }
        
        let search_result: TmdbTvSearchResponse = response.json().await?;
        Ok(search_result)
    }
    
    /// 获取电影详情
    pub async fn get_movie_details(&self, movie_id: u32) -> Result<TmdbMovieDetails> {
        let url = format!("{}/movie/{}", self.base_url, movie_id);
        
        let response = self.client
            .get(&url)
            .query(&[
                ("api_key", &self.api_key),
                ("language", &"zh-CN".to_string()),
                ("append_to_response", &"credits,keywords".to_string()),
            ])
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow!("TMDB API error: {}", response.status()));
        }
        
        let movie_details: TmdbMovieDetails = response.json().await?;
        Ok(movie_details)
    }
    
    /// 获取电视剧详情
    pub async fn get_tv_details(&self, tv_id: u32) -> Result<TmdbTvDetails> {
        let url = format!("{}/tv/{}", self.base_url, tv_id);
        
        let response = self.client
            .get(&url)
            .query(&[
                ("api_key", &self.api_key),
                ("language", &"zh-CN".to_string()),
                ("append_to_response", &"credits,keywords".to_string()),
            ])
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow!("TMDB API error: {}", response.status()));
        }
        
        let tv_details: TmdbTvDetails = response.json().await?;
        Ok(tv_details)
    }
    
    /// 获取热门电影
    pub async fn get_popular_movies(&self, page: Option<u32>) -> Result<TmdbSearchResponse> {
        let url = format!("{}/movie/popular", self.base_url);
        let page = page.unwrap_or(1);
        
        let response = self.client
            .get(&url)
            .query(&[
                ("api_key", &self.api_key),
                ("page", &page.to_string()),
                ("language", &"zh-CN".to_string()),
            ])
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow!("TMDB API error: {}", response.status()));
        }
        
        let result: TmdbSearchResponse = response.json().await?;
        Ok(result)
    }
    
    /// 获取热门电视剧
    pub async fn get_popular_tv_shows(&self, page: Option<u32>) -> Result<TmdbTvSearchResponse> {
        let url = format!("{}/tv/popular", self.base_url);
        let page = page.unwrap_or(1);
        
        let response = self.client
            .get(&url)
            .query(&[
                ("api_key", &self.api_key),
                ("page", &page.to_string()),
                ("language", &"zh-CN".to_string()),
            ])
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow!("TMDB API error: {}", response.status()));
        }
        
        let result: TmdbTvSearchResponse = response.json().await?;
        Ok(result)
    }
    
    /// 构建图片URL
    pub fn build_image_url(&self, path: &str, size: ImageSize) -> String {
        let size_str = match size {
            ImageSize::W92 => "w92",
            ImageSize::W154 => "w154",
            ImageSize::W185 => "w185",
            ImageSize::W342 => "w342",
            ImageSize::W500 => "w500",
            ImageSize::W780 => "w780",
            ImageSize::Original => "original",
        };
        
        format!("https://image.tmdb.org/t/p/{}{}", size_str, path)
    }
}

/// 图片尺寸枚举
#[derive(Debug, Clone)]
pub enum ImageSize {
    W92,
    W154,
    W185,
    W342,
    W500,
    W780,
    Original,
}

/// TMDB搜索响应
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbSearchResponse {
    pub page: u32,
    pub results: Vec<TmdbMovie>,
    pub total_pages: u32,
    pub total_results: u32,
}

/// TMDB电视剧搜索响应
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbTvSearchResponse {
    pub page: u32,
    pub results: Vec<TmdbScene>,
    pub total_pages: u32,
    pub total_results: u32,
}

/// TMDB电影基本信息
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbMovie {
    pub id: u32,
    pub title: String,
    pub original_title: String,
    pub overview: Option<String>,
    pub release_date: Option<String>,
    pub poster_path: Option<String>,
    pub backdrop_path: Option<String>,
    pub vote_average: f32,
    pub vote_count: u32,
    pub genre_ids: Vec<u32>,
    pub adult: bool,
    pub original_language: String,
    pub popularity: f32,
}

/// TMDB电视剧基本信息
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbScene {
    pub id: u32,
    pub name: String,
    pub original_name: String,
    pub overview: Option<String>,
    pub first_air_date: Option<String>,
    pub poster_path: Option<String>,
    pub backdrop_path: Option<String>,
    pub vote_average: f32,
    pub vote_count: u32,
    pub genre_ids: Vec<u32>,
    pub original_language: String,
    pub popularity: f32,
    pub origin_country: Vec<String>,
}

/// TMDB电影详情
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbMovieDetails {
    pub id: u32,
    pub title: String,
    pub original_title: String,
    pub overview: Option<String>,
    pub release_date: Option<String>,
    pub poster_path: Option<String>,
    pub backdrop_path: Option<String>,
    pub vote_average: f32,
    pub vote_count: u32,
    pub runtime: Option<u32>,
    pub budget: u64,
    pub revenue: u64,
    pub status: String,
    pub tagline: Option<String>,
    pub genres: Vec<TmdbGenre>,
    pub production_countries: Vec<TmdbProductionCountry>,
    pub spoken_languages: Vec<TmdbSpokenLanguage>,
    pub credits: Option<TmdbCredits>,
    pub imdb_id: Option<String>,
    pub adult: bool,
    pub original_language: String,
    pub popularity: f32,
}

/// TMDB电视剧详情
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbTvDetails {
    pub id: u32,
    pub name: String,
    pub original_name: String,
    pub overview: Option<String>,
    pub first_air_date: Option<String>,
    pub last_air_date: Option<String>,
    pub poster_path: Option<String>,
    pub backdrop_path: Option<String>,
    pub vote_average: f32,
    pub vote_count: u32,
    pub number_of_episodes: u32,
    pub number_of_seasons: u32,
    pub status: String,
    pub tagline: Option<String>,
    pub genres: Vec<TmdbGenre>,
    pub production_countries: Vec<TmdbProductionCountry>,
    pub spoken_languages: Vec<TmdbSpokenLanguage>,
    pub credits: Option<TmdbCredits>,
    pub original_language: String,
    pub popularity: f32,
    pub origin_country: Vec<String>,
}

/// TMDB类型
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbGenre {
    pub id: u32,
    pub name: String,
}

/// TMDB制作国家
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbProductionCountry {
    pub iso_3166_1: String,
    pub name: String,
}

/// TMDB语言
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbSpokenLanguage {
    pub iso_639_1: String,
    pub name: String,
    pub english_name: String,
}

/// TMDB演职人员信息
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbCredits {
    pub cast: Vec<TmdbCastMember>,
    pub crew: Vec<TmdbCrewMember>,
}

/// TMDB演员
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbCastMember {
    pub id: u32,
    pub name: String,
    pub character: String,
    pub order: u32,
    pub profile_path: Option<String>,
    pub cast_id: u32,
    pub credit_id: String,
}

/// TMDB制作人员
#[derive(Debug, Deserialize, Serialize)]
pub struct TmdbCrewMember {
    pub id: u32,
    pub name: String,
    pub job: String,
    pub department: String,
    pub profile_path: Option<String>,
    pub credit_id: String,
}

/// 转换器：将TMDB数据转换为内部数据模型
pub struct TmdbConverter;

impl TmdbConverter {
    /// 将TMDB电影转换为MediaItem
    pub fn movie_to_media_item(movie: &TmdbMovie, tmdb_client: &TmdbClient) -> Result<MediaItem> {
        let external_ids = ExternalIds {
            tmdb_id: Some(movie.id as i32),
            imdb_id: None,
            omdb_id: None,
        };
        
        let year = movie.release_date.as_ref()
            .and_then(|date| date.split('-').next())
            .and_then(|year_str| year_str.parse().ok());
            
        let poster_url = movie.poster_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W500));
            
        let backdrop_url = movie.backdrop_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W780));
        
        Ok(MediaItemFactory::from_external_data(
            movie.title.clone(),
            MediaType::Movie,
            external_ids,
            year,
            movie.overview.clone(),
            Vec::new(), // 需要从genre_ids转换
            Some(movie.vote_average),
            poster_url,
            backdrop_url,
        )?)
    }
    
    /// 将TMDB电视剧转换为MediaItem
    pub fn scene_to_media_item(scene: &TmdbScene, tmdb_client: &TmdbClient) -> Result<MediaItem> {
        let external_ids = ExternalIds {
            tmdb_id: Some(scene.id as i32),
            imdb_id: None,
            omdb_id: None,
        };
        
        let year = scene.first_air_date.as_ref()
            .and_then(|date| date.split('-').next())
            .and_then(|year_str| year_str.parse().ok());
            
        let poster_url = scene.poster_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W500));
            
        let backdrop_url = scene.backdrop_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W780));
        
        Ok(MediaItemFactory::from_external_data(
            scene.name.clone(),
            MediaType::Scene,
            external_ids,
            year,
            scene.overview.clone(),
            Vec::new(), // 需要从genre_ids转换
            Some(scene.vote_average),
            poster_url,
            backdrop_url,
        )?)
    }
    
    /// 将TMDB电影详情转换为MediaItem
    pub fn movie_details_to_media_item(details: &TmdbMovieDetails, tmdb_client: &TmdbClient) -> Result<MediaItem> {
        let external_ids = ExternalIds {
            tmdb_id: Some(details.id as i32),
            imdb_id: details.imdb_id.clone(),
            omdb_id: None,
        };
        
        let year = details.release_date.as_ref()
            .and_then(|date| date.split('-').next())
            .and_then(|year_str| year_str.parse().ok());
            
        let poster_url = details.poster_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W500));
            
        let backdrop_url = details.backdrop_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W780));
            
        let genres: Vec<String> = details.genres.iter()
            .map(|g| g.name.clone())
            .collect();
        
        let mut media = MediaItemFactory::from_external_data(
            details.title.clone(),
            MediaType::Movie,
            external_ids,
            year,
            details.overview.clone(),
            genres,
            Some(details.vote_average),
            poster_url,
            backdrop_url,
        )?;
        
        // 设置额外信息
        media.original_title = Some(details.original_title.clone());
        media.set_runtime(details.runtime.map(|r| r as i32))?;
        media.set_budget(Some(details.budget as i64))?;
        media.set_revenue(Some(details.revenue as i64))?;
        media.status = Some(details.status.clone());
        media.vote_count = Some(details.vote_count as i32);
        
        // 设置语言和国家
        if let Some(lang) = details.spoken_languages.first() {
            media.set_language(Some(lang.iso_639_1.clone()))?;
        }
        
        if let Some(country) = details.production_countries.first() {
            media.set_country(Some(country.iso_3166_1.clone()))?;
        }
        
        // 转换演职人员信息
        if let Some(ref credits) = details.credits {
            let cast: Vec<Person> = credits.cast.iter()
                .take(20) // 限制演员数量
                .map(|c| Person::with_character(c.name.clone(), "演员".to_string(), c.character.clone()))
                .collect();
            media.set_cast(&cast)?;
            
            let crew: Vec<Person> = credits.crew.iter()
                .filter(|c| ["Director", "Writer", "Producer"].contains(&c.job.as_str()))
                .take(10) // 限制制作人员数量
                .map(|c| Person::new(c.name.clone(), c.job.clone()))
                .collect();
            media.set_crew(&crew)?;
        }
        
        Ok(media)
    }
    
    /// 将TMDB电视剧详情转换为MediaItem
    pub fn tv_details_to_media_item(details: &TmdbTvDetails, tmdb_client: &TmdbClient) -> Result<MediaItem> {
        let external_ids = ExternalIds {
            tmdb_id: Some(details.id as i32),
            imdb_id: None,
            omdb_id: None,
        };
        
        let year = details.first_air_date.as_ref()
            .and_then(|date| date.split('-').next())
            .and_then(|year_str| year_str.parse().ok());
            
        let poster_url = details.poster_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W500));
            
        let backdrop_url = details.backdrop_path.as_ref()
            .map(|path| tmdb_client.build_image_url(path, ImageSize::W780));
            
        let genres: Vec<String> = details.genres.iter()
            .map(|g| g.name.clone())
            .collect();
        
        let mut media = MediaItemFactory::from_external_data(
            details.name.clone(),
            MediaType::Scene,
            external_ids,
            year,
            details.overview.clone(),
            genres,
            Some(details.vote_average),
            poster_url,
            backdrop_url,
        )?;
        
        // 设置额外信息
        media.original_title = Some(details.original_name.clone());
        media.status = Some(details.status.clone());
        media.vote_count = Some(details.vote_count as i32);
        
        // 设置语言和国家
        if let Some(lang) = details.spoken_languages.first() {
            media.set_language(Some(lang.iso_639_1.clone()))?;
        }
        
        if let Some(country) = details.origin_country.first() {
            media.set_country(Some(country.clone()))?;
        }
        
        // 转换演职人员信息
        if let Some(ref credits) = details.credits {
            let cast: Vec<Person> = credits.cast.iter()
                .take(20) // 限制演员数量
                .map(|c| Person::with_character(c.name.clone(), "演员".to_string(), c.character.clone()))
                .collect();
            media.set_cast(&cast)?;
            
            let crew: Vec<Person> = credits.crew.iter()
                .filter(|c| ["Director", "Writer", "Producer", "Creator"].contains(&c.job.as_str()))
                .take(10) // 限制制作人员数量
                .map(|c| Person::new(c.name.clone(), c.job.clone()))
                .collect();
            media.set_crew(&crew)?;
        }
        
        Ok(media)
    }
}