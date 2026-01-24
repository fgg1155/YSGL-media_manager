import 'package:flutter/material.dart';

/// 加载状态枚举
enum LoadingStatus {
  idle,
  loading,
  success,
  error,
}

/// 加载状态数据类
class LoadingState<T> {
  final LoadingStatus status;
  final T? data;
  final String? error;

  const LoadingState({
    required this.status,
    this.data,
    this.error,
  });

  /// 创建空闲状态
  factory LoadingState.idle() => const LoadingState(status: LoadingStatus.idle);

  /// 创建加载中状态
  factory LoadingState.loading() => const LoadingState(status: LoadingStatus.loading);

  /// 创建成功状态
  factory LoadingState.success(T data) => LoadingState(
        status: LoadingStatus.success,
        data: data,
      );

  /// 创建错误状态
  factory LoadingState.error(String error) => LoadingState(
        status: LoadingStatus.error,
        error: error,
      );

  /// 是否正在加载
  bool get isLoading => status == LoadingStatus.loading;

  /// 是否成功
  bool get isSuccess => status == LoadingStatus.success;

  /// 是否错误
  bool get isError => status == LoadingStatus.error;

  /// 是否空闲
  bool get isIdle => status == LoadingStatus.idle;

  /// 复制并修改状态
  LoadingState<T> copyWith({
    LoadingStatus? status,
    T? data,
    String? error,
  }) {
    return LoadingState<T>(
      status: status ?? this.status,
      data: data ?? this.data,
      error: error ?? this.error,
    );
  }
}

/// 加载状态管理Mixin
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 设置加载状态
  void setLoading(bool loading) {
    if (mounted) {
      setState(() {
        _isLoading = loading;
        if (loading) {
          _errorMessage = null;
        }
      });
    }
  }

  /// 设置错误消息
  void setError(String? error) {
    if (mounted) {
      setState(() {
        _errorMessage = error;
        _isLoading = false;
      });
    }
  }

  /// 清除错误
  void clearError() {
    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  /// 执行异步操作并自动管理加载状态
  Future<R?> executeWithLoading<R>(
    Future<R> Function() operation, {
    String? errorMessage,
    void Function(R)? onSuccess,
    void Function(dynamic)? onError,
  }) async {
    setLoading(true);
    try {
      final result = await operation();
      setLoading(false);
      onSuccess?.call(result);
      return result;
    } catch (e) {
      setError(errorMessage ?? e.toString());
      onError?.call(e);
      return null;
    }
  }
}

/// 加载状态构建器Widget
class LoadingStateBuilder<T> extends StatelessWidget {
  final LoadingState<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, String error)? errorBuilder;
  final Widget Function(BuildContext context)? idleBuilder;

  const LoadingStateBuilder({
    super.key,
    required this.state,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.idleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case LoadingStatus.idle:
        return idleBuilder?.call(context) ?? const SizedBox.shrink();

      case LoadingStatus.loading:
        return loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator());

      case LoadingStatus.success:
        if (state.data != null) {
          return builder(context, state.data as T);
        }
        return const SizedBox.shrink();

      case LoadingStatus.error:
        return errorBuilder?.call(context, state.error ?? 'Unknown error') ??
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    state.error ?? 'Unknown error',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
    }
  }
}
