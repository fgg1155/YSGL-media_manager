import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collection.dart';
import '../models/media_item.dart';
import 'api_service.dart';

// Export format version for compatibility
const exportFormatVersion = '1.0';

// Export data structure
class ExportData {
  final String version;
  final DateTime exportedAt;
  final String? deviceId;
  final List<MediaItem> mediaItems;
  final List<Collection> collections;
  final Map<String, dynamic> settings;

  const ExportData({
    required this.version,
    required this.exportedAt,
    this.deviceId,
    required this.mediaItems,
    required this.collections,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'exportedAt': exportedAt.toIso8601String(),
    'deviceId': deviceId,
    'mediaItems': mediaItems.map((e) => e.toJson()).toList(),
    'collections': collections.map((e) => e.toJson()).toList(),
    'settings': settings,
  };

  factory ExportData.fromJson(Map<String, dynamic> json) {
    return ExportData(
      version: json['version'],
      exportedAt: DateTime.parse(json['exportedAt']),
      deviceId: json['deviceId'],
      mediaItems: (json['mediaItems'] as List)
          .map((e) => MediaItem.fromJson(e))
          .toList(),
      collections: (json['collections'] as List)
          .map((e) => Collection.fromJson(e))
          .toList(),
      settings: json['settings'] ?? {},
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ExportData.fromJsonString(String jsonString) {
    return ExportData.fromJson(jsonDecode(jsonString));
  }
}

// Import result
class ImportResult {
  final bool success;
  final int mediaItemsImported;
  final int collectionsImported;
  final List<String> errors;
  final List<String> warnings;

  const ImportResult({
    required this.success,
    required this.mediaItemsImported,
    required this.collectionsImported,
    this.errors = const [],
    this.warnings = const [],
  });

  factory ImportResult.error(String message) => ImportResult(
    success: false,
    mediaItemsImported: 0,
    collectionsImported: 0,
    errors: [message],
  );
}

// Export/Import service
class ExportService {
  final ApiService _apiService;

  ExportService(this._apiService);

  // Export all data
  Future<ExportData> exportAll({String? deviceId}) async {
    try {
      // Fetch all media items
      final mediaResponse = await _apiService.getMediaList(limit: 10000);
      
      // Fetch all collections
      final collections = await _apiService.getCollections();

      return ExportData(
        version: exportFormatVersion,
        exportedAt: DateTime.now(),
        deviceId: deviceId,
        mediaItems: mediaResponse.items,
        collections: collections,
        settings: {}, // TODO: Add user settings export
      );
    } catch (e) {
      throw ExportException('Failed to export data: $e');
    }
  }

  // Export to JSON string
  Future<String> exportToJson({String? deviceId}) async {
    final data = await exportAll(deviceId: deviceId);
    return data.toJsonString();
  }

  // Validate import data
  ImportValidation validateImportData(String jsonString) {
    try {
      final data = ExportData.fromJsonString(jsonString);
      
      final warnings = <String>[];
      
      // Check version compatibility
      if (data.version != exportFormatVersion) {
        warnings.add('Data version (${data.version}) differs from current ($exportFormatVersion)');
      }

      // Validate media items
      for (final item in data.mediaItems) {
        if (item.title.isEmpty) {
          warnings.add('Media item with empty title found');
        }
      }

      return ImportValidation(
        isValid: true,
        data: data,
        warnings: warnings,
      );
    } catch (e) {
      return ImportValidation(
        isValid: false,
        errorMessage: 'Invalid data format: $e',
      );
    }
  }

  // Import data
  Future<ImportResult> importData(
    ExportData data, {
    bool overwriteExisting = false,
    bool skipErrors = true,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];
    var mediaImported = 0;
    var collectionsImported = 0;

    // Import media items
    for (final item in data.mediaItems) {
      try {
        await _apiService.createMedia(CreateMediaRequest(
          title: item.title,
          mediaType: item.mediaType,
          year: item.year,
          overview: item.overview,
          genres: item.genres,
        ));
        mediaImported++;
      } catch (e) {
        if (skipErrors) {
          errors.add('Failed to import media "${item.title}": $e');
        } else {
          return ImportResult.error('Failed to import media "${item.title}": $e');
        }
      }
    }

    // Import collections
    for (final collection in data.collections) {
      try {
        await _apiService.addToCollection(AddToCollectionRequest(
          mediaId: collection.mediaId,
          watchStatus: collection.watchStatus,
        ));
        collectionsImported++;
      } catch (e) {
        if (skipErrors) {
          errors.add('Failed to import collection for media ${collection.mediaId}: $e');
        } else {
          return ImportResult.error('Failed to import collection: $e');
        }
      }
    }

    return ImportResult(
      success: errors.isEmpty,
      mediaItemsImported: mediaImported,
      collectionsImported: collectionsImported,
      errors: errors,
      warnings: warnings,
    );
  }

  // Import from JSON string
  Future<ImportResult> importFromJson(
    String jsonString, {
    bool overwriteExisting = false,
    bool skipErrors = true,
  }) async {
    final validation = validateImportData(jsonString);
    
    if (!validation.isValid) {
      return ImportResult.error(validation.errorMessage ?? 'Invalid data');
    }

    return importData(
      validation.data!,
      overwriteExisting: overwriteExisting,
      skipErrors: skipErrors,
    );
  }
}

// Import validation result
class ImportValidation {
  final bool isValid;
  final ExportData? data;
  final String? errorMessage;
  final List<String> warnings;

  const ImportValidation({
    required this.isValid,
    this.data,
    this.errorMessage,
    this.warnings = const [],
  });
}

// Export exception
class ExportException implements Exception {
  final String message;
  const ExportException(this.message);
  
  @override
  String toString() => 'ExportException: $message';
}

// Provider
final exportServiceProvider = Provider<ExportService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return ExportService(apiService);
});
