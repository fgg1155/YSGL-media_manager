import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/enhanced_sync_service.dart';
import '../../core/models/sync_models.dart';
import '../../core/services/backend_mode.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/snackbar_utils.dart';

/// Widget to display sync status and trigger manual sync
class SyncStatusWidget extends ConsumerWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(enhancedSyncServiceProvider);
    final syncService = ref.read(enhancedSyncServiceProvider.notifier);
    final modeManager = ref.watch(backendModeManagerProvider);
    final currentMode = modeManager.currentMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: _buildStatusIcon(syncState.status),
          title: Text(_getStatusText(syncState.status)),
          subtitle: syncState.lastSyncTime != null
              ? Text('上次同步: ${_formatDateTime(syncState.lastSyncTime!)}')
              : null,
          trailing: syncState.isSyncing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () => _handleSync(context, syncService, currentMode),
                  tooltip: '立即同步',
                ),
        ),
        if (syncState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      syncState.errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (syncState.hasPendingChanges)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '有未同步的更改',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return const Icon(Icons.cloud_done, color: Colors.grey);
      case SyncStatus.syncing:
        return const Icon(Icons.cloud_sync, color: Colors.blue);
      case SyncStatus.success:
        return const Icon(Icons.cloud_done, color: Colors.green);
      case SyncStatus.error:
        return const Icon(Icons.cloud_off, color: Colors.red);
      case SyncStatus.offline:
        return const Icon(Icons.cloud_off, color: Colors.orange);
    }
  }

  String _getStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '已同步';
      case SyncStatus.syncing:
        return '正在同步...';
      case SyncStatus.success:
        return '同步成功';
      case SyncStatus.error:
        return '同步失败';
      case SyncStatus.offline:
        return '离线模式';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _handleSync(BuildContext context, EnhancedSyncService syncService, BackendMode currentMode) async {
    // 如果是独立模式，显示提示
    if (currentMode == BackendMode.standalone) {
      if (!context.mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('需要切换到 PC 模式'),
            ],
          ),
          content: const Text(
            '同步功能需要连接到 PC 后端。\n\n'
            '请先切换到 PC 模式，然后再进行同步操作。\n\n'
            '切换方法：在首页顶部点击模式切换开关。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    
    // PC 模式下执行同步
    final result = await syncService.syncAll();
    
    if (!context.mounted) return;
    
    if (result.success) {
      context.showSuccess('同步成功！推送 ${result.itemsPushed} 项，拉取 ${result.itemsPulled} 项');
    } else {
      SnackBarUtils.showWithAction(
        context,
        '同步失败: ${result.errors.join(', ')}',
        actionLabel: '重试',
        onAction: () => _handleSync(context, syncService, currentMode),
        backgroundColor: Colors.red,
      );
    }
  }
}

/// Compact sync status indicator for app bar
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(enhancedSyncServiceProvider);

    return IconButton(
      icon: _buildIcon(syncState.status),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('同步状态'),
            content: const SyncStatusWidget(),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      },
      tooltip: _getTooltip(syncState.status),
    );
  }

  Widget _buildIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return const Icon(Icons.cloud_done);
      case SyncStatus.syncing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatus.success:
        return const Icon(Icons.cloud_done, color: Colors.green);
      case SyncStatus.error:
        return const Icon(Icons.cloud_off, color: Colors.red);
      case SyncStatus.offline:
        return const Icon(Icons.cloud_off, color: Colors.orange);
    }
  }

  String _getTooltip(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '已同步';
      case SyncStatus.syncing:
        return '正在同步';
      case SyncStatus.success:
        return '同步成功';
      case SyncStatus.error:
        return '同步失败';
      case SyncStatus.offline:
        return '离线模式';
    }
  }
}
