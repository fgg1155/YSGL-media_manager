import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'ffmpeg_thumbnail_generator.dart';

/// 视频缩略图生成服务
class VideoThumbnailService {
  /// FFmpeg 缩略图生成器（Windows 平台）
  final FFmpegThumbnailGenerator _ffmpegGenerator = FFmpegThumbnailGenerator();
  /// 缓存目录
  Directory? _cacheDir;

  /// 初始化缓存目录
  Future<void> _initCacheDir() async {
    if (_cacheDir != null) return;
    
    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory(path.join(tempDir.path, 'video_thumbnails'));
      
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
        print('缓存目录已创建: ${_cacheDir!.path}');
      }
    } catch (e, stackTrace) {
      _logError('缓存目录初始化', e, stackTrace: stackTrace);
      rethrow; // 重新抛出异常，因为没有缓存目录无法继续
    }
  }

  /// 生成视频缩略图
  /// 
  /// [videoPath] 视频文件路径
  /// [quality] 缩略图质量 (0-100)
  /// [maxWidth] 最大宽度
  /// [maxHeight] 最大高度
  /// [timeMs] 截取时间点（毫秒）
  /// 
  /// 返回缩略图文件路径，失败返回 null
  Future<String?> generateThumbnail(
    String videoPath, {
    int quality = 75,
    int maxWidth = 300,
    int maxHeight = 300,
    int timeMs = 1000,
  }) async {
    try {
      // 参数验证
      if (!_validateParameters(quality, maxWidth, maxHeight, timeMs)) {
        return null;
      }

      await _initCacheDir();

      // 检查视频文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        _logError('文件验证', '视频文件不存在: $videoPath');
        return null;
      }

      // 生成缩略图文件名（使用视频路径的哈希值）
      final fileName = '${videoPath.hashCode.abs()}_${timeMs}.jpg';
      final thumbnailPath = path.join(_cacheDir!.path, fileName);

      // 如果缩略图已存在，直接返回
      final thumbnailFile = File(thumbnailPath);
      if (await thumbnailFile.exists()) {
        print('使用缓存的缩略图: $thumbnailPath');
        return thumbnailPath;
      }

      // 根据平台选择生成方式
      if (Platform.isWindows) {
        return await _generateThumbnailWindows(
          videoPath,
          thumbnailPath,
          quality: quality,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          timeMs: timeMs,
        );
      } else {
        return await _generateThumbnailMobile(
          videoPath,
          thumbnailPath,
          quality: quality,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          timeMs: timeMs,
        );
      }
    } catch (e, stackTrace) {
      _logError('生成缩略图', e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 验证参数
  bool _validateParameters(int quality, int maxWidth, int maxHeight, int timeMs) {
    if (quality < 0 || quality > 100) {
      _logError('参数验证', '质量参数超出范围 (0-100): $quality');
      return false;
    }

    if (maxWidth <= 0) {
      _logError('参数验证', '宽度必须大于 0: $maxWidth');
      return false;
    }

    if (maxHeight <= 0) {
      _logError('参数验证', '高度必须大于 0: $maxHeight');
      return false;
    }

    if (timeMs < 0) {
      _logError('参数验证', '时间戳不能为负数: $timeMs');
      return false;
    }

    return true;
  }

  /// 记录错误日志
  void _logError(String context, dynamic error, {StackTrace? stackTrace}) {
    print('[$context] 错误: $error');
    if (stackTrace != null) {
      print('堆栈跟踪: $stackTrace');
    }
  }

  /// Windows 平台缩略图生成（使用 FFmpeg）
  Future<String?> _generateThumbnailWindows(
    String videoPath,
    String thumbnailPath, {
    required int quality,
    required int maxWidth,
    required int maxHeight,
    required int timeMs,
  }) async {
    try {
      print('使用 FFmpeg 生成缩略图 (Windows)');
      
      // 检查 FFmpeg 是否可用
      if (!await _ffmpegGenerator.isFFmpegAvailable()) {
        _logError('FFmpeg 检查', 'FFmpeg 不可用。请安装 FFmpeg 并将其添加到系统 PATH。\n访问: https://ffmpeg.org/download.html');
        return null;
      }

      return await _ffmpegGenerator.generateThumbnail(
        videoPath,
        thumbnailPath,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        timeMs: timeMs,
      );
    } catch (e, stackTrace) {
      _logError('Windows 缩略图生成', e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 移动平台缩略图生成（使用 video_thumbnail 插件）
  Future<String?> _generateThumbnailMobile(
    String videoPath,
    String thumbnailPath, {
    required int quality,
    required int maxWidth,
    required int maxHeight,
    required int timeMs,
  }) async {
    try {
      print('使用 video_thumbnail 插件生成缩略图 (Mobile)');
      
      // 生成缩略图
      final thumbnail = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: _cacheDir!.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        timeMs: timeMs,
        quality: quality,
      );

      if (thumbnail != null && await File(thumbnail).exists()) {
        // 重命名为我们的文件名
        await File(thumbnail).rename(thumbnailPath);
        return thumbnailPath;
      }

      _logError('移动平台缩略图生成', '插件返回 null 或文件不存在');
      return null;
    } catch (e, stackTrace) {
      _logError('移动平台缩略图生成', e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 批量生成缩略图
  /// 
  /// [videoPaths] 视频文件路径列表
  /// 返回 Map<视频路径, 缩略图路径>
  Future<Map<String, String?>> generateThumbnails(
    List<String> videoPaths, {
    int quality = 75,
    int maxWidth = 300,
    int maxHeight = 300,
    int timeMs = 1000,
  }) async {
    final results = <String, String?>{};

    for (final videoPath in videoPaths) {
      final thumbnail = await generateThumbnail(
        videoPath,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        timeMs: timeMs,
      );
      results[videoPath] = thumbnail;
    }

    return results;
  }

  /// 清除所有缓存的缩略图
  Future<void> clearCache() async {
    try {
      await _initCacheDir();
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
        print('缩略图缓存已清除');
      }
    } catch (e, stackTrace) {
      _logError('清除缩略图缓存', e, stackTrace: stackTrace);
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    try {
      await _initCacheDir();
      if (_cacheDir == null || !await _cacheDir!.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in _cacheDir!.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      print('缓存大小: ${formatCacheSize(totalSize)}');
      return totalSize;
    } catch (e, stackTrace) {
      _logError('获取缓存大小', e, stackTrace: stackTrace);
      return 0;
    }
  }

  /// 格式化文件大小
  String formatCacheSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
