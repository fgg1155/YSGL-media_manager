use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;

/// 统一的API响应包装器
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

impl<T: Serialize> ApiResponse<T> {
    /// 创建成功响应
    pub fn success(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            message: None,
        }
    }

    /// 创建成功响应（带消息）
    pub fn success_with_message(data: T, message: impl Into<String>) -> Self {
        Self {
            success: true,
            data: Some(data),
            message: Some(message.into()),
        }
    }

    /// 创建成功响应（仅消息）
    pub fn message(message: impl Into<String>) -> ApiResponse<()> {
        ApiResponse {
            success: true,
            data: None,
            message: Some(message.into()),
        }
    }
}

impl<T: Serialize> IntoResponse for ApiResponse<T> {
    fn into_response(self) -> Response {
        Json(self).into_response()
    }
}

/// 分页响应
#[derive(Debug, Serialize)]
pub struct PaginatedResponse<T: Serialize> {
    pub items: Vec<T>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
    pub has_more: bool,
}

impl<T: Serialize> PaginatedResponse<T> {
    pub fn new(items: Vec<T>, total: i64, limit: i64, offset: i64) -> Self {
        let has_more = offset + (items.len() as i64) < total;
        Self {
            items,
            total,
            limit,
            offset,
            has_more,
        }
    }
}

impl<T: Serialize> IntoResponse for PaginatedResponse<T> {
    fn into_response(self) -> Response {
        Json(ApiResponse::success(self)).into_response()
    }
}

/// 批量操作响应
#[derive(Debug, Serialize)]
pub struct BatchResponse {
    pub success_count: usize,
    pub failure_count: usize,
    pub total: usize,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub errors: Vec<BatchError>,
}

#[derive(Debug, Serialize)]
pub struct BatchError {
    pub id: String,
    pub error: String,
}

impl BatchResponse {
    pub fn new(success_count: usize, failure_count: usize) -> Self {
        Self {
            success_count,
            failure_count,
            total: success_count + failure_count,
            errors: Vec::new(),
        }
    }

    pub fn with_errors(mut self, errors: Vec<BatchError>) -> Self {
        self.errors = errors;
        self
    }
}

impl IntoResponse for BatchResponse {
    fn into_response(self) -> Response {
        let status = if self.failure_count == 0 {
            StatusCode::OK
        } else if self.success_count == 0 {
            StatusCode::BAD_REQUEST
        } else {
            StatusCode::MULTI_STATUS
        };

        (status, Json(ApiResponse::success(self))).into_response()
    }
}

/// 辅助函数：创建成功响应
pub fn success<T: Serialize>(data: T) -> impl IntoResponse {
    ApiResponse::success(data)
}

/// 辅助函数：创建成功消息响应
pub fn success_message(message: impl Into<String>) -> impl IntoResponse {
    ApiResponse::<()>::message(message)
}

/// 辅助函数：创建分页响应
pub fn paginated<T: Serialize>(
    items: Vec<T>,
    total: i64,
    limit: i64,
    offset: i64,
) -> impl IntoResponse {
    PaginatedResponse::new(items, total, limit, offset)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_success_response() {
        let response = ApiResponse::success("test data");
        assert!(response.success);
        assert_eq!(response.data, Some("test data"));
        assert!(response.message.is_none());
    }

    #[test]
    fn test_paginated_response() {
        let items = vec![1, 2, 3];
        let response = PaginatedResponse::new(items, 10, 3, 0);
        assert_eq!(response.items.len(), 3);
        assert_eq!(response.total, 10);
        assert!(response.has_more);
    }

    #[test]
    fn test_batch_response() {
        let response = BatchResponse::new(5, 2);
        assert_eq!(response.success_count, 5);
        assert_eq!(response.failure_count, 2);
        assert_eq!(response.total, 7);
    }
}
