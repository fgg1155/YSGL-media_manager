import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;

/// HLS 清晰度选项
class HlsQuality {
  final String label;      // 显示标签，如 "1080p"
  final String url;        // 播放 URL
  final int bandwidth;     // 带宽
  final String resolution; // 分辨率，如 "1920x1080"

  HlsQuality({
    required this.label,
    required this.url,
    required this.bandwidth,
    required this.resolution,
  });
}

/// 原生平台视频播放器 (Android, iOS, Windows, macOS, Linux)
/// 使用 media_kit 包，完全支持 HLS 流媒体
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
  late final Player _player;
  late final VideoController _videoController;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;
  
  // HLS 清晰度相关
  List<HlsQuality> _qualities = [];
  int _currentQualityIndex = -1;
  bool _isLoadingQualities = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _initializePlayer();
  }

  /// 解析 M3U8 主播放列表，提取清晰度选项
  Future<List<HlsQuality>> _parseM3u8Playlist(String m3u8Url) async {
    try {
      print('VideoPlayer: Parsing M3U8 playlist: $m3u8Url');
      
      final response = await http.get(Uri.parse(m3u8Url));
      if (response.statusCode != 200) {
        print('VideoPlayer: Failed to fetch M3U8: ${response.statusCode}');
        return [];
      }
      
      final content = response.body;
      final lines = content.split('\n');
      final qualities = <HlsQuality>[];
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // 查找 #EXT-X-STREAM-INF 标签
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          // 解析属性
          int? bandwidth;
          String? resolution;
          
          // 提取 BANDWIDTH
          final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
          if (bandwidthMatch != null) {
            bandwidth = int.tryParse(bandwidthMatch.group(1)!);
          }
          
          // 提取 RESOLUTION
          final resolutionMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
          if (resolutionMatch != null) {
            resolution = resolutionMatch.group(1);
          }
          
          // 下一行是 URL
          if (i + 1 < lines.length) {
            String url = lines[i + 1].trim();
            
            // 如果是相对路径，转换为绝对路径
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              // 提取基础 URL
              final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/'));
              if (url.startsWith('/')) {
                // 绝对路径
                final uri = Uri.parse(m3u8Url);
                url = '${uri.scheme}://${uri.host}$url';
              } else {
                // 相对路径
                url = '$baseUrl/$url';
              }
            }
            
            // 生成清晰度标签
            String label = 'Auto';
            if (resolution != null) {
              final height = resolution.split('x')[1];
              label = '${height}p';
            } else if (bandwidth != null) {
              // 根据带宽估算清晰度
              if (bandwidth > 5000000) {
                label = '1080p';
              } else if (bandwidth > 3000000) {
                label = '720p';
              } else if (bandwidth > 1500000) {
                label = '540p';
              } else {
                label = '360p';
              }
            }
            
            qualities.add(HlsQuality(
              label: label,
              url: url,
              bandwidth: bandwidth ?? 0,
              resolution: resolution ?? 'unknown',
            ));
          }
        }
      }
      
      // 按带宽排序（从高到低）
      qualities.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      
      print('VideoPlayer: Found ${qualities.length} quality options');
      for (var q in qualities) {
        print('  - ${q.label}: ${q.resolution} (${q.bandwidth} bps)');
      }
      
      return qualities;
    } catch (e) {
      print('VideoPlayer: Error parsing M3U8: $e');
      return [];
    }
  }

  Future<void> _initializePlayer() async {
    try {
      print('VideoPlayer (media_kit): Initializing with URL: ${widget.videoUrl}');
      
      // 检查是否是 HLS (M3U8) URL
      final isHLS = widget.videoUrl.toLowerCase().contains('.m3u8');
      
      String playbackUrl;
      if (isHLS) {
        // HLS 格式通过后端代理播放
        print('VideoPlayer (media_kit): HLS detected, using backend proxy');
        final encodedUrl = Uri.encodeComponent(widget.videoUrl);
        final proxyUrl = 'http://localhost:3000/api/proxy/hls?url=$encodedUrl';
        print('VideoPlayer (media_kit): Proxy URL: $proxyUrl');
        
        // 先解析主播放列表，提取清晰度选项
        setState(() => _isLoadingQualities = true);
        final qualities = await _parseM3u8Playlist(proxyUrl);
        
        if (qualities.isEmpty) {
          // 没有清晰度选项，直接播放主播放列表
          print('VideoPlayer (media_kit): No quality options found, playing main playlist');
          playbackUrl = proxyUrl;
        } else {
          // 有清晰度选项，选择最低清晰度（最后一个）来播放
          print('VideoPlayer (media_kit): Found ${qualities.length} quality options, selecting lowest quality');
          _qualities = qualities;
          _currentQualityIndex = qualities.length - 1; // 选择最低清晰度
          playbackUrl = qualities[_currentQualityIndex].url;
          print('VideoPlayer (media_kit): Selected quality: ${qualities[_currentQualityIndex].label}');
        }
        
        setState(() => _isLoadingQualities = false);
      } else {
        // 普通视频直接播放
        playbackUrl = widget.videoUrl;
      }
      
      // 使用 media_kit 播放
      await _player.open(Media(playbackUrl));
      print('VideoPlayer (media_kit): Media opened successfully');
      
      // 设置循环播放
      if (widget.loop) {
        await _player.setPlaylistMode(PlaylistMode.loop);
      } else {
        // 如果不循环，监听播放完成事件
        _player.stream.completed.listen((completed) {
          if (completed && mounted) {
            // 播放完成后，重置到开头
            _player.seek(Duration.zero);
            _player.pause();
          }
        });
      }
      
      // 设置音量
      if (widget.muted) {
        await _player.setVolume(0);
      }
      
      // 自动播放
      if (widget.autoPlay) {
        await _player.play();
      }
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
      
      print('VideoPlayer (media_kit): Initialized successfully');
    } catch (e, stackTrace) {
      print('VideoPlayer (media_kit): Error: $e');
      print('VideoPlayer (media_kit): Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 切换清晰度
  Future<void> _changeQuality(int qualityIndex) async {
    if (qualityIndex < 0 || qualityIndex >= _qualities.length) {
      return;
    }
    
    // 保存当前播放位置
    final currentPosition = _player.state.position;
    final wasPlaying = _player.state.playing;
    
    print('VideoPlayer: Switching to quality: ${_qualities[qualityIndex].label}');
    
    try {
      // 切换到新的清晰度
      final quality = _qualities[qualityIndex];
      await _player.open(Media(quality.url));
      
      // 恢复播放位置
      await _player.seek(currentPosition);
      
      // 恢复播放状态
      if (wasPlaying) {
        await _player.play();
      }
      
      if (mounted) {
        setState(() {
          _currentQualityIndex = qualityIndex;
        });
      }
      
      print('VideoPlayer: Quality switched successfully');
    } catch (e) {
      print('VideoPlayer: Error switching quality: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = '切换清晰度失败: $e';
        });
      }
    }
  }

  /// 显示清晰度选择菜单（紧凑版）
  void _showQualityMenu() {
    if (_qualities.isEmpty) return;
    
    // 获取按钮位置
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        size.width - 200, // 右对齐
        size.height - 60, // 从底部向上
        size.width,
        size.height,
      ),
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: _qualities.asMap().entries.map((entry) {
        final index = entry.key;
        final quality = entry.value;
        final isSelected = index == _currentQualityIndex;
        
        return PopupMenuItem<int>(
          value: index,
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.blue : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                quality.label,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedIndex) {
      if (selectedIndex != null && selectedIndex != _currentQualityIndex) {
        _changeQuality(selectedIndex);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // Video
          if (_isInitialized)
            Video(
              controller: _videoController,
              controls: widget.showControls ? AdaptiveVideoControls : NoVideoControls,
            ),
          
          // Loading
          if (!_isInitialized && !_hasError)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          
          // Error
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 8),
                    const Text('视频加载失败', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      widget.videoUrl,
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() { 
                          _hasError = false; 
                          _isInitialized = false; 
                          _errorMessage = null; 
                        });
                        _initializePlayer();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          
          // 清晰度选择按钮（放在右下角，全屏按钮左边）
          if (_isInitialized && widget.showControls && _qualities.isNotEmpty)
            Positioned(
              right: 56, // 给全屏按钮留出空间
              bottom: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: _showQualityMenu,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.high_quality, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _currentQualityIndex >= 0 
                              ? _qualities[_currentQualityIndex].label 
                              : 'Auto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
