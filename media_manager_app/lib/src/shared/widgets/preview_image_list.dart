import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/utils/image_proxy.dart';

/// 预览图列表组件 - 横向滚动，响应式高度
class PreviewImageList extends StatelessWidget {
  final List<String> imageUrls;
  final Function(int index)? onImageTap;
  final ScrollController? scrollController;

  const PreviewImageList({
    super.key,
    required this.imageUrls,
    this.onImageTap,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final colorScheme = Theme.of(context).colorScheme;
    
    // 响应式高度：手机 160，平板 200，桌面 240（增加高度让图片更清晰）
    final previewHeight = screenWidth < 600 ? 160.0 : (screenWidth < 900 ? 200.0 : 240.0);
    
    return SizedBox(
      height: previewHeight,
      child: ScrollConfiguration(
        // 支持鼠标拖拽滚动（Web/桌面端）
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: Listener(
          // 鼠标滚轮横向滚动
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && scrollController != null) {
              final offset = scrollController!.offset + event.scrollDelta.dy;
              scrollController!.jumpTo(offset.clamp(0.0, scrollController!.position.maxScrollExtent));
            }
          },
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 600, // 预缓存 3 张图片，减少滚动卡顿
            itemCount: imageUrls.length,
            itemBuilder: (context, index) => PreviewImageItem(
              imageUrl: imageUrls[index],
              index: index,
              total: imageUrls.length,
              height: previewHeight,
              onTap: onImageTap != null ? () => onImageTap!(index) : null,
              colorScheme: colorScheme,
            ),
          ),
        ),
      ),
    );
  }
}

/// 预览图单项组件 - 响应式高度，自适应宽度
class PreviewImageItem extends StatelessWidget {
  final String imageUrl;
  final int index;
  final int total;
  final double height;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const PreviewImageItem({
    super.key,
    required this.imageUrl,
    required this.index,
    required this.total,
    required this.height,
    this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          margin: EdgeInsets.only(right: index < total - 1 ? 12 : 0),
          child: Stack(
            children: [
              // 图片
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: getProxiedImageUrl(imageUrl),
                  height: height,
                  fit: BoxFit.cover, // 填充固定高度，宽度自适应
                  memCacheWidth: 400,
                  placeholder: (_, __) => Container(
                    width: height * 1.5, // 加载时的占位宽度（假设 3:2 比例）
                    height: height,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: height * 1.5,
                    height: height,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: colorScheme.onSurfaceVariant,
                      size: height * 0.25,
                    ),
                  ),
                ),
              ),
              // 索引指示器
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${index + 1}/$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
