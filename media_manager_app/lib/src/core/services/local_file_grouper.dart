import 'local_file_scanner.dart';

/// 分段模式类型
enum PartPatternType {
  cd,         // CD1, CD2, CD3
  part,       // Part1, Part2, Part3
  disc,       // Disc1, Disc2, Disc3
  number,     // 01, 02, 03
  underscore, // _1, _2, _3
  hyphen,     // -1, -2, -3
}

/// 分段信息
class PartInfo {
  final int partNumber;
  final String partLabel;
  final PartPatternType patternType;

  PartInfo({
    required this.partNumber,
    required this.partLabel,
    required this.patternType,
  });

  Map<String, dynamic> toJson() => {
    'part_number': partNumber,
    'part_label': partLabel,
    'pattern_type': patternType.toString().split('.').last,
  };
}

/// 带分段信息的扫描文件
class LocalScannedFileWithPart {
  final LocalScannedFile scannedFile;
  final PartInfo? partInfo;

  LocalScannedFileWithPart({
    required this.scannedFile,
    this.partInfo,
  });

  Map<String, dynamic> toJson() => {
    'scanned_file': scannedFile.toJson(),
    'part_info': partInfo?.toJson(),
  };
}

/// 文件组
class LocalFileGroup {
  final String baseName;
  final List<LocalScannedFileWithPart> files;
  final int totalSize;

  LocalFileGroup({
    required this.baseName,
    required this.files,
    required this.totalSize,
  });

  Map<String, dynamic> toJson() => {
    'base_name': baseName,
    'files': files.map((f) => f.toJson()).toList(),
    'total_size': totalSize,
  };
}

/// 本地文件分组器（独立模式）
class LocalFileGrouper {
  // 各种分段模式的正则表达式
  static final RegExp _cdRegex = RegExp(r'[-_\s]?cd[-_\s]?(\d+)', caseSensitive: false);
  static final RegExp _partRegex = RegExp(r'[-_\s]?part[-_\s]?(\d+)', caseSensitive: false);
  static final RegExp _discRegex = RegExp(r'[-_\s]?disc[-_\s]?(\d+)', caseSensitive: false);
  static final RegExp _numberRegex = RegExp(r'[-_\s](\d{2,3})$');
  static final RegExp _underscoreRegex = RegExp(r'_(\d+)$');
  static final RegExp _hyphenRegex = RegExp(r'-(\d+)$');

  /// 将扫描的文件按基础名称分组
  List<LocalFileGroup> groupFiles(List<LocalScannedFile> files) {
    // 第一步：为每个文件解析分段信息
    final filesWithParts = files.map((file) {
      final partInfo = _parsePartInfo(file.fileName);
      return LocalScannedFileWithPart(
        scannedFile: file,
        partInfo: partInfo,
      );
    }).toList();

    // 第二步：按基础名称分组
    final groups = <String, List<LocalScannedFileWithPart>>{};
    for (final fileWithPart in filesWithParts) {
      final baseName = _extractBaseName(fileWithPart.scannedFile.fileName);
      groups.putIfAbsent(baseName, () => []).add(fileWithPart);
    }

    // 第三步：转换为 LocalFileGroup 并计算总大小
    return groups.entries.map((entry) {
      final totalSize = entry.value.fold<int>(
        0,
        (sum, f) => sum + f.scannedFile.fileSize,
      );
      return LocalFileGroup(
        baseName: entry.key,
        files: entry.value,
        totalSize: totalSize,
      );
    }).toList();
  }

