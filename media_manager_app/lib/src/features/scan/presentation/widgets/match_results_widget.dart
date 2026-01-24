import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/api_service.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../../media/providers/plugin_providers.dart';

class MatchResultsWidget extends ConsumerStatefulWidget {
  final MatchResponse matchResponse;
  final VoidCallback onConfirm;

  const MatchResultsWidget({
    super.key,
    required this.matchResponse,
    required this.onConfirm,
  });

  @override
  ConsumerState<MatchResultsWidget> createState() => _MatchResultsWidgetState();
}

class _MatchResultsWidgetState extends ConsumerState<MatchResultsWidget> {
  final Map<String, String> _selectedMatches = {}; // filePath -> mediaId (单文件)
  final Map<String, String> _selectedGroupMatches = {}; // baseName -> mediaId (文件组)
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    // 自动选择精确匹配和高置信度模糊匹配（单文件）
    for (final result in widget.matchResponse.matchResults) {
      if (result.matchType == 'exact' || 
          (result.matchType == 'fuzzy' && result.confidence > 0.8)) {
        if (result.matchedMedia != null) {
          _selectedMatches[result.scannedFile.filePath] = result.matchedMedia!.id;
        }
      }
    }
    
    // 自动选择精确匹配和高置信度模糊匹配（文件组）
    for (final result in widget.matchResponse.groupMatchResults) {
      if (result.matchType == 'exact' || 
          (result.matchType == 'fuzzy' && result.confidence > 0.8)) {
        if (result.matchedMedia != null) {
          _selectedGroupMatches[result.fileGroup.baseName] = result.matchedMedia!.id;
        }
      }
    }
  }

  Future<void> _confirmMatches() async {
    if (_selectedMatches.isEmpty && _selectedGroupMatches.isEmpty) {
      context.showWarning('请至少选择一个匹配');
      return;
    }

    setState(() {
      _isConfirming = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final matches = <ConfirmMatch>[];
      
      // 添加单文件匹配
      for (final entry in _selectedMatches.entries) {
        matches.add(ConfirmMatch.single(
          filePath: entry.key,
          mediaId: entry.value,
        ));
      }
      
      // 添加文件组匹配
      for (final entry in _selectedGroupMatches.entries) {
        final baseName = entry.key;
        final mediaId = entry.value;
        
        // 找到对应的文件组
        final groupResult = widget.matchResponse.groupMatchResults.firstWhere(
          (r) => r.fileGroup.baseName == baseName,
        );
        
        // 创建包含所有文件的 ConfirmMatch
        final files = groupResult.fileGroup.files.asMap().entries.map((fileEntry) {
          final index = fileEntry.key;
          final file = fileEntry.value;
          return FileInfo(
            filePath: file.filePath,
            fileSize: file.fileSize,
            partNumber: index + 1,
            partLabel: file.fileName,
          );
        }).toList();
        
        matches.add(ConfirmMatch(
          mediaId: mediaId,
          files: files,
        ));
      }
      
      final response = await apiService.confirmMatches(matches);

      if (mounted) {
        context.showSuccess(response.message);
        widget.onConfirm();
      }
    } catch (e) {
      if (mounted) {
        context.showError('确认失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConfirming = false;
        });
      }
    }
  }

  Future<void> _ignoreFile(ScannedFile file) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.ignoreFile(
        filePath: file.filePath,
        fileName: file.fileName,
        reason: '用户手动忽略',
      );

      if (mounted) {
        setState(() {
          _selectedMatches.remove(file.filePath);
        });
        context.showSuccess('已添加到忽略列表');
      }
    } catch (e) {
      if (mounted) {
        context.showError('忽略失败: $e');
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final totalSelected = _selectedMatches.length + _selectedGroupMatches.length;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '匹配结果',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // 统计信息
            LayoutBuilder(
              builder: (context, constraints) {
                // 移动端使用垂直布局，桌面端使用水平布局
                final isMobile = constraints.maxWidth < 600;
                
                if (isMobile) {
                  return Column(
                    children: [
                      _buildStatCard(
                        '精确匹配',
                        widget.matchResponse.exactMatches,
                        Colors.green,
                        Icons.check_circle,
                      ),
                      const SizedBox(height: 12),
                      _buildStatCard(
                        '模糊匹配',
                        widget.matchResponse.fuzzyMatches,
                        Colors.orange,
                        Icons.help_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildStatCard(
                        '未匹配',
                        widget.matchResponse.noMatches,
                        Colors.red,
                        Icons.cancel_outlined,
                      ),
                    ],
                  );
                } else {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          '精确匹配',
                          widget.matchResponse.exactMatches,
                          Colors.green,
                          Icons.check_circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '模糊匹配',
                          widget.matchResponse.fuzzyMatches,
                          Colors.orange,
                          Icons.help_outline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '未匹配',
                          widget.matchResponse.noMatches,
                          Colors.red,
                          Icons.cancel_outlined,
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // 已选择数量
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.playlist_add_check,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已自动选择高置信度匹配',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 $totalSelected 个文件将被关联到媒体库',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            
            // 确认按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConfirming || totalSelected == 0 ? null : _confirmMatches,
                icon: _isConfirming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _isConfirming 
                      ? '确认中...' 
                      : totalSelected == 0
                          ? '没有可确认的匹配'
                          : '确认匹配 ($totalSelected)',
                ),
              ),
            ),

            // 插件UI注入点 - scan_results_actions（根据后端已安装插件过滤）
            if (widget.matchResponse.noMatches > 0) ...[
              const SizedBox(height: 12),
              // 调试：检查按钮数量
              Builder(
                builder: (context) {
                  final installedIds = ref.watch(installedPluginIdsProvider);
                  final buttons = PluginUIRegistry().getButtonsFiltered('scan_results_actions', installedIds);
                  print('🔍 DEBUG: scan_results_actions buttons count: ${buttons.length}');
                  print('🔍 DEBUG: All injection points: ${PluginUIRegistry().injectionPoints}');
                  return const SizedBox.shrink();
                },
              ),
              ...PluginUIRegistry()
                  .getButtonsFiltered('scan_results_actions', ref.watch(installedPluginIdsProvider))
                  .map((button) {
                    // 收集未匹配的文件组
                    final unmatchedGroups = widget.matchResponse.groupMatchResults
                        .where((r) => r.matchType == 'none')
                        .map((r) => r.fileGroup)
                        .toList();

                    // 收集文件组中的所有文件路径
                    final groupedFilePaths = <String>{};
                    for (final group in unmatchedGroups) {
                      for (final file in group.files) {
                        groupedFilePaths.add(file.filePath);
                      }
                    }

                    // 获取所有未匹配的文件（排除已经在文件组中的文件）
                    final unmatchedFiles = widget.matchResponse.matchResults
                        .where((r) => r.matchType == 'none' && !groupedFilePaths.contains(r.scannedFile.filePath))
                        .map((r) => r.scannedFile)
                        .toList();

                    return SizedBox(
                      width: double.infinity,
                      child: PluginUIRenderer.renderButton(
                        button,
                        context,
                        contextData: {
                          'unmatched_files': unmatchedFiles.map((f) => f.toJson()).toList(),
                          'unmatched_groups': unmatchedGroups.map((g) => g.toJson()).toList(),
                          'unmatched_count': widget.matchResponse.noMatches,
                        },
                      ),
                    );
                  }),
            ],

          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
