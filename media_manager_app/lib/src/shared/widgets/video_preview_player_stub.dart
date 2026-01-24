import 'package:flutter/material.dart';

/// Stub 实现 - 不应该被实际使用
/// 这个文件只是为了满足条件导入的语法要求
class VideoPreviewPlayerImpl extends StatelessWidget {
  final String videoUrl;
  final double? width;
  final double? height;
  final bool autoPlay;
  final bool showControls;
  final bool loop;
  final bool muted;

  const VideoPreviewPlayerImpl({
    super.key,
    required this.videoUrl,
    this.width,
    this.height,
    this.autoPlay = false,
    this.showControls = true,
    this.loop = true,
    this.muted = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height ?? 200,
      color: Colors.red,
      child: const Center(
        child: Text(
          'Video player not supported on this platform',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
