// 条件导入
import 'dart:convert';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_mobile.dart';

/// 跨平台文件下载工具
class FileDownload {
  /// 下载文件
  /// [data] - 文件内容（字节）
  /// [filename] - 文件名
  /// [mimeType] - MIME 类型
  static Future<void> download({
    required List<int> data,
    required String filename,
    required String mimeType,
  }) async {
    await downloadFile(data: data, filename: filename, mimeType: mimeType);
  }
  
  /// 下载文本文件
  static Future<void> downloadText({
    required String content,
    required String filename,
    required String mimeType,
  }) async {
    // 使用 UTF-8 编码来正确处理中文等字符
    final bytes = utf8.encode(content);
    await download(data: bytes, filename: filename, mimeType: mimeType);
  }
}
