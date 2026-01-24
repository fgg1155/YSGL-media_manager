import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API 服务器地址配置 Provider
/// 默认值为 localhost，用户可以在设置中修改
/// 注意：这里只存储基础 URL（不包含 /api 路径）
final apiBaseUrlProvider = StateProvider<String>((ref) {
  // 默认值
  return 'http://localhost:3000';
});

/// 从持久化存储加载 API 服务器地址
Future<String> loadApiBaseUrl() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // 统一使用 pc_backend_url key
    return prefs.getString('pc_backend_url') ?? 'http://localhost:3000';
  } catch (e) {
    return 'http://localhost:3000';
  }
}

/// 保存 API 服务器地址到持久化存储
Future<void> saveApiBaseUrl(String url) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // 统一使用 pc_backend_url key
    await prefs.setString('pc_backend_url', url);
  } catch (e) {
    // 忽略保存错误
  }
}

/// 获取完整的 API URL（包含 /api 路径）
String getFullApiUrl(String baseUrl) {
  // 移除末尾的斜杠
  final cleanUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  // 添加 /api 路径
  return '$cleanUrl/api';
}
