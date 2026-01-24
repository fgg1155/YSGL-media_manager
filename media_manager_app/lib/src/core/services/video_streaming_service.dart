import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Service for video streaming and thumbnail generation
/// 
/// Provides URLs for streaming videos and fetching thumbnails from the backend.
/// Supports both desktop (local) and mobile (remote) modes.
class VideoStreamingService {
  final String baseUrl;
  final Dio? _dio;

  VideoStreamingService({
    required this.baseUrl,
    Dio? dio,
  }) : _dio = dio;

  /// Get thumbnail URL for a media item
  /// 
  /// Returns the URL to fetch a JPEG thumbnail for the given media ID.
  /// The thumbnail is generated on-demand by the backend using FFmpeg.
  /// 
  /// [fileIndex] - Optional file index for multi-file videos (defaults to 0)
  /// 
  /// Example: http://localhost:3000/api/media/abc123/thumbnail?index=0
  String getThumbnailUrl(String mediaId, {int fileIndex = 0}) {
    final url = '$baseUrl/api/media/$mediaId/thumbnail?index=$fileIndex';
    if (kDebugMode) {
      debugPrint('📸 Thumbnail URL: $url (file index: $fileIndex)');
    }
    return url;
  }

  /// Get video streaming URL for a media item
  /// 
  /// Returns the URL to stream video content for the given media ID.
  /// The backend supports HTTP Range requests for seeking/scrubbing.
  /// 
  /// Example: http://localhost:3000/api/media/abc123/video
  String getVideoStreamUrl(String mediaId) {
    final url = '$baseUrl/api/media/$mediaId/video';
    if (kDebugMode) {
      debugPrint('🎬 Video stream URL: $url');
    }
    return url;
  }

  /// Check if streaming is available
  /// 
  /// Tests if the backend is reachable by checking the health endpoint.
  /// Returns true if the backend responds successfully.
  Future<bool> isStreamingAvailable() async {
    if (_dio == null) {
      // If no Dio instance provided, assume available
      return true;
    }

    try {
      final response = await _dio!.get(
        '$baseUrl/api/health',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      
      final isAvailable = response.statusCode == 200;
      
      if (kDebugMode) {
        debugPrint('🔍 Streaming availability: $isAvailable');
      }
      
      return isAvailable;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Streaming not available: $e');
      }
      return false;
    }
  }
}
