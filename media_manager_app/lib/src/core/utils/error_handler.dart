import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

/// 统一的错误处理工具类
class ErrorHandler {
  /// 处理API调用错误并显示SnackBar
  static void handleError(
    BuildContext context,
    dynamic error, {
    String? customMessage,
    bool mounted = true,
  }) {
    if (!mounted || !context.mounted) return;

    final message = customMessage ?? _getErrorMessage(error);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 处理API调用错误并返回错误消息
  static String getErrorMessage(dynamic error) {
    return _getErrorMessage(error);
  }

  /// 内部方法：根据错误类型生成错误消息
  static String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      return _handleDioError(error);
    }
    
    return error.toString();
  }

  /// 处理Dio错误
  static String _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络';
      
      case DioExceptionType.badResponse:
        return _handleBadResponse(error);
      
      case DioExceptionType.cancel:
        return '请求已取消';
      
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络设置';
      
      case DioExceptionType.badCertificate:
        return '证书验证失败';
      
      case DioExceptionType.unknown:
      default:
        return '未知错误: ${error.message}';
    }
  }

  /// 处理HTTP响应错误
  static String _handleBadResponse(DioException error) {
    final statusCode = error.response?.statusCode;
    
    switch (statusCode) {
      case 400:
        return '请求参数错误';
      case 401:
        return '未授权，请重新登录';
      case 403:
        return '权限不足';
      case 404:
        return '资源不存在';
      case 422:
        return '数据验证失败';
      case 500:
        return '服务器内部错误';
      case 502:
        return '网关错误';
      case 503:
        return '服务暂时不可用';
      default:
        return '请求失败 (${statusCode ?? 'unknown'})';
    }
  }

  /// 安全执行异步操作，自动处理错误
  static Future<T?> safeExecute<T>(
    Future<T> Function() operation, {
    BuildContext? context,
    String? errorMessage,
    T? defaultValue,
    bool showError = true,
  }) async {
    try {
      return await operation();
    } catch (e) {
      if (showError && context != null && context.mounted) {
        handleError(context, e, customMessage: errorMessage);
      }
      return defaultValue;
    }
  }

  /// 安全执行同步操作，自动处理错误
  static T? safeExecuteSync<T>(
    T Function() operation, {
    BuildContext? context,
    String? errorMessage,
    T? defaultValue,
    bool showError = true,
  }) {
    try {
      return operation();
    } catch (e) {
      if (showError && context != null && context.mounted) {
        handleError(context, e, customMessage: errorMessage);
      }
      return defaultValue;
    }
  }
}

/// 扩展方法：为Future添加错误处理
extension FutureErrorHandling<T> on Future<T> {
  /// 自动处理错误并显示SnackBar
  Future<T?> handleError(
    BuildContext context, {
    String? errorMessage,
    T? defaultValue,
  }) async {
    try {
      return await this;
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.handleError(context, e, customMessage: errorMessage);
      }
      return defaultValue;
    }
  }

  /// 自动处理错误但不显示UI
  Future<T?> catchError({T? defaultValue}) async {
    try {
      return await this;
    } catch (e) {
      debugPrint('Error: $e');
      return defaultValue;
    }
  }
}
