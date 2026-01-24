import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/providers/app_providers.dart';

/// 带缩略图的文件组卡片
class FileGroupCardWithThumbnail extends ConsumerStatefulWidget {
  final FileGroup group;
  final int index;

  const FileGroupCardWithThumbnail({
    super.key,
    required this.group,
    required this.index,
  });

  @override
  ConsumerState<FileGroupCardWithThumbnail> createState() =>
      _FileGroupCardWithThumbnailState();
}

class _FileGroupCardWithThumbnailState
    extends ConsumerState<FileGroupCardWithThumbnail> {
  String? _thumbnailPath;
  bool _isLoadingThumbnail = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (_isLoadingThumbnail) return;

    setState(() {
      _isLoadingThumbnail = true;
    });

    try {
      final thumbnailService = ref.read(videoThumbnailServiceProvider);
      // 使用第一个文件生成缩略图
      final firstFile = widget.group.files.first;
      final thumbnail = await thumbnailService.generateThumbnail(
        firstFile.filePath,
        quality: 75,
        maxWidth: 200,
        maxHeight: 200,
        timeMs: 2000, // 从第2秒截取
      );

      if (mounted) {
        setState(() {
          _thumbnailPath = thumbnail;
          _isLoadingThumbnail = false;
        });
      }
    } catch (e) {
      print('加载缩略图失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingThumbnail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: widget.index > 0 ? 12 : 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧缩略图
          _buildThumbnail(context),
          
          // 右侧信息
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题和文件数量
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.group.files.length} 个文件',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.group.baseName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // 总大小
                  Text(
                    '总大小: ${widget.group.formattedTotalSize}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // 文件列表
                  ...widget.group.files.asMap().entries.map((fileEntry) {
                    final fileIndex = fileEntry.key;
                    final file = fileEntry.value;
                    return Padding(
                      padding: EdgeInsets.only(top: fileIndex > 0 ? 4 : 0),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Center(
                              child: Text(
                                '${fileIndex + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              file.fileName,
                              style: const TextStyle(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return Container(
      width: 120,
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
        child: _buildThumbnailContent(context),
      ),
    );
  }

  Widget _buildThumbnailContent(BuildContext context) {
    if (_isLoadingThumbnail) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '生成中...',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_thumbnailPath != null && File(_thumbnailPath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(_thumbnailPath!),
            fit: BoxFit.cover,
          ),
          // 视频图标叠加层
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      );
    }

    // 默认占位符
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.video_library,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
        const SizedBox(height: 8),
        Text(
          '无缩略图',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
