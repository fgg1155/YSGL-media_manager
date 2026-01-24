import 'package:flutter/material.dart';

// Platform-specific conditional imports
// Web uses HTML5 video, native platforms use video_player
import 'video_preview_player_native.dart'
    if (dart.library.html) 'video_preview_player_web.dart';

/// Video preview player - cross-platform unified interface
/// 
/// Platform implementations:
/// - Web: HTML5 video element
/// - Android/iOS: video_player package
/// - Windows/macOS/Linux: video_player + video_player_win
class VideoPreviewPlayer extends StatelessWidget {
  final String videoUrl;
  final double? width;
  final double? height;
  final bool autoPlay;
  final bool showControls;
  final bool loop;
  final bool muted;

  const VideoPreviewPlayer({
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
    // Conditional import automatically selects the correct platform implementation
    return VideoPreviewPlayerImpl(
      videoUrl: videoUrl,
      width: width,
      height: height,
      autoPlay: autoPlay,
      showControls: showControls,
      loop: loop,
      muted: muted,
    );
  }
}
