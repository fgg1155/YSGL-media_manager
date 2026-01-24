import 'package:flutter/material.dart';

/// SnackBar工具类
class SnackBarUtils {
  /// 显示成功消息
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
  }

  /// 显示错误消息
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
  }

  /// 显示警告消息
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
  }

  /// 显示信息消息
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
  }

  /// 显示加载中消息（带进度指示器）
  static void showLoading(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          duration: const Duration(days: 1), // 长时间显示，需要手动关闭
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 隐藏当前SnackBar
  static void hide(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// 显示带操作按钮的SnackBar
  static void showWithAction(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          action: SnackBarAction(
            label: actionLabel,
            textColor: Colors.white,
            onPressed: onAction,
          ),
        ),
      );
  }
}

/// 扩展方法：为BuildContext添加快捷方法
extension SnackBarExtension on BuildContext {
  /// 显示成功消息
  void showSuccess(String message) {
    SnackBarUtils.showSuccess(this, message);
  }

  /// 显示错误消息
  void showError(String message) {
    SnackBarUtils.showError(this, message);
  }

  /// 显示警告消息
  void showWarning(String message) {
    SnackBarUtils.showWarning(this, message);
  }

  /// 显示信息消息
  void showInfo(String message) {
    SnackBarUtils.showInfo(this, message);
  }

  /// 显示加载中消息
  void showLoading(String message) {
    SnackBarUtils.showLoading(this, message);
  }

  /// 隐藏SnackBar
  void hideSnackBar() {
    SnackBarUtils.hide(this);
  }
}
