import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../database/local_database.dart';
import './video_thumbnail_service.dart';

/// 本地 HTTP 服务器，用于接收油猴脚本的数据和提供视频流式传输
/// 
/// 注意：
/// - PC 模式：不启动本地服务器，油猴脚本连接到 Rust 后端（3000端口）
/// - 独立模式：启动本地服务器（8080端口），油猴脚本连接到这里
/// 
/// 新增功能：
/// - 视频流式传输：GET /api/media/:id/video
/// - 缩略图生成：GET /api/media/:id/thumbnail
class LocalHttpServer {
  HttpServer? _server;
  final int port;
  final Future<void> Function(Map<String, dynamic>) onMediaReceived;
  final Future<void> Function(Map<String, dynamic>) onActorReceived;
  final LocalDatabase? database;
  final VideoThumbnailService? thumbnailService;
  bool _isRunning = false;

  LocalHttpServer({
    this.port = 8080,
    required this.onMediaReceived,
    required this.onActorReceived,
    this.database,
    this.thumbnailService,
  });

  bool get isRunning => _isRunning;

  /// 启动服务器（仅在独立模式下）
  Future<void> start() async {
    if (_isRunning) {
      print('⚠ Local HTTP server already running');
      return;
    }
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _isRunning = true;
    print('✓ Local HTTP server started on port $port (Standalone mode)');
  }

  /// 停止服务器
  Future<void> stop() async {
    if (!_isRunning) return;
    
    await _server?.close();
    _server = null;
    _isRunning = false;
    print('✓ Local HTTP server stopped');
  }

