import '../models/media_item.dart';
import 'local_file_scanner.dart';
import 'local_file_grouper.dart';

/// 匹配结果类型
enum LocalMatchType {
  exact,  // 精确匹配
  fuzzy,  // 模糊匹配
  none,   // 未匹配
}

/// 单个文件的匹配结果
class LocalMatchResult {
  final LocalScannedFile scannedFile;
  final LocalMatchType matchType;
  final MediaItem? matchedMedia;
  final double confidence;
  final List<MediaItem> suggestions;

  LocalMatchResult({
    required this.scannedFile,
    required this.matchType,
    this.matchedMedia,
    required this.confidence,
    required this.suggestions,
  });

  Map<String, dynamic> toJson() => {
    'scanned_file': scannedFile.toJson(),
    'match_type': matchType.toString().split('.').last,
    'matched_media': matchedMedia?.toJson(),
    'confidence': confidence,
    'suggestions': suggestions.map((m) => m.toJson()).toList(),
  };
}

/// 文件组的匹配结果
class LocalGroupMatchResult {
  final LocalFileGroup fileGroup;
  final LocalMatchType matchType;
  final MediaItem? matchedMedia;
  final double confidence;
  final List<MediaItem> suggestions;

  LocalGroupMatchResult({
    required this.fileGroup,
    required this.matchType,
    this.matchedMedia,
    required this.confidence,
    required this.suggestions,
  });

  Map<String, dynamic> toJson() => {
    'file_group': fileGroup.toJson(),
    'match_type': matchType.toString().split('.').last,
    'matched_media': matchedMedia?.toJson(),
    'confidence': confidence,
    'suggestions': suggestions.map((m) => m.toJson()).toList(),
  };
}

/// 本地文件匹配器（独立模式）
class LocalFileMatcher {
  /// 匹配扫描的文件到数据库中的媒体
  List<LocalMatchResult> matchFiles(
    List<LocalScannedFile> scannedFiles,
    List<MediaItem> allMedia,
  ) {
    return scannedFiles.map((file) => _matchSingleFile(file, allMedia)).toList();
  }

  /// 匹配文件组到数据库中的媒体
  List<LocalGroupMatchResult> matchFileGroups(
    List<LocalFileGroup> fileGroups,
    List<MediaItem> allMedia,
  ) {
    return fileGroups.map((group) => _matchSingleGroup(group, allMedia)).toList();
  }

  /// 匹配单个文件组
  LocalGroupMatchResult _matchSingleGroup(
    LocalFileGroup group,
    List<MediaItem> allMedia,
  ) {
    // 使用第一个文件的信息进行匹配
    if (group.files.isNotEmpty) {
      final file = group.files.first.scannedFile;

      // 1. 尝试通过识别号精确匹配
      if (file.parsedCode != null) {
        final media = _findByCode(file.parsedCode!, allMedia);
        if (media != null) {
          return LocalGroupMatchResult(
            fileGroup: group,
            matchType: LocalMatchType.exact,
            matchedMedia: media,
            confidence: 1.0,
            suggestions: [],
          );
        }
      }

      // 2. 尝试通过基础名称模糊匹配
      final fuzzyMatches = _findByTitleFuzzy(group.baseName, allMedia, 0.6);

      if (fuzzyMatches.isNotEmpty) {
        final bestMatch = fuzzyMatches.first;
        final confidence = bestMatch['confidence'] as double;

        if (confidence > 0.8) {
          // 高置信度，认为是匹配
          return LocalGroupMatchResult(
            fileGroup: group,
            matchType: LocalMatchType.fuzzy,
            matchedMedia: bestMatch['media'] as MediaItem,
            confidence: confidence,
            suggestions: fuzzyMatches
                .skip(1)
                .take(3)
                .map((m) => m['media'] as MediaItem)
                .toList(),
          );
        } else {
          // 中等置信度，提供建议
          return LocalGroupMatchResult(
            fileGroup: group,
            matchType: LocalMatchType.none,
            matchedMedia: null,
            confidence: 0.0,
            suggestions: fuzzyMatches
                .take(5)
                .map((m) => m['media'] as MediaItem)
                .toList(),
          );
        }
      }
    }

    // 3. 未匹配
    return LocalGroupMatchResult(
      fileGroup: group,
      matchType: LocalMatchType.none,
      matchedMedia: null,
      confidence: 0.0,
      suggestions: [],
    );
  }

