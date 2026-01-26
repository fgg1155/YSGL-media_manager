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
  final String? parsedCode;      // JAV 番号（如 IPX-177）
  final String? parsedTitle;     // 标题
  final int? parsedYear;         // 年份
  final String? parsedSeries;    // 系列名（欧美，如 Straplez）
  final String? parsedDate;      // 发布日期（欧美，如 2026-01-23）

  LocalScannedFile({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.parsedCode,
    this.parsedTitle,
    this.parsedYear,
    this.parsedSeries,
    this.parsedDate,
  });

  Map<String, dynamic> toJson() => {
    'file_path': filePath,
    'file_name': fileName,
    'file_size': fileSize,
    if (parsedCode != null) 'parsed_code': parsedCode,
    if (parsedTitle != null) 'parsed_title': parsedTitle,
    if (parsedYear != null) 'parsed_year': parsedYear,
    if (parsedSeries != null) 'parsed_series': parsedSeries,
    if (parsedDate != null) 'parsed_date': parsedDate,
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
  // JAV 番号正则表达式：ABC-123, ABCD-1234, ABC123 等
  static final RegExp _javCodeRegex = RegExp(r'([A-Z]{2,6})-?(\d{3,5})');
  
  // 欧美系列+日期格式：Series.YY.MM.DD 或 Series.YYYY.MM.DD
  static final RegExp _westernSeriesDateRegex = RegExp(
    r'^([A-Z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)*)\.(\d{2})\.(\d{2})\.(\d{2})',
    caseSensitive: false,
  );
  
  // 欧美系列+标题格式：Series-Title 或 Series.Title
  static final RegExp _westernSeriesTitleRegex = RegExp(
    r'^([A-Z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)*)[-\.](.+)',
    caseSensitive: false,
  );
  
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
        parsedSeries: parsed['series'],
        parsedDate: parsed['date'],
      );
    } catch (e) {
      print('解析文件失败: $e');
      return null;
    }
  }

  /// 解析文件名，提取识别号、标题、年份、系列、日期
  Map<String, dynamic> _parseFilename(String filename) {
    // 移除文件扩展名
    final nameWithoutExt = path.basenameWithoutExtension(filename);

    // 1. 尝试识别欧美格式：系列.YY.MM.DD
    final westernDateMatch = _westernSeriesDateRegex.firstMatch(nameWithoutExt);
    if (westernDateMatch != null) {
      final series = westernDateMatch.group(1)!;
      final year = westernDateMatch.group(2)!;
      final month = westernDateMatch.group(3)!;
      final day = westernDateMatch.group(4)!;
      
      // 构建完整日期：YYYY-MM-DD
      final fullYear = int.parse('20$year');
      final releaseDate = '20$year-$month-$day';
      
      return {
        'code': null,           // 欧美不使用 code
        'title': null,          // 不提取标题（不准确）
        'year': fullYear,
        'series': series,       // 系列名
        'date': releaseDate,    // 发布日期
      };
    }

    // 2. 尝试识别欧美格式：系列-标题 或 系列.标题
    final westernTitleMatch = _westernSeriesTitleRegex.firstMatch(nameWithoutExt);
    if (westernTitleMatch != null) {
      final series = westernTitleMatch.group(1)!;
      String title = westernTitleMatch.group(2)!;
      
      // 检查标题是否以大写字母开头（排除 JAV 番号误匹配）
      if (title.isNotEmpty && title[0].toUpperCase() == title[0]) {
        // 清理标题
        title = title
            .replaceAll('_', ' ')
            .replaceAll('.', ' ')
            .trim();
        
        // 移除常见标记
        title = _removeCommonMarkers(title);
        
        // 提取年份（如果有）
        int? parsedYear;
        final yearMatch = _yearRegex.firstMatch(title);
        if (yearMatch != null) {
          parsedYear = int.tryParse(yearMatch.group(1)!);
          title = title.replaceAll(yearMatch.group(0)!, '').trim();
        }
        
        return {
          'code': null,           // 欧美不使用 code
          'title': title.isEmpty ? null : title,
          'year': parsedYear,
          'series': series,       // 系列名
          'date': null,
        };
      }
    }

    // 3. 尝试识别 JAV 番号：ABC-123
    String? parsedCode;
    final javCodeMatch = _javCodeRegex.firstMatch(nameWithoutExt);
    if (javCodeMatch != null) {
      parsedCode = '${javCodeMatch.group(1)}-${javCodeMatch.group(2)}';
    }

    // 4. 提取年份
    int? parsedYear;
    final yearMatch = _yearRegex.firstMatch(nameWithoutExt);
    if (yearMatch != null) {
      parsedYear = int.tryParse(yearMatch.group(1)!);
    }

    // 5. 提取标题（移除识别号、年份、特殊标记后的内容）
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
    title = _removeCommonMarkers(title);

    // 清理标题
    title = title
        .replaceAll('_', ' ')
        .replaceAll('.', ' ')
        .replaceAll('-', ' ')
        .trim();

    final parsedTitle = title.isEmpty ? null : title;

    return {
      'code': parsedCode,     // JAV 番号
      'title': parsedTitle,
      'year': parsedYear,
      'series': null,         // JAV 不使用 series
      'date': null,
    };
  }

  /// 移除常见的视频质量标记
  String _removeCommonMarkers(String text) {
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

    String result = text;
    for (final marker in markers) {
      result = result.replaceAll(marker, '');
    }
    
    return result.trim();
  }
}
