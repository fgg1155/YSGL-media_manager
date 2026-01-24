import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Security configuration
class SecurityConfig {
  final bool encryptLocalData;
  final bool requireHttps;
  final bool enableDataPrivacy;
  final int sessionTimeoutMinutes;

  const SecurityConfig({
    this.encryptLocalData = true,
    this.requireHttps = true,
    this.enableDataPrivacy = true,
    this.sessionTimeoutMinutes = 30,
  });

  SecurityConfig copyWith({
    bool? encryptLocalData,
    bool? requireHttps,
    bool? enableDataPrivacy,
    int? sessionTimeoutMinutes,
  }) {
    return SecurityConfig(
      encryptLocalData: encryptLocalData ?? this.encryptLocalData,
      requireHttps: requireHttps ?? this.requireHttps,
      enableDataPrivacy: enableDataPrivacy ?? this.enableDataPrivacy,
      sessionTimeoutMinutes: sessionTimeoutMinutes ?? this.sessionTimeoutMinutes,
    );
  }
}

/// Simple encryption service (for demonstration - use proper encryption in production)
class EncryptionService {
  // In production, use flutter_secure_storage or similar
  // This is a simplified XOR-based obfuscation for demonstration
  
  final String _key;
  
  EncryptionService(this._key);
  
  /// Encrypt a string
  String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;
    
    final keyBytes = utf8.encode(_key);
    final textBytes = utf8.encode(plainText);
    final encrypted = Uint8List(textBytes.length);
    
    for (var i = 0; i < textBytes.length; i++) {
      encrypted[i] = textBytes[i] ^ keyBytes[i % keyBytes.length];
    }
    
    return base64Encode(encrypted);
  }
  
  /// Decrypt a string
  String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;
    
    try {
      final keyBytes = utf8.encode(_key);
      final encrypted = base64Decode(encryptedText);
      final decrypted = Uint8List(encrypted.length);
      
      for (var i = 0; i < encrypted.length; i++) {
        decrypted[i] = encrypted[i] ^ keyBytes[i % keyBytes.length];
      }
      
      return utf8.decode(decrypted);
    } catch (e) {
      return encryptedText; // Return original if decryption fails
    }
  }
  
  /// Generate a random key
  static String generateKey({int length = 32}) {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

/// Secure storage wrapper
class SecureStorage {
  final SharedPreferences _prefs;
  final EncryptionService _encryption;
  
  static const _keyPrefix = 'secure_';
  
  SecureStorage(this._prefs, this._encryption);
  
  /// Store encrypted value
  Future<void> write(String key, String value) async {
    final encrypted = _encryption.encrypt(value);
    await _prefs.setString('$_keyPrefix$key', encrypted);
  }
  
  /// Read and decrypt value
  String? read(String key) {
    final encrypted = _prefs.getString('$_keyPrefix$key');
    if (encrypted == null) return null;
    return _encryption.decrypt(encrypted);
  }
  
  /// Delete value
  Future<void> delete(String key) async {
    await _prefs.remove('$_keyPrefix$key');
  }
  
  /// Check if key exists
  bool containsKey(String key) {
    return _prefs.containsKey('$_keyPrefix$key');
  }
  
  /// Clear all secure storage
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

/// Privacy settings
class PrivacySettings {
  final bool shareAnalytics;
  final bool shareUsageData;
  final bool allowPersonalization;
  final bool storeSearchHistory;

  const PrivacySettings({
    this.shareAnalytics = false,
    this.shareUsageData = false,
    this.allowPersonalization = true,
    this.storeSearchHistory = true,
  });

  PrivacySettings copyWith({
    bool? shareAnalytics,
    bool? shareUsageData,
    bool? allowPersonalization,
    bool? storeSearchHistory,
  }) {
    return PrivacySettings(
      shareAnalytics: shareAnalytics ?? this.shareAnalytics,
      shareUsageData: shareUsageData ?? this.shareUsageData,
      allowPersonalization: allowPersonalization ?? this.allowPersonalization,
      storeSearchHistory: storeSearchHistory ?? this.storeSearchHistory,
    );
  }

  Map<String, dynamic> toJson() => {
    'shareAnalytics': shareAnalytics,
    'shareUsageData': shareUsageData,
    'allowPersonalization': allowPersonalization,
    'storeSearchHistory': storeSearchHistory,
  };

  factory PrivacySettings.fromJson(Map<String, dynamic> json) {
    return PrivacySettings(
      shareAnalytics: json['shareAnalytics'] ?? false,
      shareUsageData: json['shareUsageData'] ?? false,
      allowPersonalization: json['allowPersonalization'] ?? true,
      storeSearchHistory: json['storeSearchHistory'] ?? true,
    );
  }
}

/// Security service
class SecurityService {
  final EncryptionService _encryption;
  final SecureStorage _secureStorage;
  SecurityConfig _config;
  PrivacySettings _privacySettings;

  SecurityService(
    this._encryption,
    this._secureStorage, {
    SecurityConfig? config,
    PrivacySettings? privacySettings,
  })  : _config = config ?? const SecurityConfig(),
        _privacySettings = privacySettings ?? const PrivacySettings();

  SecurityConfig get config => _config;
  PrivacySettings get privacySettings => _privacySettings;

  /// Update security config
  void updateConfig(SecurityConfig config) {
    _config = config;
  }

  /// Update privacy settings
  void updatePrivacySettings(PrivacySettings settings) {
    _privacySettings = settings;
  }

  /// Validate URL is HTTPS (if required)
  bool validateUrl(String url) {
    if (!_config.requireHttps) return true;
    return url.startsWith('https://') || url.startsWith('http://localhost');
  }

  /// Store sensitive data
  Future<void> storeSensitiveData(String key, String value) async {
    if (_config.encryptLocalData) {
      await _secureStorage.write(key, value);
    }
  }

  /// Retrieve sensitive data
  String? getSensitiveData(String key) {
    if (_config.encryptLocalData) {
      return _secureStorage.read(key);
    }
    return null;
  }

  /// Clear all sensitive data
  Future<void> clearSensitiveData() async {
    await _secureStorage.clearAll();
  }

  /// Check if data collection is allowed
  bool canCollectData(DataCollectionType type) {
    switch (type) {
      case DataCollectionType.analytics:
        return _privacySettings.shareAnalytics;
      case DataCollectionType.usage:
        return _privacySettings.shareUsageData;
      case DataCollectionType.searchHistory:
        return _privacySettings.storeSearchHistory;
      case DataCollectionType.personalization:
        return _privacySettings.allowPersonalization;
    }
  }
}

enum DataCollectionType {
  analytics,
  usage,
  searchHistory,
  personalization,
}

// Providers
final encryptionKeyProvider = Provider<String>((ref) {
  // In production, retrieve from secure storage or generate once
  return 'media_manager_secure_key_2024';
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final key = ref.watch(encryptionKeyProvider);
  return EncryptionService(key);
});

final securityConfigProvider = StateProvider<SecurityConfig>((ref) {
  return const SecurityConfig();
});

final privacySettingsProvider = StateProvider<PrivacySettings>((ref) {
  return const PrivacySettings();
});
