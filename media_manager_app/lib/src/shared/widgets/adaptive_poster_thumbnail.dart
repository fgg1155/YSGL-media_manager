import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/utils/image_proxy.dart';

/// 自适应封面缩略图 - 根据图片比例智能调整尺寸
class AdaptivePosterThumbnail extends StatefulWidget {
  final String posterUrl;

  const AdaptivePosterThumbnail({super.key, required this.posterUrl});

  @override
  State<AdaptivePosterThumbnail> createState() => _AdaptivePosterThumbnailState();
}

class _AdaptivePosterThumbnailState extends State<AdaptivePosterThumbnail> {
  double _aspectRatio = 2 / 3; // 默认竖版海报比例
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _detectImageAspectRatio();
  }

  @override
  void didUpdateWidget(AdaptivePosterThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 posterUrl 发生变化时，重新检测图片比例
    if (oldWidget.posterUrl != widget.posterUrl) {
      setState(() {
        _aspectRatio = 2 / 3;
        _isLoading = true;
      });
      _detectImageAspectRatio();
    }
  }

  Future<void> _detectImageAspectRatio() async {
    try {
      final proxiedUrl = getProxiedImageUrl(widget.posterUrl);
      final imageProvider = CachedNetworkImageProvider(proxiedUrl);
      final stream = imageProvider.resolve(const ImageConfiguration());
      
      stream.addListener(
        ImageStreamListener((info, _) {
          if (mounted) {
            final width = info.image.width.toDouble();
            final height = info.image.height.toDouble();
            setState(() {
              _aspectRatio = width / height;
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
    // DORCELCLUB 响应式尺寸：封面图（cover）
    final screenWidth = MediaQuery.of(context).size.width;
    
    double coverHeight;
    if (screenWidth <= 360) {
      coverHeight = 360;
    } else if (screenWidth <= 480) {
      coverHeight = 480;
    } else if (screenWidth <= 576) {
      coverHeight = 576;
    } else if (screenWidth <= 768) {
      coverHeight = 768;
    } else {
      coverHeight = 202; // 桌面端固定 202px
    }
    
    final calculatedWidth = coverHeight * _aspectRatio;

    return Container(
      width: calculatedWidth,
      height: coverHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: getProxiedImageUrl(widget.posterUrl),
          fit: BoxFit.contain,  // 完整显示图片，不裁剪
          fadeInDuration: const Duration(milliseconds: 200),
          fadeOutDuration: const Duration(milliseconds: 100),
          placeholder: (context, url) => Container(
            color: Colors.grey[800],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey[800],
            child: const Icon(Icons.movie, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