  /// 匹配单个文件
  LocalMatchResult _matchSingleFile(
    LocalScannedFile file,
    List<MediaItem> allMedia,
  ) {
    // 1. 尝试通过识别号精确匹配
    if (file.parsedCode != null) {
      final media = _findByCode(file.parsedCode!, allMedia);
      if (media != null) {
        return LocalMatchResult(
          scannedFile: file,
          matchType: LocalMatchType.exact,
          matchedMedia: media,
          confidence: 1.0,
          suggestions: [],
        );
      }
    }

    // 2. 尝试通过标题模糊匹配
    if (file.parsedTitle != null) {
      final fuzzyMatches = _findByTitleFuzzy(file.parsedTitle!, allMedia, 0.6);

      if (fuzzyMatches.isNotEmpty) {
        final bestMatch = fuzzyMatches.first;
        final confidence = bestMatch['confidence'] as double;

        if (confidence > 0.8) {
          // 高置信度，认为是匹配
          return LocalMatchResult(
            scannedFile: file,
            matchType: LocalMatchType.fuzzy,
            matchedMedia: bestMatch['media'] as MediaItem,
            confidence: confidence,
            suggestions: fuzzyMatches
                .skip(1)
                .take(3)
                .map((m) => m['media'] as MediaItem)
                .toList(),
          );
        } else {
          // 中等置信度，提供建议
          return LocalMatchResult(
            scannedFile: file,
            matchType: LocalMatchType.none,
            matchedMedia: null,
            confidence: 0.0,
            suggestions: fuzzyMatches
                .take(5)
                .map((m) => m['media'] as MediaItem)
                .toList(),
          );
        }
      }
    }

    // 3. 未匹配
    return LocalMatchResult(
      scannedFile: file,
      matchType: LocalMatchType.none,
      matchedMedia: null,
      confidence: 0.0,
      suggestions: [],
    );
  }

  /// 通过识别号查找媒体（标准化比较）
  MediaItem? _findByCode(String code, List<MediaItem> allMedia) {
    final normalizedCode = _normalizeCode(code);

    for (final media in allMedia) {
      if (media.code != null) {
        final normalizedMediaCode = _normalizeCode(media.code!);
        if (normalizedCode == normalizedMediaCode) {
          return media;
        }
      }
    }

    return null;
  }

  /// 标准化识别号格式（移除连字符、下划线、空格，转为大写）
  String _normalizeCode(String code) {
    return code
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '')
        .toUpperCase();
  }

  /// 通过标题模糊匹配
  List<Map<String, dynamic>> _findByTitleFuzzy(
    String title,
    List<MediaItem> allMedia,
    double threshold,
  ) {
    final matches = <Map<String, dynamic>>[];

    for (final media in allMedia) {
      final similarity = _calculateSimilarity(title, media.title);
      if (similarity >= threshold) {
        matches.add({
          'media': media,
          'confidence': similarity,
        });
      }
    }

    // 按相似度降序排序
    matches.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));

    return matches;
  }

  /// 计算字符串相似度（简单的 Jaccard 相似度）
  double _calculateSimilarity(String s1, String s2) {
    final s1Lower = s1.toLowerCase();
    final s2Lower = s2.toLowerCase();

    // 分词（按空格）
    final words1 = s1Lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    final words2 = s2Lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

    if (words1.isEmpty && words2.isEmpty) {
      return 1.0;
    }

    if (words1.isEmpty || words2.isEmpty) {
      return 0.0;
    }

    // Jaccard 相似度
    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;

    return intersection / union;
  }
}
