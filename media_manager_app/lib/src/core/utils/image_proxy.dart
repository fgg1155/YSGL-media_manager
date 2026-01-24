import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// 服务器配置 - 与 api_service.dart 保持一致
const String _serverHost = '192.168.1.17';
const int _serverPort = 3000;

/// 全局标志：是否启用图片代理
/// 在独立模式下应该设置为 false，直接加载外链图片
bool _proxyEnabled = true;

/// 设置图片代理是否启用
void setImageProxyEnabled(bool enabled) {
  _proxyEnabled = enabled;
}

/// 获取平台适配的代理基础地址
String _getProxyBaseUrl() {
  if (kIsWeb) {
    return 'http://localhost:$_serverPort/api';
  }
  
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      return 'http://$_serverHost:$_serverPort/api';
    }
  } catch (e) {
    // 如果 Platform 不可用，回退到 localhost
  }
  
  return 'http://localhost:$_serverPort/api';
}

/// 判断 URL 是否需要代理
/// 外部图片 URL（非 TMDB、非本地）需要代理
bool _needsProxy(String url) {
  if (url.isEmpty) return false;
  
  // 如果代理未启用，不需要代理
  if (!_proxyEnabled) return false;
  
  // TMDB 图片不需要代理（有 CORS 支持）
  if (url.contains('tmdb.org') || url.contains('themoviedb.org')) {
    return false;
  }
  
  // 本地图片不需要代理
  if (url.startsWith('http://localhost') || 
      url.startsWith('http://127.0.0.1') ||
      url.startsWith('http://192.168.')) {
    return false;
  }
  
  // 其他外部图片需要代理
  return url.startsWith('http://') || url.startsWith('https://');
}

/// 获取代理后的图片 URL
/// 如果图片需要代理（外部图片），返回代理 URL
/// 否则返回原始 URL
String getProxiedImageUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  
  if (_needsProxy(url)) {
    final baseUrl = _getProxyBaseUrl();
    final encodedUrl = Uri.encodeComponent(url);
    return '$baseUrl/proxy/image?url=$encodedUrl';
  }
  
  return url;
}

/// 获取代理后的视频 URL
/// 如果视频需要代理（外部视频），返回代理 URL
/// 否则返回原始 URL
String getProxiedVideoUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  
  if (_needsProxy(url)) {
    final baseUrl = _getProxyBaseUrl();
    final encodedUrl = Uri.encodeComponent(url);
    return '$baseUrl/proxy/video?url=$encodedUrl';
  }
  
  return url;
}
