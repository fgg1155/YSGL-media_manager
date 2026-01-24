import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/core/providers/app_providers.dart';
import 'src/core/config/app_config.dart';
import 'src/core/plugins/ui_registry.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 media_kit（用于视频播放）
  MediaKit.ensureInitialized();
  
  // 设置系统 UI 样式（状态栏透明 - 仅移动端有效）
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  
  // 初始化 sqflite_ffi（用于 Windows/Linux/macOS 桌面平台）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // 加载保存的 API 服务器地址
  final savedApiUrl = await loadApiBaseUrl();
  
  // 先启动应用，插件在后台异步加载（不阻塞启动）
  runApp(
    ProviderScope(
      child: MediaManagerApp(initialApiUrl: savedApiUrl),
    ),
  );
  
  // 异步加载插件UI配置（不阻塞应用启动）
  _loadPluginUIs();
}

/// 加载所有插件的UI配置
Future<void> _loadPluginUIs() async {
  try {
    print('🔌 ========================================');
    print('🔌 Starting Plugin UI Loading Process');
    print('🔌 ========================================');
    
    int successCount = 0;
    int failureCount = 0;
    
    // 加载 Media_Scraper 插件UI
    try {
      print('');
      print('📦 Loading Media_Scraper plugin...');
      await PluginUIRegistry.instance.loadPluginUI(
        'media_scraper',
        'assets/plugins/Media_Scraper/config/ui_manifest.yaml',
      );
      successCount++;
    } catch (e) {
      print('⚠️ Failed to load Media_Scraper UI: $e');
      failureCount++;
    }
    
    // 加载 Magnet_Scraper 插件UI
    try {
      print('');
      print('📦 Loading Magnet_Scraper plugin...');
      await PluginUIRegistry.instance.loadPluginUI(
        'multi-site-magnet',
        'assets/plugins/Magnet_Scraper/config/ui_manifest.yaml',
      );
      successCount++;
    } catch (e) {
      print('⚠️ Failed to load Magnet_Scraper UI: $e');
      failureCount++;
    }
    
    print('');
    print('🔌 ========================================');
    print('🔌 Plugin UI Loading Summary:');
    print('🔌   ✅ Success: $successCount');
    print('🔌   ❌ Failed: $failureCount');
    print('🔌 ========================================');
    
    // 输出已注册的注入点统计
    final registry = PluginUIRegistry.instance;
    final injectionPoints = registry.injectionPoints;
    if (injectionPoints.isNotEmpty) {
      print('');
      print('📍 Registered Injection Points:');
      for (final point in injectionPoints) {
        final buttons = registry.getButtons(point);
        print('   - $point: ${buttons.length} button(s)');
      }
    }
    
    print('');
  } catch (e) {
    print('❌ ========================================');
    print('❌ Critical Error in Plugin UI Loading');
    print('❌ Error: $e');
    print('❌ ========================================');
  }
}