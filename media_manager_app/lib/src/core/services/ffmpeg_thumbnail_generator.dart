import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart' show rootBundle;

/// FFmpeg 视频缩略图生成器（Windows 平台专用）
class FFmpegThumbnailGenerator {
  String? _ffmpegPath;

  /// 获取 FFmpeg 可执行文件路径
  /// 
  /// 优先使用打包在应用中的 FFmpeg，如果不存在则尝试系统 PATH
  Future<String?> _getFFmpegPath() async {
    if (_ffmpegPath != null) return _ffmpegPath;

    // 方法 1: 尝试使用打包在应用中的 FFmpeg (Windows 专用)
    try {
      // 获取应用可执行文件所在目录
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      
      // 检查 Windows 打包目录中的 FFmpeg
      final bundledPath = path.join(exeDir, 'ffmpeg.exe');
      if (await File(bundledPath).exists()) {
        _ffmpegPath = bundledPath;
        print('✓ 找到打包的 FFmpeg: $_ffmpegPath');
        return _ffmpegPath;
      }
    } catch (e) {
      print('检查打包 FFmpeg 时出错: $e');
    }

    // 方法 2: 尝试使用系统 PATH 中的 FFmpeg
    try {
      final result = await Process.run('where', ['ffmpeg']);
      if (result.exitCode == 0) {
        final systemPath = (result.stdout as String).split('\n').first.trim();
        if (systemPath.isNotEmpty && await File(systemPath).exists()) {
          _ffmpegPath = systemPath;
          print('✓ 找到系统 FFmpeg: $_ffmpegPath');
          return _ffmpegPath;
        }
      }
    } catch (e) {
      print('检查系统 FFmpeg 时出错: $e');
    }

    print('✗ 未找到 FFmpeg');
    return null;
  }

  /// 检查 FFmpeg 是否可用
  /// 
  /// 返回 true 如果找到可用的 FFmpeg
  Future<bool> isFFmpegAvailable() async {
    final ffmpegPath = await _getFFmpegPath();
    if (ffmpegPath == null) return false;

    try {
      final result = await Process.run(ffmpegPath, ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      print('FFmpeg 不可用: $e');
      return false;
    }
  }

  /// 将用户质量值 (0-100) 映射到 FFmpeg 质量值 (31-2)
  /// 
  /// 用户质量: 0 (最差) 到 100 (最好)
  /// FFmpeg 质量: 31 (最差) 到 2 (最好)
  int _mapQualityToFFmpeg(int userQuality) {
    // 确保质量值在有效范围内
    final clampedQuality = userQuality.clamp(0, 100);
    return 31 - ((clampedQuality * 29) ~/ 100);
  }

  /// 将毫秒转换为 FFmpeg 时间戳格式
  /// 
  /// 返回格式: 秒.毫秒 (例如: "1.500" 表示 1500ms)
  String _formatTimestamp(int milliseconds) {
    final seconds = milliseconds / 1000.0;
    return seconds.toStringAsFixed(3);
  }

  /// 生成视频缩略图
  /// 
  /// [videoPath] 视频文件路径
  /// [outputPath] 输出缩略图文件路径
  /// [maxWidth] 最大宽度
  /// [maxHeight] 最大高度
  /// [timeMs] 截取时间点（毫秒）
  /// [quality] 缩略图质量 (0-100)
  /// 
  /// 返回缩略图文件路径，失败返回 null
  Future<String?> generateThumbnail(
    String videoPath,
    String outputPath, {
    int maxWidth = 300,
    int maxHeight = 300,
    int timeMs = 1000,
    int quality = 75,
  }) async {
    try {
      // 参数验证
      if (maxWidth <= 0 || maxHeight <= 0) {
        print('无效的尺寸参数: width=$maxWidth, height=$maxHeight');
        return null;
      }

      if (timeMs < 0) {
        print('无效的时间戳: $timeMs');
        return null;
      }

      // 检查视频文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        print('视频文件不存在: $videoPath');
        return null;
      }

      // 检查 FFmpeg 是否可用
      final ffmpegPath = await _getFFmpegPath();
      if (ffmpegPath == null) {
        print('FFmpeg 不可用。请确保 FFmpeg 已正确打包或安装。');
        return null;
      }

      // 转换参数
      final timestamp = _formatTimestamp(timeMs);
      final ffmpegQuality = _mapQualityToFFmpeg(quality);

      // 构建 FFmpeg 命令
      final args = [
        '-ss', timestamp,                    // 跳转到指定时间戳
        '-i', videoPath,                     // 输入视频文件
        '-vframes', '1',                     // 只提取一帧
        '-vf', 'scale=$maxWidth:$maxHeight:force_original_aspect_ratio=decrease', // 缩放并保持宽高比
        '-q:v', ffmpegQuality.toString(),   // JPEG 质量
        '-y',                                 // 覆盖输出文件
        outputPath,                          // 输出文件路径
      ];

      print('执行 FFmpeg 命令: $ffmpegPath ${args.join(" ")}');

      // 执行 FFmpeg 命令
      final result = await Process.run(ffmpegPath, args);

      if (result.exitCode != 0) {
        print('FFmpeg 执行失败 (退出码: ${result.exitCode})');
        print('错误输出: ${result.stderr}');
        return null;
      }

      // 验证输出文件是否存在
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        print('缩略图生成成功: $outputPath');
        return outputPath;
      } else {
        print('缩略图文件未生成: $outputPath');
        return null;
      }
    } catch (e) {
      print('生成缩略图时发生错误: $e');
      return null;
    }
  }
}
