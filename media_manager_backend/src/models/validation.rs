use thiserror::Error;

/// 验证错误类型
#[derive(Error, Debug)]
pub enum ValidationError {
    #[error("Title cannot be empty")]
    EmptyTitle,
    
    #[error("Title is too long (max 500 characters)")]
    TitleTooLong,
    
    #[error("Invalid ID format (must be a valid UUID)")]
    InvalidId,
    
    #[error("Invalid year: {0} (must be between 1800 and 2100)")]
    InvalidYear(i32),
    
    #[error("Invalid rating: {0} (must be between 0.0 and 10.0)")]
    InvalidRating(f32),
    
    #[error("Invalid runtime: {0} (must be positive)")]
    InvalidRuntime(i32),
    
    #[error("Invalid progress: {0} (must be between 0.0 and 1.0)")]
    InvalidProgress(f32),
    
    #[error("Overview is too long (max 2000 characters)")]
    OverviewTooLong,
    
    #[error("Invalid URL format: {0}")]
    InvalidUrl(String),
    
    #[error("Invalid language code: {0} (must be ISO 639-1 format)")]
    InvalidLanguageCode(String),
    
    #[error("Invalid country code: {0} (must be ISO 3166-1 format)")]
    InvalidCountryCode(String),
    
    #[error("Budget cannot be negative")]
    NegativeBudget,
    
    #[error("Revenue cannot be negative")]
    NegativeRevenue,
    
    #[error("Notes are too long (max 1000 characters)")]
    NotesTooLong,
    
    #[error("Too many genres (max 10)")]
    TooManyGenres,
    
    #[error("Genre name is too long (max 50 characters)")]
    GenreNameTooLong,
    
    #[error("Too many cast members (max 50)")]
    TooManyCastMembers,
    
    #[error("Too many crew members (max 100)")]
    TooManyCrewMembers,
    
    #[error("Person name cannot be empty")]
    EmptyPersonName,
    
    #[error("Person name is too long (max 100 characters)")]
    PersonNameTooLong,
    
    #[error("Role is too long (max 100 characters)")]
    RoleTooLong,
    
    #[error("Character name is too long (max 100 characters)")]
    CharacterNameTooLong,
    
    #[error("Invalid JSON data")]
    InvalidJson,
}

/// 验证器trait
pub trait Validator {
    type Error;
    
    fn validate(&self) -> Result<(), Self::Error>;
}

/// 字符串验证工具
pub struct StringValidator;

impl StringValidator {
    pub fn validate_title(title: &str) -> Result<(), ValidationError> {
        if title.trim().is_empty() {
            return Err(ValidationError::EmptyTitle);
        }
        
        if title.len() > 500 {
            return Err(ValidationError::TitleTooLong);
        }
        
        Ok(())
    }
    
    pub fn validate_overview(overview: &Option<String>) -> Result<(), ValidationError> {
        if let Some(text) = overview {
            if text.len() > 2000 {
                return Err(ValidationError::OverviewTooLong);
            }
        }
        Ok(())
    }
    
    pub fn validate_notes(notes: &Option<String>) -> Result<(), ValidationError> {
        if let Some(text) = notes {
            if text.len() > 1000 {
                return Err(ValidationError::NotesTooLong);
            }
        }
        Ok(())
    }
    
    pub fn validate_url(url: &Option<String>) -> Result<(), ValidationError> {
        if let Some(url_str) = url {
            if !url_str.is_empty() && !url_str.starts_with("http") {
                return Err(ValidationError::InvalidUrl(url_str.clone()));
            }
        }
        Ok(())
    }
    
    pub fn validate_language_code(code: &Option<String>) -> Result<(), ValidationError> {
        if let Some(lang) = code {
            if !lang.is_empty() && lang.len() != 2 {
                return Err(ValidationError::InvalidLanguageCode(lang.clone()));
            }
        }
        Ok(())
    }
    
    pub fn validate_country_code(code: &Option<String>) -> Result<(), ValidationError> {
        if let Some(country) = code {
            if !country.is_empty() && country.len() != 2 {
                return Err(ValidationError::InvalidCountryCode(country.clone()));
            }
        }
        Ok(())
    }
}

/// 数值验证工具
pub struct NumberValidator;

impl NumberValidator {
    pub fn validate_year(year: &Option<i32>) -> Result<(), ValidationError> {
        if let Some(y) = year {
            if *y < 1800 || *y > 2100 {
                return Err(ValidationError::InvalidYear(*y));
            }
        }
        Ok(())
    }
    
    pub fn validate_rating(rating: &Option<f32>) -> Result<(), ValidationError> {
        if let Some(r) = rating {
            if *r < 0.0 || *r > 10.0 {
                return Err(ValidationError::InvalidRating(*r));
            }
        }
        Ok(())
    }
    
    pub fn validate_runtime(runtime: &Option<i32>) -> Result<(), ValidationError> {
        if let Some(r) = runtime {
            if *r <= 0 {
                return Err(ValidationError::InvalidRuntime(*r));
            }
        }
        Ok(())
    }
    
    pub fn validate_progress(progress: &Option<f32>) -> Result<(), ValidationError> {
        if let Some(p) = progress {
            if *p < 0.0 || *p > 1.0 {
                return Err(ValidationError::InvalidProgress(*p));
            }
        }
        Ok(())
    }
    
    pub fn validate_budget(budget: &Option<i64>) -> Result<(), ValidationError> {
        if let Some(b) = budget {
            if *b < 0 {
                return Err(ValidationError::NegativeBudget);
            }
        }
        Ok(())
    }
    
    pub fn validate_revenue(revenue: &Option<i64>) -> Result<(), ValidationError> {
        if let Some(r) = revenue {
            if *r < 0 {
                return Err(ValidationError::NegativeRevenue);
            }
        }
        Ok(())
    }
}

/// 集合验证工具
pub struct CollectionValidator;

impl CollectionValidator {
    pub fn validate_genres(genres: &[String]) -> Result<(), ValidationError> {
        // 不再限制数量，而是在set_genres中自动截断
        // if genres.len() > 10 {
        //     return Err(ValidationError::TooManyGenres);
        // }
        
        for genre in genres {
            if genre.len() > 50 {
                return Err(ValidationError::GenreNameTooLong);
            }
        }
        
        Ok(())
    }
    
    pub fn validate_cast(cast: &[crate::models::Person]) -> Result<(), ValidationError> {
        if cast.len() > 50 {
            return Err(ValidationError::TooManyCastMembers);
        }
        
        for person in cast {
            PersonValidator::validate_person(person)?;
        }
        
        Ok(())
    }
    
    pub fn validate_crew(crew: &[crate::models::Person]) -> Result<(), ValidationError> {
        if crew.len() > 100 {
            return Err(ValidationError::TooManyCrewMembers);
        }
        
        for person in crew {
            PersonValidator::validate_person(person)?;
        }
        
        Ok(())
    }
}

/// 人员验证工具
pub struct PersonValidator;

impl PersonValidator {
    pub fn validate_person(person: &crate::models::Person) -> Result<(), ValidationError> {
        if person.name.trim().is_empty() {
            return Err(ValidationError::EmptyPersonName);
        }
        
        if person.name.len() > 100 {
            return Err(ValidationError::PersonNameTooLong);
        }
        
        if person.role.len() > 100 {
            return Err(ValidationError::RoleTooLong);
        }
        
        if let Some(ref character) = person.character {
            if character.len() > 100 {
                return Err(ValidationError::CharacterNameTooLong);
            }
        }
        
        Ok(())
    }
}