import 'backend_mode.dart';
import 'local_http_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/image_proxy.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// 应用初始化服务
class AppInitializer {
  final BackendModeManager modeManager;
  final LocalHttpServer? localServer;
  final Function(String)? onBackendUrlChanged;

  AppInitializer({
    required this.modeManager,
    this.localServer,
    this.onBackendUrlChanged,
  });

  /// 判断是否为移动端
  bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (e) {
      return false;
    }
  }

  /// 初始化应用
  Future<void> initialize() async {
    print('=== Initializing Media Manager App ===');
    print('Platform: ${_isMobile ? "Mobile" : "Desktop"}');

    // 1. 加载用户偏好设置
    final prefs = await SharedPreferences.getInstance();
    
    BackendMode selectedMode;
    
    if (_isMobile) {
      // 移动端：可以选择模式
      final savedMode = prefs.getString('backend_mode');
      
      if (savedMode != null) {
        // 使用保存的模式
        switch (savedMode) {
          case 'pc':
            selectedMode = BackendMode.pc;
            break;
          case 'standalone':
            selectedMode = BackendMode.standalone;
            break;
          default:
            selectedMode = BackendMode.standalone;
        }
      } else {
        // 首次启动：默认独立模式
        selectedMode = BackendMode.standalone;
        await prefs.setString('backend_mode', selectedMode.name);
        print('✓ 移动端首次启动，设置默认模式: $selectedMode');
      }
    } else {
      // 桌面端：强制使用 PC 模式
      selectedMode = BackendMode.pc;
      // 确保保存为 PC 模式
      await prefs.setString('backend_mode', 'pc');
      print('✓ 桌面端强制使用 PC 模式');
    }
    
    modeManager.setMode(selectedMode);
    print('✓ 使用模式: $selectedMode');

    // 2. 加载 PC 后端 URL（不再自动检测）
    String pcBackendUrl = prefs.getString('pc_backend_url') ?? 'http://localhost:3000';
    print('📝 当前保存的 PC 后端地址: $pcBackendUrl');
    
    modeManager.setPcBackendUrl(pcBackendUrl);
    print('✓ 设置 modeManager PC 后端地址: $pcBackendUrl');
    
    // 通知 URL 变更（更新 apiBaseUrlProvider）
    if (onBackendUrlChanged != null) {
      onBackendUrlChanged!(pcBackendUrl);
      print('✓ 调用 onBackendUrlChanged 回调');
    }

    // 3. 根据模式和平台启动相应服务
    if (selectedMode == BackendMode.standalone && localServer != null && _isMobile) {
      // 独立模式 + 移动端：启动本地 HTTP 服务器，禁用图片代理
      try {
        await localServer!.start();
        setImageProxyEnabled(false);  // 独立模式下直接加载外链图片
        print('✓ Running in STANDALONE mode (Mobile)');
        print('  - Local HTTP server: http://localhost:${localServer!.port}');
        print('  - Userscript should connect to: http://localhost:${localServer!.port}/api');
        print('  - Image proxy: DISABLED (direct loading)');
      } catch (e) {
        print('⚠️  Failed to start local server: $e');
        print('  - App will continue in standalone mode without server');
      }
    } else if (selectedMode == BackendMode.standalone && !_isMobile) {
      // 独立模式 + 桌面端：不启动服务器，禁用图片代理
      setImageProxyEnabled(false);
      print('✓ Running in STANDALONE mode (Desktop)');
      print('  - Local HTTP server: DISABLED (desktop platform)');
      print('  - Image proxy: DISABLED (direct loading)');
    } else if (selectedMode == BackendMode.pc) {
      // PC 模式：不启动本地服务器，启用图片代理
      setImageProxyEnabled(true);  // PC 模式下使用后端代理
      print('✓ Running in PC mode');
      print('  - Backend URL: $pcBackendUrl');
      print('  - Userscript should connect to: $pcBackendUrl/api');
      print('  - Image proxy: ENABLED (via backend)');
    }

    print('=== Initialization complete ===');
  }

  /// 切换模式
  Future<void> switchMode(BackendMode newMode) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 保存新模式
    await prefs.setString('backend_mode', newMode.name);
    modeManager.setMode(newMode);

    // 重新初始化
    await initialize();
  }
}
