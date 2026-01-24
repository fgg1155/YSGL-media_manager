import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../shared/widgets/adaptive_poster_thumbnail.dart';

/// DORCELCLUB 风格的媒体详情页头部组件
/// 包含：背景图（全宽自适应高度）、封面缩略图（叠加左下角）、标题（封面旁边）
class MediaHeroHeader extends ConsumerStatefulWidget {
  final MediaItem media;

  const MediaHeroHeader({super.key, required this.media});

  @override
  ConsumerState<MediaHeroHeader> createState() => _MediaHeroHeaderState();
}

class _MediaHeroHeaderState extends ConsumerState<MediaHeroHeader> {
  double _imageAspectRatio = 16 / 9; // 默认横版比例
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _detectImageAspectRatio();
  }

  @override
  void didUpdateWidget(MediaHeroHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 media 发生变化时，重新检测图片比例
    if (oldWidget.media.id != widget.media.id) {
      setState(() {
        _imageAspectRatio = 16 / 9;
        _isLoading = true;
      });
      _detectImageAspectRatio();
    }
  }

  Future<void> _detectImageAspectRatio() async {
    final backendMode = ref.read(backendModeManagerProvider);
    final hasVideoFiles = (backendMode.isPcMode && 
                          widget.media.files.isNotEmpty && 
                          widget.media.files.any((f) => f.filePath.isNotEmpty)) || 
                          widget.media.files.isNotEmpty;
    
    String? imageUrl;
    if (hasVideoFiles) {
      final streamingService = ref.read(videoStreamingServiceProvider);
      imageUrl = streamingService.getThumbnailUrl(widget.media.id);
    } else {
      // 支持多个背景图：优先使用第一张背景图，如果没有则使用封面
      imageUrl = (widget.media.backdropUrl.isNotEmpty 
          ? widget.media.backdropUrl.first 
          : null) ?? widget.media.posterUrl;
    }

    if (imageUrl == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final proxiedUrl = getProxiedImageUrl(imageUrl);
      final imageProvider = CachedNetworkImageProvider(proxiedUrl);
      final stream = imageProvider.resolve(const ImageConfiguration());
      
      stream.addListener(
        ImageStreamListener((info, _) {
          if (mounted) {
            final width = info.image.width.toDouble();
            final height = info.image.height.toDouble();
            setState(() {
              _imageAspectRatio = width / height;
              _isLoading = false;
            });
          }
        }),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendMode = ref.watch(backendModeManagerProvider);
    final hasVideoFiles = (backendMode.isPcMode && 
                          widget.media.files.isNotEmpty && 
                          widget.media.files.any((f) => f.filePath.isNotEmpty)) || 
                          widget.media.files.isNotEmpty;

    // DORCELCLUB 响应式高度：背景图（banner）
    final screenWidth = MediaQuery.of(context).size.width;
    
    double bannerHeight;
    if (screenWidth <= 768) {
      bannerHeight = 400;
    } else if (screenWidth <= 1024) {
      bannerHeight = 550;
    } else if (screenWidth <= 1600) {
      bannerHeight = 625;
    } else {
      bannerHeight = 800;
    }

    // 判断是否有多张背景图（前后封面拼接）
    final hasMultipleBackdrops = widget.media.backdropUrl.length >= 2;
    final singleImageUrl = hasVideoFiles 
        ? null 
        : (widget.media.backdropUrl.isNotEmpty 
            ? widget.media.backdropUrl.first 
            : null) ?? widget.media.posterUrl;

    return SizedBox(
      width: double.infinity,
      height: bannerHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图 - 支持单张或多张拼接
          if (hasVideoFiles)
            _BackgroundVideoThumbnail(mediaId: widget.media.id, fallbackUrl: singleImageUrl)
          else if (hasMultipleBackdrops)
            // 多张背景图：横向拼接显示（前后封面）
            _StitchedBackgroundImages(imageUrls: widget.media.backdropUrl)
          else if (singleImageUrl != null)
            // 单张背景图
            CachedNetworkImage(
              imageUrl: getProxiedImageUrl(singleImageUrl),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              fadeInDuration: const Duration(milliseconds: 300),
              fadeOutDuration: const Duration(milliseconds: 100),
              placeholder: (context, url) => Container(
                color: Colors.transparent,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.transparent,
                child: const Icon(Icons.movie, size: 64, color: Colors.grey),
              ),
            )
          else
            Container(
              color: Colors.transparent,
              child: const Icon(Icons.movie, size: 64, color: Colors.grey),
            ),

          // 渐变遮罩 - 顶部透明，底部有遮罩确保标题清晰
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.6, 0.8, 1.0],
                ),
              ),
            ),
          ),

          // 左下角：封面缩略图 + 标题
          Positioned(
            left: 16,
            bottom: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 封面缩略图 - 固定尺寸，叠加在背景上
                if (widget.media.posterUrl != null)
                  AdaptivePosterThumbnail(posterUrl: widget.media.posterUrl!),
                
                const SizedBox(width: 16),
                
                // 标题
                Expanded(
                  child: Text(
                    widget.media.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(blurRadius: 12, color: Colors.black),
                        Shadow(blurRadius: 24, color: Colors.black),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景视频缩略图组件
class _BackgroundVideoThumbnail extends ConsumerWidget {
  final String mediaId;
  final String? fallbackUrl;

  const _BackgroundVideoThumbnail({
    required this.mediaId,
    this.fallbackUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamingService = ref.watch(videoStreamingServiceProvider);
    final thumbnailUrl = streamingService.getThumbnailUrl(mediaId);
    
    return CachedNetworkImage(
      imageUrl: thumbnailUrl,
      fit: BoxFit.cover,  // 填充满容器
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, url) => Container(
        color: Colors.transparent,
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) {
        // 回退到 backdropUrl 或 posterUrl
        if (fallbackUrl != null) {
          return CachedNetworkImage(
            imageUrl: getProxiedImageUrl(fallbackUrl),
            fit: BoxFit.cover,  // 填充满容器
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: const Duration(milliseconds: 100),
            placeholder: (context, url) => Container(
              color: Colors.transparent,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.transparent,
              child: const Icon(Icons.movie, size: 64, color: Colors.grey),
            ),
          );
        }
        return Container(
          color: Colors.transparent,
          child: const Icon(Icons.movie, size: 64, color: Colors.grey),
        );
      },
    );
  }
}

/// 拼接背景图组件（前后封面横向拼接）
class _StitchedBackgroundImages extends StatelessWidget {
  final List<String> imageUrls;

  const _StitchedBackgroundImages({required this.imageUrls});

  @override
  Widget build(BuildContext context) {
    // 只取前两张图片
    final urls = imageUrls.take(2).toList();
    
    if (urls.isEmpty) {
      return Container(
        color: Colors.transparent,
        child: const Icon(Icons.movie, size: 64, color: Colors.grey),
      );
    }
    
    if (urls.length == 1) {
      // 只有一张图，直接显示
      return CachedNetworkImage(
        imageUrl: getProxiedImageUrl(urls[0]),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => Container(
          color: Colors.transparent,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.transparent,
          child: const Icon(Icons.movie, size: 64, color: Colors.grey),
        ),
      );
    }
    
    // 两张图：横向拼接显示（前图在左，后图在右）
    return Row(
      children: [
        Expanded(
          child: CachedNetworkImage(
            imageUrl: getProxiedImageUrl(urls[0]),
            fit: BoxFit.cover,
            height: double.infinity,
            alignment: Alignment.center,
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: const Duration(milliseconds: 100),
            placeholder: (context, url) => Container(
              color: Colors.transparent,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.transparent,
              child: const Icon(Icons.movie, size: 64, color: Colors.grey),
            ),
          ),
        ),
        Expanded(
          child: CachedNetworkImage(
            imageUrl: getProxiedImageUrl(urls[1]),
            fit: BoxFit.cover,
            height: double.infinity,
            alignment: Alignment.center,
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: const Duration(milliseconds: 100),
            placeholder: (context, url) => Container(
              color: Colors.transparent,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.transparent,
              child: const Icon(Icons.movie, size: 64, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
