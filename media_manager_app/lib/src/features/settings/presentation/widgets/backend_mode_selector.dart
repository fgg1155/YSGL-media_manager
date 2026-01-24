import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/backend_mode.dart';
import '../../../../core/services/app_initializer.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/utils/loading_state.dart';

/// 后端模式选择器
class BackendModeSelector extends ConsumerStatefulWidget {
  final BackendModeManager modeManager;
  final AppInitializer appInitializer;

  const BackendModeSelector({
    super.key,
    required this.modeManager,
    required this.appInitializer,
  });

  @override
  ConsumerState<BackendModeSelector> createState() => _BackendModeSelectorState();
}

class _BackendModeSelectorState extends ConsumerState<BackendModeSelector> with LoadingStateMixin {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '后端模式',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '选择应用的运行模式',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            // 自动模式
            _buildModeOption(
              mode: BackendMode.auto,
              title: '自动模式',
              subtitle: '自动检测并选择最佳模式',
              icon: Icons.auto_awesome,
            ),
            
            // PC 模式
            _buildModeOption(
              mode: BackendMode.pc,
              title: 'PC 模式',
              subtitle: '连接到 Rust 后端服务器（功能完整）',
              icon: Icons.computer,
            ),
            
            // 独立模式
            _buildModeOption(
              mode: BackendMode.standalone,
              title: '独立模式',
              subtitle: 'Android 独立运行（无需 PC）',
              icon: Icons.phone_android,
            ),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption({
    required BackendMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = widget.modeManager.currentMode == mode;

    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blue)
          : null,
      selected: isSelected,
      onTap: isLoading ? null : () => _switchMode(mode),
    );
  }

  Future<void> _switchMode(BackendMode mode) async {
    await executeWithLoading(
      () => widget.appInitializer.switchMode(mode),
      onSuccess: (_) {
        if (mounted) {
          context.showSuccess('已切换到${_getModeName(mode)}');
        }
      },
      onError: (e) {
        if (mounted) {
          context.showError('切换失败: $e');
        }
      },
    );
  }

  String _getModeName(BackendMode mode) {
    switch (mode) {
      case BackendMode.auto:
        return '自动模式';
      case BackendMode.pc:
        return 'PC 模式';
      case BackendMode.standalone:
        return '独立模式';
    }
  }
}
