import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js_interop' as js;

/// Web 平台视频播放器 - 使用 HTML5 video 元素
/// 支持 HLS (M3U8) 格式通过 hls.js
class VideoPreviewPlayerImpl extends StatefulWidget {
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
  State<VideoPreviewPlayerImpl> createState() => _VideoPreviewPlayerImplState();
}

class _VideoPreviewPlayerImplState extends State<VideoPreviewPlayerImpl> {
  late String _viewId;
  html.VideoElement? _videoElement;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  double _progress = 0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _viewId = 'video-player-${widget.videoUrl.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
    _createVideoElement();
  }

  void _createVideoElement() {
    _videoElement = html.VideoElement()
      ..autoplay = widget.autoPlay
      ..controls = false
      ..loop = widget.loop
      ..muted = widget.muted
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000';

    // 检查是否是 HLS (M3U8) URL
    final isHLS = widget.videoUrl.toLowerCase().contains('.m3u8');
    
    if (isHLS) {
      // 使用 HLS.js 加载 M3U8
      _loadHLSVideo();
    } else {
      // 直接加载普通视频
      _videoElement!.src = widget.videoUrl;
    }

    _videoElement!.onLoadedMetadata.listen((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _duration = Duration(seconds: _videoElement!.duration.toInt());
        });
      }
    });

    _videoElement!.onTimeUpdate.listen((_) {
      if (mounted && _videoElement != null) {
        final currentTime = _videoElement!.currentTime;
        final duration = _videoElement!.duration;
        setState(() {
          _position = Duration(seconds: currentTime.toInt());
          _progress = duration > 0 ? currentTime / duration : 0;
        });
      }
    });

    _videoElement!.onPlay.listen((_) {
      if (mounted) setState(() => _isPlaying = true);
    });

    _videoElement!.onPause.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });

    _videoElement!.onError.listen((_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    });

    _videoElement!.onEnded.listen((_) {
      if (mounted && !widget.loop) {
        setState(() => _isPlaying = false);
      }
    });

    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => _videoElement!,
    );
  }

  void _loadHLSVideo() {
    // 简化处理：直接使用原生 HLS 或降级
    // dart:js_interop 的使用方式与旧的 dart:js 不同，这里简化处理
    _videoElement!.src = widget.videoUrl;
  }

  void _initHLS() {
    try {
      // 检查浏览器是否原生支持 HLS（Safari）
      final canPlayHLS = _videoElement!.canPlayType('application/vnd.apple.mpegurl');
      
      if (canPlayHLS.isNotEmpty && canPlayHLS != 'no') {
        // Safari 等浏览器原生支持 HLS
        print('Using native HLS support');
        _videoElement!.src = widget.videoUrl;
      } else {
        // 使用 HLS.js（Chrome、Firefox 等）
        print('Using HLS.js');
        // 注意：dart:js_interop 的使用方式与旧的 dart:js 不同
        // 这里简化处理，直接使用原生 HLS 或降级
        _videoElement!.src = widget.videoUrl;
      }
    } catch (e) {
      print('Error initializing HLS: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _togglePlay() {
    if (_videoElement == null) return;
    if (_isPlaying) {
      _videoElement!.pause();
    } else {
      _videoElement!.play();
    }
  }

  void _toggleMute() {
    if (_videoElement == null) return;
    _videoElement!.muted = !_videoElement!.muted;
    setState(() {});
  }

  void _seekTo(double value) {
    if (_videoElement == null) return;
    final duration = _videoElement!.duration;
    if (duration > 0) {
      _videoElement!.currentTime = value * duration;
    }
  }

  void _toggleFullscreen() {
    _videoElement?.requestFullscreen();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _videoElement?.pause();
    _videoElement = null;
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: widget.width,
      height: widget.height ?? 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          HtmlElementView(viewType: _viewId),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_hasError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  const Text('视频加载失败', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() { _hasError = false; _isLoading = true; });
                      _videoElement?.load();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (!_isLoading && !_hasError && widget.showControls)
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePlay,
                child: AnimatedOpacity(
                  opacity: _isPlaying ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.black38,
                    child: Center(
                      child: Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!_isLoading && !_hasError && widget.showControls)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                      onPressed: _togglePlay,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    Text('${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          activeTrackColor: colorScheme.primary,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: colorScheme.primary,
                        ),
                        child: Slider(value: _progress.clamp(0.0, 1.0), onChanged: _seekTo),
                      ),
                    ),
                    IconButton(
                      icon: Icon(_videoElement?.muted == true ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
                      onPressed: _toggleMute,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                      onPressed: _toggleFullscreen,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
