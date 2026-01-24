// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaFile _$MediaFileFromJson(Map<String, dynamic> json) => MediaFile(
      id: json['id'] as String,
      mediaId: json['media_id'] as String,
      filePath: json['file_path'] as String,
      fileSize: (json['file_size'] as num).toInt(),
      partNumber: (json['part_number'] as num?)?.toInt(),
      partLabel: json['part_label'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$MediaFileToJson(MediaFile instance) => <String, dynamic>{
      'id': instance.id,
      'media_id': instance.mediaId,
      'file_path': instance.filePath,
      'file_size': instance.fileSize,
      'part_number': instance.partNumber,
      'part_label': instance.partLabel,
      'created_at': instance.createdAt.toIso8601String(),
    };
