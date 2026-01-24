import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/media_item.dart';
import '../../core/utils/image_proxy.dart';
import '../../core/providers/app_providers.dart';

/// 封面比例类型
enum CoverAspectRatio {
  portrait,   // 竖版 (2:3)
  landscape,  // 横版 (16:9)
  square,     // 方形 (1:1)
}

/// 媒体卡片 - 支持自适应封面比例
class MediaCard extends ConsumerStatefulWidget {
  final MediaItem media;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showRating;
  final bool showYear;
  final CoverAspectRatio? forceAspectRatio;

  const MediaCard({
    super.key,
    required this.media,
    this.onTap,
    this.onLongPress,
    this.showRating = true,
    this.showYear = true,
    this.forceAspectRatio,
  });

  @override
  ConsumerState<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends ConsumerState<MediaCard> {
  bool _isHovering = false;
  Player? _player;
  VideoController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  void _disposeVideoController() {
    _player?.pause();
    _player?.dispose();
    _player = null;
    _videoController = null;
    _isVideoInitialized = false;
    _isVideoPlaying = false;
  }

  Future<void> _initializeAndPlayVideo() async {
    final coverVideoUrl = widget.media.coverVideoUrl;
    
    // 如果没有封面视频，直接返回
    if (coverVideoUrl == null || coverVideoUrl.isEmpty) {
      return;
    }

    // 如果已经在播放，不重复初始化
    if (_isVideoPlaying) {
      return;
    }

    try {
      // 释放旧的控制器
      _disposeVideoController();

      // 创建新的播放器
      _player = Player();
      _videoController = VideoController(_player!);

      // 打开视频
      await _player!.open(Media(coverVideoUrl));

      if (mounted && _isHovering) {
        setState(() {
          _isVideoInitialized = true;
        });

        // 设置循环播放和静音
        await _player!.setPlaylistMode(PlaylistMode.loop);
        await _player!.setVolume(0.0);
        
        // 开始播放
        await _player!.play();
        
        if (mounted) {
          setState(() {
            _isVideoPlaying = true;
          });
        }
      }
    } catch (e) {
      // 视频加载失败，保持显示图片
      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
          _isVideoPlaying = false;
        });
      }
    }
  }

  void _stopVideo() {
    if (_player != null) {
      _player!.pause();
      setState(() {
        _isVideoPlaying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(  // 隔离重绘区域，提升滚动性能
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _isHovering = true);
          // 延迟300ms后开始播放视频，避免快速划过时触发
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_isHovering && mounted) {
              _initializeAndPlayVideo();
            }
          });
        },
        onExit: (_) {
          setState(() => _isHovering = false);
          _stopVideo();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isHovering
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
          ),
          child: Card(
            clipBehavior: Clip.hardEdge, // 裁剪溢出内容，防止遮挡复选框
            elevation: 0, // 使用外层阴影，这里不需要
            child: InkWell(
              onTap: widget.onTap ?? () => context.push('/media/${widget.media.id}'),
              onLongPress: widget.onLongPress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 封面图片区域 - 带hover效果（亮度提升 + 轻微放大，限制在卡片内）
                  Expanded(
                    child: ClipRect(
                      child: Stack(
                        clipBehavior: Clip.hardEdge, // 裁剪溢出
                        fit: StackFit.expand,
                        children: [
                          // 图片带缩放和亮度动画
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            transform: Matrix4.identity()..scale(_isHovering ? 1.05 : 1.0), // 轻微放大5%
                            transformAlignment: Alignment.center,
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                Colors.white.withOpacity(_isHovering ? 0.15 : 0.0), // Hover时提升亮度
                                BlendMode.plus,
                              ),
                              child: _buildPosterImage(),
                            ),
                          ),
                          _buildMediaTypeBadge(),
                        ],
                      ),
                    ),
                  ),
                  // 信息区域（封面下方）
                  _buildInfoSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterImage() {
    // 使用 Stack 叠加图片和视频
    return Stack(
      fit: StackFit.expand,
      children: [
        // 底层：封面图片（始终显示）
        if (widget.media.posterUrl != null && widget.media.posterUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: getProxiedImageUrl(widget.media.posterUrl),
            fit: BoxFit.cover,
            memCacheWidth: 400,
            memCacheHeight: 600,
            maxHeightDiskCache: 800,
            maxWidthDiskCache: 533,
            fadeInDuration: const Duration(milliseconds: 200),
            fadeOutDuration: const Duration(milliseconds: 100),
            placeholder: (_, __) => _buildLoadingPlaceholder(),
            errorWidget: (_, __, ___) => _buildPlaceholder(),
          )
        else
          _buildPlaceholder(),
        
        // 顶层：封面视频（hover 时显示）
        if (_isVideoInitialized && _isVideoPlaying && _videoController != null)
          AnimatedOpacity(
            opacity: _isVideoPlaying ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Video(
              controller: _videoController!,
              controls: NoVideoControls,
            ),
          ),
      ],
    );
  }

  Widget _buildPosterImage_OLD() {
    // 优先使用视频缩略图（如果有视频文件）
    final hasVideoFiles = widget.media.files.isNotEmpty;
    
    if (hasVideoFiles) {
      final streamingService = ref.watch(videoStreamingServiceProvider);
      final thumbnailUrl = streamingService.getThumbnailUrl(widget.media.id);
      
      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        fit: BoxFit.cover,
        memCacheWidth: 400,
        memCacheHeight: 600,
        maxHeightDiskCache: 800,
        maxWidthDiskCache: 533,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (_, __) => _buildLoadingPlaceholder(),
        errorWidget: (_, __, ___) {
          // 如果缩略图加载失败，回退到 posterUrl
          if (widget.media.posterUrl != null) {
            return CachedNetworkImage(
              imageUrl: getProxiedImageUrl(widget.media.posterUrl),
              fit: BoxFit.cover,
              memCacheWidth: 400,
              memCacheHeight: 600,
              placeholder: (_, __) => _buildLoadingPlaceholder(),
              errorWidget: (_, __, ___) => _buildPlaceholder(),
            );
          }
          return _buildPlaceholder();
        },
      );
    }
    
    // 没有视频文件时使用 posterUrl
    if (widget.media.posterUrl != null) {
      final imageUrl = getProxiedImageUrl(widget.media.posterUrl);
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        memCacheWidth: 400,
        memCacheHeight: 600,
        maxHeightDiskCache: 800,
        maxWidthDiskCache: 533,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (_, __) => _buildLoadingPlaceholder(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    
    return _buildPlaceholder();
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey[700]!, Colors.grey[900]!],
        ),
      ),
      child: Center(
        child: Icon(_getMediaTypeIcon(widget.media.mediaType), size: 48, color: Colors.grey[500]),
      ),
    );
  }

  /// 信息区域（封面下方）
  Widget _buildInfoSection(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600; // 手机端使用紧凑模式
    
    return Container(
      padding: EdgeInsets.all(isCompact ? 4 : 6), // 减少padding
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 识别码（如果存在）
          if (widget.media.code != null && widget.media.code!.isNotEmpty) ...[
            Text(
              widget.media.code!,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: isCompact ? 9 : 10,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: isCompact ? 1 : 2),
          ],
          // 标题
          Text(
            widget.media.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: isCompact ? 11 : 12,
              height: 1.2,
            ),
            maxLines: 1, // 只显示1行标题
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isCompact ? 2 : 3),
          // 年份和评分
          Row(
            children: [
              if (widget.showYear && widget.media.year != null) ...[
                Icon(
                  Icons.calendar_today,
                  size: isCompact ? 9 : 10,
                  color: theme.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 3),
                Text(
                  widget.media.yearString,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: isCompact ? 9 : 10,
                  ),
                ),
              ],
              if (widget.showYear && widget.media.year != null && widget.showRating && widget.media.rating != null)
                SizedBox(width: isCompact ? 6 : 8),
              if (widget.showRating && widget.media.rating != null) ...[
                Icon(Icons.star, size: isCompact ? 9 : 10, color: Colors.amber),
                const SizedBox(width: 3),
                Text(
                  widget.media.rating!.toStringAsFixed(1),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: isCompact ? 9 : 10,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTypeBadge() {
    return Positioned(
      top: 6, left: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _getMediaTypeColor(widget.media.mediaType),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _getMediaTypeLabel(widget.media.mediaType),
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Color _getMediaTypeColor(MediaType type) {
    switch (type) {
      case MediaType.movie: return Colors.blue.withOpacity(0.85);
      case MediaType.scene: return Colors.purple.withOpacity(0.85);
      case MediaType.anime: return Colors.orange.withOpacity(0.85);
      case MediaType.documentary: return Colors.green.withOpacity(0.85);
      case MediaType.censored: return Colors.red.withOpacity(0.85);
      case MediaType.uncensored: return Colors.pink.withOpacity(0.85);
    }
  }

  String _getMediaTypeLabel(MediaType type) {
    switch (type) {
      case MediaType.movie: return '电影';
      case MediaType.scene: return '场景';
      case MediaType.anime: return '动漫';
      case MediaType.documentary: return '纪录片';
      case MediaType.censored: return '有码';
      case MediaType.uncensored: return '无码';
    }
  }

  IconData _getMediaTypeIcon(MediaType type) {
    switch (type) {
      case MediaType.movie: return Icons.movie;
      case MediaType.scene: return Icons.videocam;
      case MediaType.anime: return Icons.animation;
      case MediaType.documentary: return Icons.nature_people;
      case MediaType.censored: return Icons.lock;
      case MediaType.uncensored: return Icons.lock_open;
    }
  }
}


/// 紧凑型媒体卡片（列表视图）
class MediaCardCompact extends ConsumerWidget {
  final MediaItem media;
  final VoidCallback? onTap;
  final Widget? trailing;

  const MediaCardCompact({
    super.key,
    required this.media,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(  // 隔离重绘区域
      child: Card(
        child: ListTile(
          onTap: onTap ?? () => context.push('/media/${media.id}'),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 50,
              height: 75,
              child: media.posterUrl != null
                  ? CachedNetworkImage(
                      imageUrl: getProxiedImageUrl(media.posterUrl),
                      fit: BoxFit.cover,
                      memCacheWidth: 100,
                      memCacheHeight: 150,
                      placeholder: (_, __) => Container(color: Colors.grey[300]),
                      errorWidget: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 识别码（如果存在）
              if (media.code != null && media.code!.isNotEmpty)
                Text(
                  media.code!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              // 标题
              Text(
                media.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: media.code != null && media.code!.isNotEmpty 
                      ? FontWeight.w400 
                      : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          subtitle: Row(
            children: [
              if (media.year != null) ...[
                Text(media.yearString),
                const SizedBox(width: 8),
              ],
              if (media.rating != null) ...[
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 2),
                Text(media.rating!.toStringAsFixed(1)),
              ],
            ],
          ),
          trailing: trailing,
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail_OLD(WidgetRef ref) {
    final streamingService = ref.watch(videoStreamingServiceProvider);
    final thumbnailUrl = streamingService.getThumbnailUrl(media.id);
    
    return CachedNetworkImage(
      imageUrl: thumbnailUrl,
      fit: BoxFit.cover,
      memCacheWidth: 100,
      memCacheHeight: 150,
      placeholder: (_, __) => Container(color: Colors.grey[300]),
      errorWidget: (_, __, ___) {
        // 回退到 posterUrl
        if (media.posterUrl != null) {
          return CachedNetworkImage(
            imageUrl: getProxiedImageUrl(media.posterUrl),
            fit: BoxFit.cover,
            memCacheWidth: 100,
            memCacheHeight: 150,
            placeholder: (_, __) => Container(color: Colors.grey[300]),
            errorWidget: (_, __, ___) => _buildPlaceholder(),
          );
        }
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(Icons.movie, size: 24, color: Colors.grey[500]),
    );
  }
}

/// 瀑布流媒体网格 - 竖图版本（电影、有码等）
class MasonryMediaGridPortrait extends StatelessWidget {
  final List<MediaItem> items;
  final bool isLoading;
  final VoidCallback? onLoadMore;
  final Widget? emptyWidget;
  final ScrollController? scrollController;

  const MasonryMediaGridPortrait({
    super.key,
    required this.items,
    this.isLoading = false,
    this.onLoadMore,
    this.emptyWidget,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !isLoading) {
      return emptyWidget ?? const Center(child: Text('暂无媒体'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 200 &&
            onLoadMore != null) {
          onLoadMore!();
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = _getCrossAxisCount(constraints.maxWidth);
          
          return MasonryGridView.count(
            controller: scrollController,
            padding: const EdgeInsets.all(8),
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            itemCount: items.length + (isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return const Center(child: CircularProgressIndicator());
              }
              return _MasonryMediaCardPortrait(media: items[index]);
            },
          );
        },
      ),
    );
  }

  int _getCrossAxisCount(double width) {
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
  }
}

/// 瀑布流媒体网格 - 横图版本（场景、无码等）
class MasonryMediaGridLandscape extends StatelessWidget {
  final List<MediaItem> items;
  final bool isLoading;
  final VoidCallback? onLoadMore;
  final Widget? emptyWidget;
  final ScrollController? scrollController;

  const MasonryMediaGridLandscape({
    super.key,
    required this.items,
    this.isLoading = false,
    this.onLoadMore,
    this.emptyWidget,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !isLoading) {
      return emptyWidget ?? const Center(child: Text('暂无媒体'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 200 &&
            onLoadMore != null) {
          onLoadMore!();
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = _getCrossAxisCount(constraints.maxWidth);
          
          return MasonryGridView.count(
            controller: scrollController,
            padding: const EdgeInsets.all(8),
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            itemCount: items.length + (isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return const Center(child: CircularProgressIndicator());
              }
              return _MasonryMediaCardLandscape(media: items[index]);
            },
          );
        },
      ),
    );
  }

  int _getCrossAxisCount(double width) {
    // 横图需要更少的列数
    if (width > 1200) return 4;
    if (width > 900) return 3;
    if (width > 600) return 2;
    return 1;
  }
}

/// 瀑布流媒体网格 - 兼容旧版本（自动选择）
class MasonryMediaGrid extends StatelessWidget {
  final List<MediaItem> items;
  final bool isLoading;
  final VoidCallback? onLoadMore;
  final Widget? emptyWidget;
  final ScrollController? scrollController;

  const MasonryMediaGrid({
    super.key,
    required this.items,
    this.isLoading = false,
    this.onLoadMore,
    this.emptyWidget,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // 默认使用竖图网格
    return MasonryMediaGridPortrait(
      items: items,
      isLoading: isLoading,
      onLoadMore: onLoadMore,
      emptyWidget: emptyWidget,
      scrollController: scrollController,
    );
  }
}

// 全局缓存图片比例，避免重复检测
final Map<String, double> _aspectRatioCache = {};

/// 清除图片比例缓存
/// 在刷新列表时调用，确保新数据能正确显示
void clearAspectRatioCache() {
  _aspectRatioCache.clear();
}

/// 瀑布流卡片 - 竖图版本（自适应高度）
class _MasonryMediaCardPortrait extends StatefulWidget {
  final MediaItem media;

  const _MasonryMediaCardPortrait({
    required this.media,
  }) : super(key: const ValueKey('portrait'));

  @override
  State<_MasonryMediaCardPortrait> createState() => _MasonryMediaCardPortraitState();
}

class _MasonryMediaCardPortraitState extends State<_MasonryMediaCardPortrait> {
  double? _aspectRatio; // null 表示还未检测到

  @override
  void initState() {
    super.initState();
    _detectImageAspectRatio();
  }

  @override
  void didUpdateWidget(_MasonryMediaCardPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 posterUrl 变化了，重新检测图片比例
    if (oldWidget.media.posterUrl != widget.media.posterUrl) {
      _detectImageAspectRatio();
    }
  }

  Future<void> _detectImageAspectRatio() async {
    final posterUrl = widget.media.posterUrl;
    
    if (posterUrl == null) {
      if (mounted) {
        setState(() => _aspectRatio = 2 / 3);
      }
      return;
    }
    
    // 检查缓存
    if (_aspectRatioCache.containsKey(posterUrl)) {
      if (mounted) {
        setState(() => _aspectRatio = _aspectRatioCache[posterUrl]!);
      }
      return;
    }
    
    try {
      final proxiedUrl = getProxiedImageUrl(posterUrl);
      final imageProvider = CachedNetworkImageProvider(proxiedUrl);
      final completer = Completer<ImageInfo>();
      final stream = imageProvider.resolve(const ImageConfiguration());
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(info);
          }
          stream.removeListener(listener);
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          stream.removeListener(listener);
        },
      );
      
      stream.addListener(listener);
      
      final info = await completer.future;
      final width = info.image.width.toDouble();
      final height = info.image.height.toDouble();
      final ratio = width / height;
      
      // 缓存比例
      _aspectRatioCache[posterUrl] = ratio;
      
      if (mounted) {
        setState(() {
          _aspectRatio = ratio;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aspectRatio = 2 / 3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果还没检测到比例，使用默认比例
    final imageRatio = _aspectRatio ?? 2 / 3;
    
    // 计算卡片整体比例：图片比例 + 底部信息区域高度（约60px）
    // 假设卡片宽度为 200px，则高度 = 200/imageRatio + 60
    // 整体比例 = 200 / (200/imageRatio + 60) = imageRatio / (1 + 60*imageRatio/200)
    // 简化：假设信息区域占图片高度的 0.2 倍
    final cardRatio = imageRatio / (1 + 0.2);
    
    return AspectRatio(
      aspectRatio: cardRatio,
      child: MediaCard(media: widget.media),
    );
  }
}

/// 瀑布流卡片 - 横图版本（自适应高度）
class _MasonryMediaCardLandscape extends StatefulWidget {
  final MediaItem media;

  const _MasonryMediaCardLandscape({
    required this.media,
  }) : super(key: const ValueKey('landscape'));

  @override
  State<_MasonryMediaCardLandscape> createState() => _MasonryMediaCardLandscapeState();
}

class _MasonryMediaCardLandscapeState extends State<_MasonryMediaCardLandscape> {
  double? _aspectRatio; // null 表示还未检测到

  @override
  void initState() {
    super.initState();
    _detectImageAspectRatio();
  }

  @override
  void didUpdateWidget(_MasonryMediaCardLandscape oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 posterUrl 变化了，重新检测图片比例
    if (oldWidget.media.posterUrl != widget.media.posterUrl) {
      _detectImageAspectRatio();
    }
  }

  Future<void> _detectImageAspectRatio() async {
    final posterUrl = widget.media.posterUrl;
    
    if (posterUrl == null) {
      if (mounted) {
        setState(() => _aspectRatio = 16 / 10);
      }
      return;
    }
    
    // 检查缓存
    if (_aspectRatioCache.containsKey(posterUrl)) {
      if (mounted) {
        setState(() => _aspectRatio = _aspectRatioCache[posterUrl]!);
      }
      return;
    }
    
    try {
      final proxiedUrl = getProxiedImageUrl(posterUrl);
      final imageProvider = CachedNetworkImageProvider(proxiedUrl);
      final completer = Completer<ImageInfo>();
      final stream = imageProvider.resolve(const ImageConfiguration());
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(info);
          }
          stream.removeListener(listener);
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          stream.removeListener(listener);
        },
      );
      
      stream.addListener(listener);
      
      final info = await completer.future;
      final width = info.image.width.toDouble();
      final height = info.image.height.toDouble();
      final ratio = width / height;
      
      // 缓存比例
      _aspectRatioCache[posterUrl] = ratio;
      
      if (mounted) {
        setState(() {
          _aspectRatio = ratio;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aspectRatio = 16 / 10);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果还没检测到比例，使用默认比例
    final imageRatio = _aspectRatio ?? 16 / 10;
    
    // 计算卡片整体比例：图片比例 + 底部信息区域
    // 横图的信息区域相对更小，约占图片高度的 0.15 倍
    final cardRatio = imageRatio / (1 + 0.15);
    
    return AspectRatio(
      aspectRatio: cardRatio,
      child: MediaCard(media: widget.media),
    );
  }
}

/// 传统固定比例网格（保留兼容）
class MediaGrid extends StatelessWidget {
  final List<MediaItem> items;
  final bool isLoading;
  final VoidCallback? onLoadMore;
  final Widget? emptyWidget;

  const MediaGrid({
    super.key,
    required this.items,
    this.isLoading = false,
    this.onLoadMore,
    this.emptyWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !isLoading) {
      return emptyWidget ?? const Center(child: Text('暂无媒体'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 200 &&
            onLoadMore != null) {
          onLoadMore!();
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = _getCrossAxisCount(width);
          final isCompact = width < 600;
          final aspectRatio = isCompact ? 0.55 : 0.54;
          
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: aspectRatio, // 响应式比例
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length + (isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return const Center(child: CircularProgressIndicator());
              }
              return MediaCard(media: items[index]);
            },
          );
        },
      ),
    );
  }

  int _getCrossAxisCount(double width) {
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
  }
}

/// Sliver版本的瀑布流网格 - 竖图版本（用于CustomScrollView）
class SliverMasonryMediaGridPortrait extends StatelessWidget {
  final List<MediaItem> items;
  final bool Function(String)? isSelected;
  final void Function(String)? onToggleSelection;

  const SliverMasonryMediaGridPortrait({
    super.key,
    required this.items,
    this.isSelected,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: _getCrossAxisCount(MediaQuery.of(context).size.width),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = isSelected?.call(item.id) ?? false;
          
          if (isSelected != null && onToggleSelection != null) {
            return _SelectableMasonryMediaCardPortrait(
              media: item,
              isSelected: selected,
              onToggle: () => onToggleSelection!(item.id),
            );
          }
          
          return _MasonryMediaCardPortrait(media: item);
        },
      ),
    );
  }

  int _getCrossAxisCount(double width) {
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
  }
}

/// Sliver版本的瀑布流网格 - 横图版本（用于CustomScrollView）
class SliverMasonryMediaGridLandscape extends StatelessWidget {
  final List<MediaItem> items;
  final bool Function(String)? isSelected;
  final void Function(String)? onToggleSelection;

  const SliverMasonryMediaGridLandscape({
    super.key,
    required this.items,
    this.isSelected,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: _getCrossAxisCount(MediaQuery.of(context).size.width),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = isSelected?.call(item.id) ?? false;
          
          if (isSelected != null && onToggleSelection != null) {
            return _SelectableMasonryMediaCardLandscape(
              media: item,
              isSelected: selected,
              onToggle: () => onToggleSelection!(item.id),
            );
          }
          
          return _MasonryMediaCardLandscape(media: item);
        },
      ),
    );
  }

  int _getCrossAxisCount(double width) {
    // 横图需要更少的列数
    if (width > 1200) return 4;
    if (width > 900) return 3;
    if (width > 600) return 2;
    return 1;
  }
}

/// Sliver版本的瀑布流网格 - 兼容旧版本（默认竖图）
class SliverMasonryMediaGrid extends StatelessWidget {
  final List<MediaItem> items;
  final bool Function(String)? isSelected;
  final void Function(String)? onToggleSelection;

  const SliverMasonryMediaGrid({
    super.key,
    required this.items,
    this.isSelected,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    // 默认使用竖图版本
    return SliverMasonryMediaGridPortrait(
      items: items,
      isSelected: isSelected,
      onToggleSelection: onToggleSelection,
    );
  }
}


/// 可选择的瀑布流卡片 - 竖图版本（自适应）
class _SelectableMasonryMediaCardPortrait extends StatefulWidget {
  final MediaItem media;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectableMasonryMediaCardPortrait({
    required this.media,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_SelectableMasonryMediaCardPortrait> createState() => _SelectableMasonryMediaCardPortraitState();
}

class _SelectableMasonryMediaCardPortraitState extends State<_SelectableMasonryMediaCardPortrait> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _detectImageAspectRatio();
  }

  @override
  void didUpdateWidget(_SelectableMasonryMediaCardPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 posterUrl 变化了，重新检测图片比例
    if (oldWidget.media.posterUrl != widget.media.posterUrl) {
      _detectImageAspectRatio();
    }
  }

  Future<void> _detectImageAspectRatio() async {
    final posterUrl = widget.media.posterUrl;
    
    if (posterUrl == null) {
      if (mounted) {
        setState(() => _aspectRatio = 2 / 3);
      }
      return;
    }
    
    // 检查缓存
    if (_aspectRatioCache.containsKey(posterUrl)) {
      if (mounted) {
        setState(() => _aspectRatio = _aspectRatioCache[posterUrl]!);
      }
      return;
    }
    
    try {
      final proxiedUrl = getProxiedImageUrl(posterUrl);
      final imageProvider = CachedNetworkImageProvider(proxiedUrl);
      final completer = Completer<ImageInfo>();
      final stream = imageProvider.resolve(const ImageConfiguration());
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(info);
          }
          stream.removeListener(listener);
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          stream.removeListener(listener);
        },
      );
      
      stream.addListener(listener);
      
      final info = await completer.future;
      final width = info.image.width.toDouble();
      final height = info.image.height.toDouble();
      final ratio = width / height;
      
      // 缓存比例
      _aspectRatioCache[posterUrl] = ratio;
      
      if (mounted) {
        setState(() {
          _aspectRatio = ratio;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aspectRatio = 2 / 3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageRatio = _aspectRatio ?? 2 / 3;
    final cardRatio = imageRatio / (1 + 0.2);
    
    return AspectRatio(
      aspectRatio: cardRatio,
      child: Stack(
        children: [
          MediaCard(
            media: widget.media,
            onTap: widget.onToggle,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: widget.onToggle,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.isSelected 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ),
          if (widget.isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 可选择的瀑布流卡片 - 横图版本（自适应）
class _SelectableMasonryMediaCardLandscape extends StatefulWidget {
  final MediaItem media;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectableMasonryMediaCardLandscape({
    required this.media,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_SelectableMasonryMediaCardLandscape> createState() => _SelectableMasonryMediaCardLandscapeState();
}

class _SelectableMasonryMediaCardLandscapeState extends State<_SelectableMasonryMediaCardLandscape> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _detectImageAspectRatio();
  }

  @override
  void didUpdateWidget(_SelectableMasonryMediaCardLandscape oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 posterUrl 变化了，重新检测图片比例
    if (oldWidget.media.posterUrl != widget.media.posterUrl) {
      _detectImageAspectRatio();
    }
  }

  Future<void> _detectImageAspectRatio() async {
    final posterUrl = widget.media.posterUrl;
    
    if (posterUrl == null) {
      if (mounted) {
        setState(() => _aspectRatio = 16 / 10);
      }
      return;
    }
    
    // 检查缓存
    if (_aspectRatioCache.containsKey(posterUrl)) {
      if (mounted) {
        setState(() => _aspectRatio = _aspectRatioCache[posterUrl]!);
      }
      return;
    }
    
    try {
      final proxiedUrl = getProxiedImageUrl(posterUrl);
      final imageProvider = CachedNetworkImageProvider(proxiedUrl);
      final completer = Completer<ImageInfo>();
      final stream = imageProvider.resolve(const ImageConfiguration());
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(info);
          }
          stream.removeListener(listener);
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          stream.removeListener(listener);
        },
      );
      
      stream.addListener(listener);
      
      final info = await completer.future;
      final width = info.image.width.toDouble();
      final height = info.image.height.toDouble();
      final ratio = width / height;
      
      // 缓存比例
      _aspectRatioCache[posterUrl] = ratio;
      
      if (mounted) {
        setState(() {
          _aspectRatio = ratio;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aspectRatio = 16 / 10);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageRatio = _aspectRatio ?? 16 / 10;
    final cardRatio = imageRatio / (1 + 0.15);
    
    return AspectRatio(
      aspectRatio: cardRatio,
      child: Stack(
        children: [
          MediaCard(
            media: widget.media,
            onTap: widget.onToggle,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: widget.onToggle,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.isSelected 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ),
          if (widget.isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
