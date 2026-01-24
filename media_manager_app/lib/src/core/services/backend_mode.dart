import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';

/// 后端模式配置
enum BackendMode {
  /// PC 模式：连接到 Rust 后端服务器
  pc,
  
  /// 独立模式：使用本地服务和 Dart 实现
  standalone,
  
  /// 自动模式：自动检测并选择
  auto,
}

/// 后端模式管理器
class BackendModeManager {
  BackendMode _currentMode = BackendMode.auto;
  String? _pcBackendUrl;
  bool _pcBackendAvailable = false;
  Timer? _healthCheckTimer;
  DateTime? _lastCheckTime;
  static const _checkCacheDuration = Duration(minutes: 5); // 缓存 5 分钟，避免频繁检测
  
  /// 获取 PC 后端 URL 的回调函数
  String Function()? _getBackendUrl;

  BackendMode get currentMode => _currentMode;
  bool get isPcMode => _currentMode == BackendMode.pc;
  bool get isStandaloneMode => _currentMode == BackendMode.standalone;
  bool get isPcBackendAvailable => _pcBackendAvailable;

  /// 设置获取后端 URL 的回调
  void setBackendUrlProvider(String Function() provider) {
    _getBackendUrl = provider;
  }

  /// 设置模式
  void setMode(BackendMode mode) {
    _currentMode = mode;
  }

  /// 设置 PC 后端 URL
  void setPcBackendUrl(String url) {
    _pcBackendUrl = url;
  }
  
  /// 获取当前的 PC 后端 URL
  String? get _currentBackendUrl {
    // 优先使用回调函数获取的 URL
    if (_getBackendUrl != null) {
      return _getBackendUrl!();
    }
    // 回退到直接设置的 URL
    return _pcBackendUrl;
  }

  /// 启动定期健康检查（每 30 秒检查一次）
  void startPeriodicHealthCheck(Function() onConnectionLost) {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_currentMode == BackendMode.pc) {
        final isAvailable = await checkPcBackendAvailability();
        if (!isAvailable) {
          print('⚠️ PC backend connection lost!');
          onConnectionLost();
        }
      }
    });
  }

  /// 停止定期健康检查
  void stopPeriodicHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// 检测 PC 后端是否可用（带重试机制）
  Future<bool> checkPcBackendAvailability() async {
    final backendUrl = _currentBackendUrl;
    if (backendUrl == null) return false;
    
    // 尝试 3 次，每次超时 5 秒
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        print('Checking PC backend availability (attempt $attempt/3)...');
        // 健康检查端点在 /api/health
        final healthUrl = backendUrl.endsWith('/') 
            ? '${backendUrl}api/health' 
            : '$backendUrl/api/health';
        final response = await http.get(
          Uri.parse(healthUrl),
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          _pcBackendAvailable = true;
          print('✓ PC backend is available');
          return true;
        }
      } catch (e) {
        print('✗ Backend check attempt $attempt failed: $e');
        if (attempt < 3) {
          // 等待 1 秒后重试
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    
    _pcBackendAvailable = false;
    print('✗ PC backend is not available after 3 attempts');
    return false;
  }

  /// 自动选择模式
  Future<BackendMode> autoSelectMode({bool forceRecheck = false}) async {
    // 检查缓存是否有效
    final now = DateTime.now();
    final cacheValid = _lastCheckTime != null && 
                       now.difference(_lastCheckTime!) < _checkCacheDuration;
    
    // 如果不强制重新检测，且缓存有效，且当前不是 auto 模式，则返回缓存的模式
    if (!forceRecheck && cacheValid && _currentMode != BackendMode.auto) {
      return _currentMode;
    }

    // Web 平台强制使用 PC 模式（sqflite 不支持 Web）
    if (kIsWeb) {
      final pcAvailable = await checkPcBackendAvailability();
      _lastCheckTime = DateTime.now();
      if (pcAvailable) {
        print('✓ Web platform: PC backend available, using PC mode');
        _currentMode = BackendMode.pc;
        return BackendMode.pc;
      } else {
        print('✗ Web platform: PC backend not available! Please start the backend server.');
        print('  Run: cd media_manager_backend && cargo run');
        // Web 平台没有独立模式，必须使用 PC 后端
        throw Exception('Web platform requires PC backend. Please start the backend server at http://localhost:3000');
      }
    }

    // 移动端：重新检测 PC 后端
    print('📱 Mobile platform: checking PC backend availability...');
    final pcAvailable = await checkPcBackendAvailability();
    _lastCheckTime = DateTime.now();
    
    if (pcAvailable) {
      print('✓ PC backend available, using PC mode');
      print('  Data will be stored on PC backend');
      _currentMode = BackendMode.pc;
      return BackendMode.pc;
    } else {
      print('✓ PC backend not available, using standalone mode (local database)');
      print('  Data will be stored locally on device');
      _currentMode = BackendMode.standalone;
      return BackendMode.standalone;
    }
  }

  /// 重置模式为 auto，强制下次重新检测
  void resetToAuto() {
    _currentMode = BackendMode.auto;
    _pcBackendAvailable = false;
    _lastCheckTime = null;
    print('🔄 Backend mode reset to auto');
  }
}