  /// 识别文件的分段信息
  PartInfo? _parsePartInfo(String filename) {
    // 移除文件扩展名
    final nameWithoutExt = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;

    // 按优先级尝试各种模式
    // 1. CD 模式
    final cdMatch = _cdRegex.firstMatch(nameWithoutExt);
    if (cdMatch != null) {
      final num = int.tryParse(cdMatch.group(1)!);
      if (num != null) {
        return PartInfo(
          partNumber: num,
          partLabel: 'CD$num',
          patternType: PartPatternType.cd,
        );
      }
    }

    // 2. Part 模式
    final partMatch = _partRegex.firstMatch(nameWithoutExt);
    if (partMatch != null) {
      final num = int.tryParse(partMatch.group(1)!);
      if (num != null) {
        return PartInfo(
          partNumber: num,
          partLabel: 'Part $num',
          patternType: PartPatternType.part,
        );
      }
    }

    // 3. Disc 模式
    final discMatch = _discRegex.firstMatch(nameWithoutExt);
    if (discMatch != null) {
      final num = int.tryParse(discMatch.group(1)!);
      if (num != null) {
        return PartInfo(
          partNumber: num,
          partLabel: 'Disc $num',
          patternType: PartPatternType.disc,
        );
      }
    }

    // 4. 下划线模式（优先于纯数字）
    final underscoreMatch = _underscoreRegex.firstMatch(nameWithoutExt);
    if (underscoreMatch != null) {
      final num = int.tryParse(underscoreMatch.group(1)!);
      if (num != null) {
        return PartInfo(
          partNumber: num,
          partLabel: 'Part $num',
          patternType: PartPatternType.underscore,
        );
      }
    }

    // 5. 连字符模式（但要排除识别号格式）
    final hyphenMatch = _hyphenRegex.firstMatch(nameWithoutExt);
    if (hyphenMatch != null) {
      final matchStart = hyphenMatch.start;
      final beforeHyphen = nameWithoutExt.substring(0, matchStart);
      
      // 检查是否是识别号格式（如 ABC-123）
      final isCode = beforeHyphen.length <= 6 && 
                     beforeHyphen.split('').every((c) => c.toUpperCase() == c && RegExp(r'[A-Z]').hasMatch(c));
      
      if (!isCode) {
        final num = int.tryParse(hyphenMatch.group(1)!);
        if (num != null) {
          return PartInfo(
            partNumber: num,
            partLabel: 'Part $num',
            patternType: PartPatternType.hyphen,
          );
        }
      }
    }

    // 6. 纯数字模式（最低优先级）
    final numberMatch = _numberRegex.firstMatch(nameWithoutExt);
    if (numberMatch != null) {
      final num = int.tryParse(numberMatch.group(1)!);
      if (num != null && num <= 20) {
        return PartInfo(
          partNumber: num,
          partLabel: num.toString().padLeft(2, '0'),
          patternType: PartPatternType.number,
        );
      }
    }

    return null;
  }

  /// 提取基础文件名（去除分段标记和扩展名）
  String _extractBaseName(String filename) {
    // 移除文件扩展名
    final nameWithoutExt = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;

    String baseName = nameWithoutExt;

    // 按优先级移除模式
    final cdMatch = _cdRegex.firstMatch(baseName);
    if (cdMatch != null) {
      baseName = baseName.substring(0, cdMatch.start);
    } else {
      final partMatch = _partRegex.firstMatch(baseName);
      if (partMatch != null) {
        baseName = baseName.substring(0, partMatch.start);
      } else {
        final discMatch = _discRegex.firstMatch(baseName);
        if (discMatch != null) {
          baseName = baseName.substring(0, discMatch.start);
        } else {
          final underscoreMatch = _underscoreRegex.firstMatch(baseName);
          if (underscoreMatch != null) {
            baseName = baseName.substring(0, underscoreMatch.start);
          } else {
            final hyphenMatch = _hyphenRegex.firstMatch(baseName);
            if (hyphenMatch != null) {
              final matchStart = hyphenMatch.start;
              final beforeHyphen = baseName.substring(0, matchStart);
              
              // 检查是否是识别号格式
              final isCode = beforeHyphen.length <= 6 && 
                             beforeHyphen.split('').every((c) => c.toUpperCase() == c && RegExp(r'[A-Z]').hasMatch(c));
              
              if (!isCode) {
                baseName = baseName.substring(0, matchStart);
              }
            } else {
              final numberMatch = _numberRegex.firstMatch(baseName);
              if (numberMatch != null) {
                final num = int.tryParse(baseName.substring(numberMatch.start + 1, numberMatch.end));
                if (num != null && num <= 20) {
                  baseName = baseName.substring(0, numberMatch.start);
                }
              }
            }
          }
        }
      }
    }

    // 清理末尾的空格、下划线、连字符
    return baseName.replaceAll(RegExp(r'[\s_-]+$'), '');
  }
}
