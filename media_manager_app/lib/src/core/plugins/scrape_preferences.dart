/// 刮削偏好设置管理
/// 
/// 管理用户的刮削相关偏好设置（如上次选择的 content_type）

import 'package:shared_preferences/shared_preferences.dart';

/// 刮削偏好设置管理器
class ScrapePreferences {
  // SharedPreferences 键名常量
  static const String _CONTENT_TYPE_KEY = 'last_scrape_content_type';
  
  /// 加载上次选择的 content_type
  /// 
  /// Returns:
  ///   上次选择的 content_type（'Scene' 或 'Movie'），如果没有则返回 null
  static Future<String?> loadLastContentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_CONTENT_TYPE_KEY);
    } catch (e) {
      print('⚠️ Failed to load last content type: $e');
      return null;
    }
  }
  
  /// 保存用户选择的 content_type
  /// 
  /// Args:
  ///   contentType: 用户选择的 content_type（'Scene' 或 'Movie'）
  static Future<void> saveContentType(String contentType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_CONTENT_TYPE_KEY, contentType);
    } catch (e) {
      print('⚠️ Failed to save content type: $e');
    }
  }
  
  /// 清除保存的 content_type
  static Future<void> clearContentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_CONTENT_TYPE_KEY);
    } catch (e) {
      print('⚠️ Failed to clear content type: $e');
    }
  }
}
