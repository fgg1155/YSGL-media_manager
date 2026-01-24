use crate::models::{SearchFilters, SortOption, SortOrder};
use sqlx::{QueryBuilder, Sqlite};

/// 动态查询构建器
pub struct MediaQueryBuilder {
    query: QueryBuilder<'static, Sqlite>,
    has_where: bool,
}

impl MediaQueryBuilder {
    pub fn new() -> Self {
        let query = QueryBuilder::new("SELECT * FROM media_items");
        Self {
            query,
            has_where: false,
        }
    }
    
    pub fn with_filters(mut self, filters: &SearchFilters) -> Self {
        // 文本搜索
        if let Some(ref q) = filters.query {
            if !q.trim().is_empty() {
                self.add_where_clause();
                self.query.push("(title LIKE ");
                self.query.push_bind(format!("%{}%", q));
                self.query.push(" OR original_title LIKE ");
                self.query.push_bind(format!("%{}%", q));
                self.query.push(" OR overview LIKE ");
                self.query.push_bind(format!("%{}%", q));
                self.query.push(")");
            }
        }
        
        // 媒体类型过滤
        if let Some(ref media_type) = filters.media_type {
            self.add_where_clause();
            self.query.push("media_type = ");
            self.query.push_bind(format!("{:?}", media_type));
        }
        
        // 年份范围过滤
        if let Some((min_year, max_year)) = filters.year_range {
            self.add_where_clause();
            self.query.push("year BETWEEN ");
            self.query.push_bind(min_year);
            self.query.push(" AND ");
            self.query.push_bind(max_year);
        }
        
        // 评分范围过滤
        if let Some((min_rating, max_rating)) = filters.rating_range {
            self.add_where_clause();
            self.query.push("rating BETWEEN ");
            self.query.push_bind(min_rating);
            self.query.push(" AND ");
            self.query.push_bind(max_rating);
        }
        
        // 类型过滤
        if !filters.genres.is_empty() {
            self.add_where_clause();
            self.query.push("(");
            for (i, genre) in filters.genres.iter().enumerate() {
                if i > 0 {
                    self.query.push(" OR ");
                }
                self.query.push("genres LIKE ");
                self.query.push_bind(format!("%{}%", genre));
            }
            self.query.push(")");
        }
        
        // 厂商过滤
        if let Some(ref studio) = filters.studio {
            if !studio.trim().is_empty() {
                self.add_where_clause();
                self.query.push("studio = ");
                self.query.push_bind(studio.clone());
            }
        }
        
        // 系列过滤
        if let Some(ref series) = filters.series {
            if !series.trim().is_empty() {
                self.add_where_clause();
                self.query.push("series = ");
                self.query.push_bind(series.clone());
            }
        }
        
        self
    }
    
    /// 添加演员过滤（需要 JOIN actor_media 表）
    pub fn with_actor_filter(mut self, filters: &SearchFilters) -> Self {
        if let Some(ref actor_id) = filters.actor_id {
            if !actor_id.trim().is_empty() {
                // 需要重建查询以包含 JOIN
                let current_sql = self.query.sql();
                if current_sql.starts_with("SELECT * FROM media_items") {
                    self.query = QueryBuilder::new(
                        "SELECT DISTINCT m.* FROM media_items m JOIN actor_media am ON m.id = am.media_id"
                    );
                } else if current_sql.starts_with("SELECT m.* FROM media_items m") && !current_sql.contains("actor_media") {
                    // 已经有其他 JOIN，添加 actor_media JOIN
                    let new_sql = current_sql.replace(
                        "FROM media_items m",
                        "FROM media_items m JOIN actor_media am ON m.id = am.media_id"
                    );
                    self.query = QueryBuilder::new(&new_sql);
                }
                self.has_where = false;
                
                self.add_where_clause();
                self.query.push("am.actor_id = ");
                self.query.push_bind(actor_id.clone());
            }
        }
        
        self
    }
    
    pub fn with_collection_filters(mut self, filters: &SearchFilters) -> Self {
        // 如果有观看状态过滤，需要JOIN collections表
        if filters.watch_status.is_some() {
            self.query = QueryBuilder::new(
                "SELECT m.* FROM media_items m JOIN collections c ON m.id = c.media_id"
            );
            self.has_where = false;
            
            if let Some(ref status) = filters.watch_status {
                self.add_where_clause();
                self.query.push("c.watch_status = ");
                self.query.push_bind(format!("{:?}", status));
            }
        }
        
        self
    }
    
    pub fn with_sorting(mut self, filters: &SearchFilters) -> Self {
        self.query.push(" ORDER BY ");
        
        match filters.sort_by {
            SortOption::Title => { self.query.push("title"); },
            SortOption::Year => { self.query.push("year"); },
            SortOption::Rating => { self.query.push("rating"); },
            SortOption::AddedDate => { self.query.push("created_at"); },
            SortOption::LastWatched => {
                // 如果按最后观看时间排序，需要JOIN collections表
                if !self.query.sql().contains("JOIN collections") {
                    // 重新构建查询以包含JOIN
                    let current_sql = self.query.sql().replace("SELECT * FROM media_items", 
                        "SELECT m.* FROM media_items m LEFT JOIN collections c ON m.id = c.media_id");
                    self.query = QueryBuilder::new(&current_sql);
                }
                self.query.push("c.last_watched");
            }
        }
        
        match filters.sort_order {
            SortOrder::Ascending => { self.query.push(" ASC"); },
            SortOrder::Descending => { self.query.push(" DESC"); },
        }
        
        self
    }
    
    pub fn with_pagination(mut self, filters: &SearchFilters) -> Self {
        if let Some(limit) = filters.limit {
            self.query.push(" LIMIT ");
            self.query.push_bind(limit);
        }
        
        if let Some(offset) = filters.offset {
            self.query.push(" OFFSET ");
            self.query.push_bind(offset);
        }
        
        self
    }
    
    pub fn build(self) -> QueryBuilder<'static, Sqlite> {
        self.query
    }
    
    fn add_where_clause(&mut self) {
        if !self.has_where {
            self.query.push(" WHERE ");
            self.has_where = true;
        } else {
            self.query.push(" AND ");
        }
    }
}

impl Default for MediaQueryBuilder {
    fn default() -> Self {
        Self::new()
    }
}

/// 全文搜索查询构建器
pub struct FullTextSearchBuilder {
    query: QueryBuilder<'static, Sqlite>,
}

impl FullTextSearchBuilder {
    pub fn new(search_query: &str) -> Self {
        // 添加通配符支持前缀匹配，例如 "fri" 可以匹配 "friends"
        let search_with_wildcard = format!("{}*", search_query.trim());
        
        let mut query = QueryBuilder::new(
            "SELECT m.* FROM media_items m JOIN media_search_fts fts ON m.id = fts.media_id WHERE media_search_fts MATCH "
        );
        query.push_bind(search_with_wildcard);
        
        Self { query }
    }
    
    pub fn with_ranking(mut self) -> Self {
        self.query.push(" ORDER BY rank");
        self
    }
    
    pub fn with_limit(mut self, limit: i32) -> Self {
        self.query.push(" LIMIT ");
        self.query.push_bind(limit);
        self
    }
    
    pub fn build(self) -> QueryBuilder<'static, Sqlite> {
        self.query
    }
}