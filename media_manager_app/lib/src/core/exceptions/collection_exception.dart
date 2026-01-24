/// Collection 相关异常
class CollectionException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const CollectionException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() {
    if (code != null) {
      return 'CollectionException [$code]: $message';
    }
    return 'CollectionException: $message';
  }
}

/// 收藏未找到异常
class CollectionNotFoundException extends CollectionException {
  CollectionNotFoundException(String mediaId)
      : super(
          'Collection not found for media: $mediaId',
          code: 'COLLECTION_NOT_FOUND',
        );
}

/// 收藏已存在异常
class CollectionAlreadyExistsException extends CollectionException {
  CollectionAlreadyExistsException(String mediaId)
      : super(
          'Collection already exists for media: $mediaId',
          code: 'COLLECTION_ALREADY_EXISTS',
        );
}

/// 媒体未找到异常
class MediaNotFoundException extends CollectionException {
  MediaNotFoundException(String mediaId)
      : super(
          'Media not found: $mediaId',
          code: 'MEDIA_NOT_FOUND',
        );
}

/// 无效评分异常
class InvalidRatingException extends CollectionException {
  InvalidRatingException(double rating)
      : super(
          'Invalid rating: $rating. Rating must be between 0 and 10',
          code: 'INVALID_RATING',
        );
}

/// 无效进度异常
class InvalidProgressException extends CollectionException {
  InvalidProgressException(double progress)
      : super(
          'Invalid progress: $progress. Progress must be between 0 and 1',
          code: 'INVALID_PROGRESS',
        );
}

/// 数据库异常
class CollectionDatabaseException extends CollectionException {
  CollectionDatabaseException(String message, {dynamic originalError})
      : super(
          'Database error: $message',
          code: 'DATABASE_ERROR',
          originalError: originalError,
        );
}

/// 网络异常
class CollectionNetworkException extends CollectionException {
  CollectionNetworkException(String message, {dynamic originalError})
      : super(
          'Network error: $message',
          code: 'NETWORK_ERROR',
          originalError: originalError,
        );
}
