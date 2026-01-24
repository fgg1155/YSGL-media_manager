import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/app_providers.dart';
import 'core/services/backend_mode.dart';
import 'core/config/app_config.dart';
import 'core/utils/snackbar_utils.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

class MediaManagerApp extends ConsumerStatefulWidget {
  final String? initialApiUrl;
  
  const MediaManagerApp({super.key, this.initialApiUrl});

  @override
  ConsumerState<MediaManagerApp> createState() => _MediaManagerAppState();
}

class _MediaManagerAppState extends ConsumerState<MediaManagerApp> {
  bool _isInitialized = false;
  String? _initError;
  bool _showConnectionLostDialog = false;
  BackendModeManager? _modeManager;

  @override
  void initState() {
    super.initState();
    // 如果有初始 API URL，立即设置
    if (widget.initialApiUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(apiBaseUrlProvider.notifier).state = widget.initialApiUrl!;
        print('📱 Set initial API URL: ${widget.initialApiUrl}');
      });
    }
    _initializeApp();
  }

  @override
  void dispose() {
    // 停止定期健康检查
    _modeManager?.stopPeriodicHealthCheck();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      // 初始化应用
      final initializer = ref.read(appInitializerProvider);
      await initializer.initialize();
      
      // 启动定期健康检查
      _modeManager = ref.read(backendModeManagerProvider);
      _modeManager!.startPeriodicHealthCheck(() {
        if (mounted && !_showConnectionLostDialog) {
          _showConnectionLostDialog = true;
          _handleConnectionLost();
        }
      });
      
      setState(() {
        _isInitialized = true;
      });
      
      // 触发设置页面刷新，确保显示正确的模式图标
      try {
        ref.read(settingsRefreshProvider.notifier).state++;
      } catch (e) {
        // 忽略错误（settingsRefreshProvider 可能还未初始化）
      }
    } catch (e) {
      setState(() {
        _initError = e.toString();
        _isInitialized = true; // 即使失败也继续运行
      });
      print('App initialization error: $e');
    }
  }

  Future<void> _handleConnectionLost() async {
    if (!mounted) return;
    
    final shouldRetry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('连接断开'),
          ],
        ),
        content: const Text('与后端服务器的连接已断开。\n\n请确保后端服务器正在运行：\ncd media_manager_backend && cargo run'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重试连接'),
          ),
        ],
      ),
    );

    _showConnectionLostDialog = false;

    if (shouldRetry == true && mounted) {
      // 尝试重新连接
      final modeManager = ref.read(backendModeManagerProvider);
      final isAvailable = await modeManager.checkPcBackendAvailability();
      
      if (isAvailable) {
        if (mounted) {
          context.showSuccess('✓ 已重新连接到后端服务器');
        }
      } else {
        if (mounted) {
          context.showError('✗ 无法连接到后端服务器');
          // 再次显示对话框
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _showConnectionLostDialog = true;
              _handleConnectionLost();
            }
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 显示启动画面直到初始化完成
    if (!_isInitialized) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Initializing Media Manager...',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 如果初始化失败，显示错误信息
    if (_initError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Initialization Warning',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _initError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'App will continue in standalone mode',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _initError = null;
                      });
                    },
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 正常启动应用
    final router = ref.watch(appRouterProvider);
    
    // 智能选择locale：优先使用系统locale，如果不支持则fallback到中文
    final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
    final systemLocale = platformDispatcher.locale;
    
    // 支持的语言列表
    const supportedLanguages = ['zh', 'en', 'ja'];
    
    // 检查系统语言是否在支持列表中
    Locale? appLocale;
    if (supportedLanguages.contains(systemLocale.languageCode)) {
      appLocale = systemLocale;
      print('🌍 Using system locale: $systemLocale');
    } else {
      // Fallback到中文
      appLocale = const Locale('zh', 'CN');
      print('🌍 System locale $systemLocale not supported, fallback to Chinese');
    }
    
    return MaterialApp.router(
      title: 'Media Manager',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: appLocale, // 使用智能选择的locale
      // 本地化配置
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
        Locale('ja', 'JP'),
      ],
    );
  }
}