import 'package:json_annotation/json_annotation.dart';

part 'media_file.g.dart';

/// 媒体文件模型 - 用于存储多分段视频文件
@JsonSerializable(fieldRename: FieldRename.snake)
class MediaFile {
  final String id;
  final String mediaId;
  final String filePath;
  final int fileSize;
  final int? partNumber;
  final String? partLabel;
  final DateTime createdAt;

  const MediaFile({
    required this.id,
    required this.mediaId,
    required this.filePath,
    required this.fileSize,
    this.partNumber,
    this.partLabel,
    required this.createdAt,
  });

  factory MediaFile.fromJson(Map<String, dynamic> json) {
    try {
      return _$MediaFileFromJson(json);
    } catch (e) {
      // 如果自动生成的方法失败，使用安全的手动解析
      return MediaFile(
        id: json['id']?.toString() ?? '',
        mediaId: json['media_id']?.toString() ?? '',
        filePath: json['file_path']?.toString() ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
        partNumber: (json['part_number'] as num?)?.toInt(),
        partLabel: json['part_label']?.toString(),
        createdAt: json['created_at'] != null 
            ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
    }
  }

  Map<String, dynamic> toJson() => _$MediaFileToJson(this);

  /// 获取显示名称
  String get displayName {
    if (partLabel != null && partLabel!.isNotEmpty) {
      return partLabel!;
    } else if (partNumber != null) {
      return 'Part $partNumber';
    } else {
      // 从文件路径提取文件名
      return filePath.split('/').last.split('\\').last;
    }
  }

  /// 格式化文件大小
  String get formattedSize {
    return MediaFile.formatFileSize(fileSize);
  }

  /// 格式化文件大小为人类可读格式
  static String formatFileSize(int size) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    const tb = gb * 1024;

    if (size >= tb) {
      return '${(size / tb).toStringAsFixed(2)} TB';
    } else if (size >= gb) {
      return '${(size / gb).toStringAsFixed(2)} GB';
    } else if (size >= mb) {
      return '${(size / mb).toStringAsFixed(2)} MB';
    } else if (size >= kb) {
      return '${(size / kb).toStringAsFixed(2)} KB';
    } else {
      return '$size B';
    }
  }
}