  /// CORS 中间件
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders());
        }
        final response = await handler(request);
        return response.change(headers: _corsHeaders());
      };
    };
  }

  Map<String, String> _corsHeaders() => {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  /// 处理请求
  Future<Response> _handleRequest(Request request) async {
    try {
      print('🔍 收到请求: ${request.method} ${request.url.path}');
      
      // POST /api/media - 接收媒体数据
      if (request.method == 'POST' && request.url.path == 'api/media') {
        print('✓ 匹配到 POST /api/media 路由');
        final body = await request.readAsString();
        print('📦 请求体: $body');
        final data = jsonDecode(body) as Map<String, dynamic>;
        print('📦 解析后的数据: $data');
        print('🔄 开始调用 onMediaReceived 回调...');
        await onMediaReceived(data);
        print('✓ onMediaReceived 回调执行完成');
        return Response.ok(
          jsonEncode({'success': true, 'message': '媒体已接收'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // POST /api/actors - 接收演员数据
      if (request.method == 'POST' && request.url.path == 'api/actors') {
        print('✓ 匹配到 POST /api/actors 路由');
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        print('🔄 开始调用 onActorReceived 回调...');
        await onActorReceived(data);
        print('✓ onActorReceived 回调执行完成');
        return Response.ok(
          jsonEncode({'success': true, 'message': '演员已接收'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // GET /api/health - 健康检查
      if (request.method == 'GET' && request.url.path == 'api/health') {
        print('✓ 匹配到 GET /api/health 路由');
        return Response.ok(
          jsonEncode({'status': 'ok', 'version': '1.0.0'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // GET /api/media/:id/video - 视频流式传输
      if (request.method == 'GET' && request.url.pathSegments.length == 4 &&
          request.url.pathSegments[0] == 'api' &&
          request.url.pathSegments[1] == 'media' &&
          request.url.pathSegments[3] == 'video') {
        final mediaId = request.url.pathSegments[2];
        print('✓ 匹配到 GET /api/media/$mediaId/video 路由');
        return await _handleVideoStream(request, mediaId);
      }

      // GET /api/media/:id/thumbnail - 缩略图生成
      if (request.method == 'GET' && request.url.pathSegments.length == 4 &&
          request.url.pathSegments[0] == 'api' &&
          request.url.pathSegments[1] == 'media' &&
          request.url.pathSegments[3] == 'thumbnail') {
        final mediaId = request.url.pathSegments[2];
        print('✓ 匹配到 GET /api/media/$mediaId/thumbnail 路由');
        return await _handleThumbnail(request, mediaId);
      }

      print('✗ 未匹配到任何路由，返回 404');
      return Response.notFound('Not Found');
    } catch (e, stackTrace) {
      print('✗ 请求处理出错: $e');
      print('✗ 堆栈跟踪: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 处理视频流式传输
  Future<Response> _handleVideoStream(Request request, String mediaId) async {
    try {
      if (database == null) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Database not available'}),
        );
      }

      // 从数据库获取媒体信息
      final media = await database!.getMedia(mediaId);
      if (media == null) {
        print('✗ 媒体不存在: $mediaId');
        return Response.notFound(jsonEncode({'error': 'Media not found'}));
      }

      // 获取视频文件路径
      String? videoPath;
      if (media.files.isNotEmpty) {
        videoPath = media.files.first.filePath;
      } else if (media.localFilePath != null) {
        videoPath = media.localFilePath;
      }

      if (videoPath == null || videoPath.isEmpty) {
        print('✗ 媒体没有视频文件: $mediaId');
        return Response.notFound(jsonEncode({'error': 'No video file found'}));
      }

      // 检查文件是否存在
      final file = File(videoPath);
      if (!await file.exists()) {
        print('✗ 视频文件不存在: $videoPath');
        return Response.notFound(jsonEncode({'error': 'Video file not found'}));
      }

      final fileSize = await file.length();
      print('📹 视频文件: $videoPath (${_formatBytes(fileSize)})');

      // 解析 Range 请求头
      final rangeHeader = request.headers['range'];
      if (rangeHeader != null) {
        return await _handleRangeRequest(file, fileSize, rangeHeader);
      } else {
        // 完整文件传输
        return Response.ok(
          file.openRead(),
          headers: {
            'Content-Type': 'video/mp4',
            'Content-Length': fileSize.toString(),
            'Accept-Ranges': 'bytes',
          },
        );
      }
    } catch (e, stackTrace) {
      print('✗ 视频流处理错误: $e');
      print('✗ 堆栈跟踪: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 处理 Range 请求
  Future<Response> _handleRangeRequest(File file, int fileSize, String rangeHeader) async {
    try {
      // 解析 Range 头: "bytes=start-end"
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (match == null) {
        return Response(416, body: 'Invalid Range header');
      }

      final start = int.parse(match.group(1)!);
      final endStr = match.group(2);
      final end = endStr != null && endStr.isNotEmpty ? int.parse(endStr) : fileSize - 1;

      if (start >= fileSize || end >= fileSize || start > end) {
        return Response(416, 
          body: 'Range not satisfiable',
          headers: {'Content-Range': 'bytes */$fileSize'},
        );
      }

      final contentLength = end - start + 1;
      print('📊 Range 请求: bytes=$start-$end/$fileSize (${_formatBytes(contentLength)})');

      // 读取指定范围的数据
      final stream = file.openRead(start, end + 1);

      return Response(206,
        body: stream,
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileSize',
          'Accept-Ranges': 'bytes',
        },
      );
    } catch (e, stackTrace) {
      print('✗ Range 请求处理错误: $e');
      print('✗ 堆栈跟踪: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 处理缩略图生成
  Future<Response> _handleThumbnail(Request request, String mediaId) async {
    try {
      if (database == null || thumbnailService == null) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Service not available'}),
        );
      }

      // 从数据库获取媒体信息
      final media = await database!.getMedia(mediaId);
      if (media == null) {
        print('✗ 媒体不存在: $mediaId');
        return Response.notFound(jsonEncode({'error': 'Media not found'}));
      }

      // 获取视频文件路径
      String? videoPath;
      if (media.files.isNotEmpty) {
        videoPath = media.files.first.filePath;
      } else if (media.localFilePath != null) {
        videoPath = media.localFilePath;
      }

      if (videoPath == null || videoPath.isEmpty) {
        print('✗ 媒体没有视频文件: $mediaId');
        return Response.notFound(jsonEncode({'error': 'No video file found'}));
      }

      // 检查文件是否存在
      final file = File(videoPath);
      if (!await file.exists()) {
        print('✗ 视频文件不存在: $videoPath');
        return Response.notFound(jsonEncode({'error': 'Video file not found'}));
      }

      print('📸 生成缩略图: $videoPath');

      // 生成缩略图
      final thumbnailPath = await thumbnailService!.generateThumbnail(
        videoPath,
        quality: 75,
        maxWidth: 400,
        maxHeight: 600,
        timeMs: 5000, // 5秒处截图
      );

      if (thumbnailPath == null) {
        print('✗ 缩略图生成失败');
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to generate thumbnail'}),
        );
      }

      // 读取缩略图文件
      final thumbnailFile = File(thumbnailPath);
      if (!await thumbnailFile.exists()) {
        print('✗ 缩略图文件不存在: $thumbnailPath');
        return Response.notFound(jsonEncode({'error': 'Thumbnail file not found'}));
      }

      final thumbnailBytes = await thumbnailFile.readAsBytes();
      print('✓ 缩略图生成成功: ${_formatBytes(thumbnailBytes.length)}');

      return Response.ok(
        thumbnailBytes,
        headers: {
          'Content-Type': 'image/jpeg',
          'Content-Length': thumbnailBytes.length.toString(),
          'Cache-Control': 'public, max-age=86400', // 缓存1天
        },
      );
    } catch (e, stackTrace) {
      print('✗ 缩略图生成错误: $e');
      print('✗ 堆栈跟踪: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 格式化字节大小
  String _formatBytes(int bytes) {
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
