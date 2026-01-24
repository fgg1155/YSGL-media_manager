use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use std::fmt;

/// 统一的API错误类型
#[derive(Debug)]
pub enum ApiError {
    /// 数据库错误
    Database(sqlx::Error),
    /// 未找到资源
    NotFound(String),
    /// 验证错误
    Validation(String),
    /// 权限错误
    Unauthorized(String),
    /// 禁止访问
    Forbidden(String),
    /// 冲突错误（如重复创建）
    Conflict(String),
    /// 内部服务器错误
    Internal(String),
    /// 外部服务错误
    ExternalService(String),
    /// 请求参数错误
    BadRequest(String),
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ApiError::Database(e) => write!(f, "Database error: {}", e),
            ApiError::NotFound(msg) => write!(f, "Not found: {}", msg),
            ApiError::Validation(msg) => write!(f, "Validation error: {}", msg),
            ApiError::Unauthorized(msg) => write!(f, "Unauthorized: {}", msg),
            ApiError::Forbidden(msg) => write!(f, "Forbidden: {}", msg),
            ApiError::Conflict(msg) => write!(f, "Conflict: {}", msg),
            ApiError::Internal(msg) => write!(f, "Internal error: {}", msg),
            ApiError::ExternalService(msg) => write!(f, "External service error: {}", msg),
            ApiError::BadRequest(msg) => write!(f, "Bad request: {}", msg),
        }
    }
}

impl std::error::Error for ApiError {}

/// 从sqlx::Error转换
impl From<sqlx::Error> for ApiError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => ApiError::NotFound("Resource not found".to_string()),
            _ => ApiError::Database(err),
        }
    }
}

/// 从anyhow::Error转换
impl From<anyhow::Error> for ApiError {
    fn from(err: anyhow::Error) -> Self {
        ApiError::Internal(err.to_string())
    }
}

/// 实现IntoResponse，将错误转换为HTTP响应
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_type, message) = match self {
            ApiError::Database(ref e) => {
                tracing::error!("Database error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "database_error",
                    "An internal database error occurred".to_string(),
                )
            }
            ApiError::NotFound(ref msg) => (StatusCode::NOT_FOUND, "not_found", msg.clone()),
            ApiError::Validation(ref msg) => {
                (StatusCode::UNPROCESSABLE_ENTITY, "validation_error", msg.clone())
            }
            ApiError::Unauthorized(ref msg) => {
                (StatusCode::UNAUTHORIZED, "unauthorized", msg.clone())
            }
            ApiError::Forbidden(ref msg) => (StatusCode::FORBIDDEN, "forbidden", msg.clone()),
            ApiError::Conflict(ref msg) => (StatusCode::CONFLICT, "conflict", msg.clone()),
            ApiError::Internal(ref msg) => {
                tracing::error!("Internal error: {}", msg);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal_error",
                    "An internal server error occurred".to_string(),
                )
            }
            ApiError::ExternalService(ref msg) => {
                tracing::error!("External service error: {}", msg);
                (
                    StatusCode::BAD_GATEWAY,
                    "external_service_error",
                    msg.clone(),
                )
            }
            ApiError::BadRequest(ref msg) => {
                (StatusCode::BAD_REQUEST, "bad_request", msg.clone())
            }
        };

        let body = Json(json!({
            "success": false,
            "error": {
                "type": error_type,
                "message": message,
            }
        }));

        (status, body).into_response()
    }
}

/// Result类型别名
pub type ApiResult<T> = Result<T, ApiError>;

/// 辅助宏：快速创建错误
#[macro_export]
macro_rules! api_error {
    (NotFound, $msg:expr) => {
        $crate::api::error::ApiError::NotFound($msg.to_string())
    };
    (Validation, $msg:expr) => {
        $crate::api::error::ApiError::Validation($msg.to_string())
    };
    (BadRequest, $msg:expr) => {
        $crate::api::error::ApiError::BadRequest($msg.to_string())
    };
    (Internal, $msg:expr) => {
        $crate::api::error::ApiError::Internal($msg.to_string())
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let error = ApiError::NotFound("User not found".to_string());
        assert_eq!(error.to_string(), "Not found: User not found");
    }

    #[test]
    fn test_error_conversion() {
        let sqlx_error = sqlx::Error::RowNotFound;
        let api_error: ApiError = sqlx_error.into();
        assert!(matches!(api_error, ApiError::NotFound(_)));
    }
}
