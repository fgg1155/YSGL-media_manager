import 'dart:io';
import 'package:path/path.dart' as path;

/// 支持的视频文件扩展名
const List<String> videoExtensions = [
  'mp4', 'mkv', 'avi', 'wmv', 'flv', 'mov', 'm4v', 
  'mpg', 'mpeg', 'webm', 'ts', 'm2ts'
];

/// 扫描的视频文件信息
class LocalScannedFile {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String? parsedCode;
  final String? parsedTitle;
  final int? parsedYear;

  LocalScannedFile({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.parsedCode,
    this.parsedTitle,
    this.parsedYear,
  });

  Map<String, dynamic> toJson() => {
    'file_path': filePath,
    'file_name': fileName,
    'file_size': fileSize,
    if (parsedCode != null) 'parsed_code': parsedCode,
    if (parsedTitle != null) 'parsed_title': parsedTitle,
    if (parsedYear != null) 'parsed_year': parsedYear,
  };
}

/// 扫描结果
class LocalScanResult {
  final int totalFiles;
  final List<LocalScannedFile> scannedFiles;

  LocalScanResult({
    required this.totalFiles,
    required this.scannedFiles,
  });
}

/// 本地文件扫描器（独立模式）
class LocalFileScanner {
  // 识别号正则表达式：ABC-123, ABCD-1234, ABC123 等
  static final RegExp _codeRegex = RegExp(r'([A-Z]{2,6})-?(\d{3,5})');
  
  // 年份正则表达式：2020, 2021 等
  static final RegExp _yearRegex = RegExp(r'\b(19\d{2}|20\d{2})\b');

  /// 扫描指定目录
  Future<LocalScanResult> scanDirectory(String directoryPath, bool recursive) async {
    final dir = Directory(directoryPath);
    
    if (!await dir.exists()) {
      throw Exception('路径不存在: $directoryPath');
    }

    final scannedFiles = <LocalScannedFile>[];
    await _scanDirRecursive(dir, recursive, scannedFiles);

    return LocalScanResult(
      totalFiles: scannedFiles.length,
      scannedFiles: scannedFiles,
    );
  }

  /// 递归扫描目录
  Future<void> _scanDirRecursive(
    Directory dir,
    bool recursive,
    List<LocalScannedFile> files,
  ) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          if (_isVideoFile(entity.path)) {
            final scannedFile = await _parseFile(entity);
            if (scannedFile != null) {
              files.add(scannedFile);
            }
          }
        } else if (entity is Directory && recursive) {
          await _scanDirRecursive(entity, recursive, files);
        }
      }
    } catch (e) {
      print('扫描目录失败: $e');
    }
  }

  /// 判断是否为视频文件
  bool _isVideoFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    if (ext.isEmpty) return false;
    
    // 移除开头的点
    final extWithoutDot = ext.substring(1);
    return videoExtensions.contains(extWithoutDot);
  }

  /// 解析文件信息
  Future<LocalScannedFile?> _parseFile(File file) async {
    try {
      final fileName = path.basename(file.path);
      final filePath = file.path;
      final stat = await file.stat();
      final fileSize = stat.size;

      // 解析文件名
      final parsed = _parseFilename(fileName);

      return LocalScannedFile(
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        parsedCode: parsed['code'],
        parsedTitle: parsed['title'],
        parsedYear: parsed['year'],
      );
    } catch (e) {
      print('解析文件失败: $e');
      return null;
    }
  }

  /// 解析文件名，提取识别号、标题、年份
  Map<String, dynamic> _parseFilename(String filename) {
    // 移除文件扩展名
    final nameWithoutExt = path.basenameWithoutExtension(filename);

    // 提取识别号
    String? parsedCode;
    final codeMatch = _codeRegex.firstMatch(nameWithoutExt);
    if (codeMatch != null) {
      parsedCode = '${codeMatch.group(1)}-${codeMatch.group(2)}';
    }

    // 提取年份
    int? parsedYear;
    final yearMatch = _yearRegex.firstMatch(nameWithoutExt);
    if (yearMatch != null) {
      parsedYear = int.tryParse(yearMatch.group(1)!);
    }

    // 提取标题（移除识别号、年份、特殊标记后的内容）
    String title = nameWithoutExt;

    // 移除识别号
    if (parsedCode != null) {
      title = title.replaceAll(parsedCode, '');
      title = title.replaceAll(parsedCode.replaceAll('-', ''), '');
    }

    // 移除年份
    if (parsedYear != null) {
      title = title.replaceAll(parsedYear.toString(), '');
    }

    // 移除常见标记
    final markers = [
      RegExp(r'\[.*?\]'),  // [1080p], [中文字幕] 等
      RegExp(r'\(.*?\)'),  // (2023) 等
      RegExp(r'1080p', caseSensitive: false),
      RegExp(r'720p', caseSensitive: false),
      RegExp(r'480p', caseSensitive: false),
      RegExp(r'4K', caseSensitive: false),
      RegExp(r'2160p', caseSensitive: false),
      RegExp(r'BluRay', caseSensitive: false),
      RegExp(r'WEB-DL', caseSensitive: false),
      RegExp(r'WEBRip', caseSensitive: false),
      RegExp(r'HDRip', caseSensitive: false),
      RegExp(r'x264', caseSensitive: false),
      RegExp(r'x265', caseSensitive: false),
      RegExp(r'H264', caseSensitive: false),
      RegExp(r'H265', caseSensitive: false),
      RegExp(r'HEVC', caseSensitive: false),
      RegExp(r'AAC', caseSensitive: false),
      RegExp(r'AC3', caseSensitive: false),
      RegExp(r'DTS', caseSensitive: false),
    ];

    for (final marker in markers) {
      title = title.replaceAll(marker, '');
    }

    // 清理标题
    title = title
        .replaceAll('_', ' ')
        .replaceAll('.', ' ')
        .replaceAll('-', ' ')
        .trim();

    final parsedTitle = title.isEmpty ? null : title;

    return {
      'code': parsedCode,
      'title': parsedTitle,
      'year': parsedYear,
    };
  }
}
