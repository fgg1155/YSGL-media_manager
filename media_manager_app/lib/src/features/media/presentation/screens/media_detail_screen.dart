// Media detail screen - shows detailed information about a media item
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/models/media_file.dart';
import '../../../../core/models/collection.dart';
import '../../../../core/models/actor.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../providers/media_providers.dart';
import '../../providers/plugin_providers.dart';
import '../../../collection/providers/collection_providers.dart';
import '../../../actors/providers/actor_providers.dart';
import '../../../../shared/widgets/video_preview_player.dart';
import '../../../../shared/widgets/expandable_text.dart';
import '../../../../shared/widgets/preview_image_list.dart';
import '../../../../shared/widgets/glassmorphism_container.dart';
import '../widgets/media_hero_header.dart';

class MediaDetailScreen extends ConsumerStatefulWidget {
  final String mediaId;

  const MediaDetailScreen({super.key, required this.mediaId});

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  final ScrollController _previewScrollController = ScrollController();
  List<MediaFile>? _mediaFiles; // 多分段文件列表
  bool _loadingFiles = false;

  @override
  void dispose() {
    _previewScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 加载媒体文件列表
    _loadMediaFiles();
  }

  Future<void> _loadMediaFiles() async {
    if (_loadingFiles) return;
    
    setState(() {
      _loadingFiles = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.getMediaFiles(widget.mediaId);
      if (mounted) {
        setState(() {
          _mediaFiles = response.files;
          _loadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingFiles = false;
        });
      }
      // 静默失败，使用向后兼容的单文件模式
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaDetail = ref.watch(mediaDetailProvider(widget.mediaId));
    final isInCollection = ref.watch(isInCollectionProvider(widget.mediaId));
    final collection = ref.watch(getCollectionForMediaProvider(widget.mediaId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: true, // 允许返回
        child: Scaffold(
          extendBodyBehindAppBar: true, // 让内容延伸到 AppBar 后面
          body: mediaDetail.when(
            data: (media) {
              if (media == null) {
                return const Center(child: Text('未找到媒体'));
              }
              return _buildContent(context, media, isInCollection, collection);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('错误: $error'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(mediaDetailProvider(widget.mediaId)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    MediaItem media,
    bool isInCollection,
    Collection? collection,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 检查插件可用性
    final pluginsAvailable = ref.watch(pluginsAvailableProvider);
    
    return CustomScrollView(
      slivers: [
        // 固定顶部操作栏 + Hero header（DORCELCLUB 风格）
        SliverAppBar(
          pinned: true,
          floating: false,
          backgroundColor: Colors.black.withOpacity(0.3),
          expandedHeight: () {
            final w = MediaQuery.of(context).size.width;
            if (w <= 768) return 400.0;
            if (w <= 1024) return 550.0;
            if (w <= 1600) return 625.0;
            return 800.0;
          }(),
          flexibleSpace: MediaHeroHeader(media: media),
          iconTheme: const IconThemeData(
            color: Colors.white,
            shadows: [
              Shadow(blurRadius: 8, color: Colors.black),
              Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
          actions: [
            // 插件UI注入点 - media_detail_appbar（根据后端已安装插件过滤）
            ...PluginUIRegistry()
                .getButtonsFiltered('media_detail_appbar', ref.watch(installedPluginIdsProvider))
                .map((button) => PluginUIRenderer.renderButton(
                      button,
                      context,
                      contextData: {
                        'media_id': media.id,
                        'code': media.code,
                        'title': media.title,
                        'series': media.series,
                        'release_date': media.releaseDate,
                        // 不包含 media_type，只使用对话框中用户选择的 content_type
                      },
                    )),
            
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              onPressed: () => context.push('/media/${media.id}/edit'),
              tooltip: '编辑',
            ),
            IconButton(
              icon: Icon(
                isInCollection ? Icons.bookmark : Icons.bookmark_border,
                color: isInCollection ? colorScheme.primary : Colors.white,
              ),
              onPressed: () => _toggleCollection(ref, media, isInCollection),
              tooltip: isInCollection ? '取消收藏' : '添加收藏',
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: () => _shareMedia(context, media),
              tooltip: '分享',
            ),
          ],
        ),
        

        // Content
        SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick info bar
                  _buildQuickInfoBar(context, media),
                  
                  // Main content with padding
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Collection status card (if in collection)
                        if (isInCollection && collection != null) ...[
                          _buildCollectionCard(context, ref, collection),
                          const SizedBox(height: 16),
                        ],

                        // Overview section
                        if (media.overview != null && media.overview!.isNotEmpty) ...[
                          _buildSectionCard(
                            context,
                            icon: Icons.description_outlined,
                            title: '简介',
                            child: ExpandableText(
                              text: media.overview!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.6,
                                color: colorScheme.onSurface.withOpacity(0.8),
                              ),
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Preview images section (prominent display)
                        if (media.previewUrls.isNotEmpty) ...[
                          _buildPreviewImagesSection(context, media),
                          const SizedBox(height: 16),
                        ],

                        // Preview videos section
                        // 如果有本地文件，不显示预览视频
                        if (media.previewVideoUrls.isNotEmpty && 
                            (_mediaFiles == null || _mediaFiles!.isEmpty)) ...[
                          _buildPreviewVideosSection(context, media),
                          const SizedBox(height: 16),
                        ],

                        // Resources section (play + download + 刮削)
                        // 如果有资源或有可用插件，就显示这个部分
                        if (media.playLinks.isNotEmpty || 
                            media.downloadLinks.isNotEmpty || 
                            media.localFilePath != null ||
                            ref.watch(pluginsAvailableProvider)) ...[
                          _buildResourcesSection(context, media),
                          const SizedBox(height: 16),
                        ],

                        // Cast & Crew section
                        if (media.cast.isNotEmpty || media.crew.isNotEmpty) ...[
                          _buildCastCrewSection(context, media),
                          const SizedBox(height: 16),
                        ],

                        // Additional info section
                        _buildInfoSection(context, media),
                        
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ],
    );
  }

  // DORCELCLUB 风格的 Hero Header
  Widget _buildHeroHeader(BuildContext context, MediaItem media) {
    return MediaHeroHeader(media: media);
  }

  IconData _getMediaTypeIcon(MediaType type) {
    switch (type) {
      case MediaType.movie:
        return Icons.movie_outlined;
      case MediaType.scene:
        return Icons.theaters_outlined;
      case MediaType.documentary:
        return Icons.video_library_outlined;
      case MediaType.anime:
        return Icons.animation_outlined;
      case MediaType.censored:
        return Icons.lock_outlined;
      case MediaType.uncensored:
        return Icons.lock_open_outlined;
    }
  }

  Widget _buildQuickInfoBar(BuildContext context, MediaItem media) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return GlassmorphismContainer(
      borderRadius: BorderRadius.zero,
      border: Border(
        bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Media type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _getMediaTypeLabel(media.mediaType),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Release Date or Year
          if (media.releaseDate != null || media.year != null) ...[
            Icon(Icons.calendar_today_outlined, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              media.releaseDate ?? media.yearString,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
          ],
          
          // Rating with vote count
          if (media.rating != null) ...[
            const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
            const SizedBox(width: 4),
            Text(
              media.rating!.toStringAsFixed(1),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (media.voteCount != null && media.voteCount! > 0) ...[
              Text(
                ' (${media.voteCount})',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: 12),
          ],
          
          // Runtime
          if (media.runtime != null) ...[
            Icon(Icons.schedule_outlined, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(media.runtimeString, style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
          
          const Spacer(),
          
          // Genres (compact)
          if (media.genres.isNotEmpty)
            Flexible(
              child: Text(
                media.genres.take(2).join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  String _getMediaTypeLabel(MediaType type) {
    switch (type) {
      case MediaType.movie:
        return '电影';
      case MediaType.scene:
        return '场景';
      case MediaType.documentary:
        return '纪录片';
      case MediaType.anime:
        return '动漫';
      case MediaType.censored:
        return '有码';
      case MediaType.uncensored:
        return '无码';
    }
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return GlassmorphismCard(
      icon: icon,
      title: title,
      trailing: trailing,
      child: child,
    );
  }

  Widget _buildCollectionCard(BuildContext context, WidgetRef ref, Collection collection) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return GlassmorphismContainer(
      opacity: 0.5,
      color: colorScheme.primaryContainer,
      border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.bookmark, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已收藏',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        collection.statusDisplay,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (collection.personalRating != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        collection.ratingDisplay,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showStatusSheet(context, ref, collection),
            child: const Text('更新'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewImagesSection(BuildContext context, MediaItem media) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '预览图',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${media.previewUrls.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        PreviewImageList(
          imageUrls: media.previewUrls.map((url) => getProxiedImageUrl(url)).toList(),
          onImageTap: (index) => _showFullScreenImage(context, media.previewUrls, index),
        ),
      ],
    );
  }

  Widget _buildPreviewVideosSection(BuildContext context, MediaItem media) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 使用 StatefulWidget 来管理当前选择的清晰度
    return _PreviewVideoPlayer(
      videoUrls: media.previewVideoUrlList,  // 提取 URL 列表
      videoData: media.previewVideoUrls,     // 传递原始数据用于提取清晰度标签
      theme: theme,
      colorScheme: colorScheme,
      onCopyLink: (url) => _copyToClipboard(context, url, '链接已复制'),
    );
  }

  Widget _buildResourcesSection(BuildContext context, MediaItem media) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 检查后端模式
    final backendMode = ref.read(backendModeManagerProvider);
    
    // 判断是否有多个文件
    final hasMultipleFiles = _mediaFiles != null && _mediaFiles!.length > 1;
    final hasSingleFile = media.localFilePath != null || (_mediaFiles != null && _mediaFiles!.length == 1);
    
    // PC 模式下，检查是否真的有视频文件
    // 使用 _mediaFiles（从 API 获取）而不是 media.files（可能为空）
    final hasStreamableVideo = backendMode.isPcMode && 
                                _mediaFiles != null && 
                                _mediaFiles!.isNotEmpty;
    
    final hasAnyFiles = hasSingleFile || hasMultipleFiles || hasStreamableVideo;
    
    return _buildSectionCard(
      context,
      icon: Icons.folder_outlined,
      title: '资源',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 插件UI注入点 - media_detail_resources（根据后端已安装插件过滤）
          ...PluginUIRegistry()
              .getButtonsFiltered('media_detail_resources', ref.watch(installedPluginIdsProvider))
              .map((button) => PluginUIRenderer.renderButton(
                    button,
                    context,
                    contextData: {
                      'media_id': media.id,
                      'code': media.code,
                      'title': media.title,
                      'series': media.series,
                      'release_date': media.releaseDate,
                    },
                  )),
          

        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 如果没有任何资源，显示提示
          if (media.playLinks.isEmpty && media.downloadLinks.isEmpty && !hasAnyFiles) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '暂无资源，点击右上角"刮削磁力"按钮添加',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          
          // Play links - 只显示在线播放链接，本地文件通过下面的文件列表播放
          if (media.playLinks.isNotEmpty) ...[
            Text(
              '在线播放',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 在线播放链接
                ...media.playLinks.map((link) => FilledButton.tonalIcon(
                  onPressed: () => _openUrl(context, link.url),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text(
                    link.quality != null ? '${link.name} (${link.quality})' : link.name,
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                )).toList(),
              ],
            ),
            const SizedBox(height: 16),
          ],
          
          // 显示文件信息（单文件或多文件）- 带播放按钮
          if (hasSingleFile) ...[
            Text(
              '本地文件',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _buildSingleFileInfo(context, media, colorScheme),
          ] else if (hasMultipleFiles) ...[
            Text(
              '本地文件',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _buildFilesList(context, _mediaFiles!, colorScheme),
          ] else if (hasStreamableVideo) ...[
            Text(
              '视频文件',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _buildFilesList(context, media.files, colorScheme),
          ],
          
          // Download links
          if (media.downloadLinks.isNotEmpty) ...[
            if (media.playLinks.isNotEmpty || hasSingleFile || hasMultipleFiles || hasStreamableVideo) const SizedBox(height: 16),
            Text(
              '下载资源',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...media.downloadLinks.asMap().entries.map((entry) {
              final index = entry.key;
              final link = entry.value;
              return Container(
                margin: EdgeInsets.only(top: index > 0 ? 8 : 0),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: _getDownloadIcon(link.linkType),
                  title: Text(link.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    [link.linkTypeDisplay, if (link.size != null) link.size].join(' · '),
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (link.password != null)
                        TextButton.icon(
                          onPressed: () => _copyToClipboard(context, link.password!, '提取码已复制'),
                          icon: const Icon(Icons.key, size: 14),
                          label: Text(link.password!, style: const TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.content_copy, size: 18),
                        onPressed: () => _copyToClipboard(context, link.url, '链接已复制'),
                        tooltip: '复制链接',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  onTap: () => _handleDownloadLink(context, link),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _getSingleFileLabel(MediaItem media) {
    if (_mediaFiles != null && _mediaFiles!.isNotEmpty) {
      final file = _mediaFiles!.first;
      return '本地播放 (${file.formattedSize})';
    } else if (media.fileSize != null) {
      return '本地播放 (${_formatFileSize(media.fileSize!)})';
    }
    return '本地播放';
  }

  Widget _buildSingleFileInfo(BuildContext context, MediaItem media, ColorScheme colorScheme) {
    // 获取单个文件信息
    MediaFile file;
    if (_mediaFiles != null && _mediaFiles!.isNotEmpty) {
      file = _mediaFiles!.first;
    } else {
      // 从 media 对象创建 MediaFile
      file = MediaFile(
        id: '${media.id}_file',
        mediaId: media.id,
        filePath: media.localFilePath!,
        fileSize: media.fileSize ?? 0,
        createdAt: DateTime.now(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文件大小信息
        Row(
          children: [
            Icon(Icons.video_file, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '1 个文件',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              MediaFile.formatFileSize(file.fileSize),
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 缩略图卡片 - 响应式高度
        LayoutBuilder(
          builder: (context, constraints) {
            // 根据容器宽度计算 16:9 比例的高度
            final availableWidth = constraints.maxWidth;
            final height16_9 = availableWidth / (16 / 9);
            
            // 限制高度范围：240px - 720px
            final clampedHeight = height16_9.clamp(240.0, 720.0);
            
            return SizedBox(
              height: clampedHeight,
              child: _buildVideoThumbnailCard(
                context,
                file,
                0,
                colorScheme,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMultiFilePlayButton(BuildContext context, List<MediaFile> files, ColorScheme colorScheme) {
    return PopupMenuButton<MediaFile>(
      onSelected: (file) => _playLocalFile(context, file.filePath),
      itemBuilder: (context) => files.map((file) {
        return PopupMenuItem<MediaFile>(
          value: file,
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      file.formattedSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: FilledButton.icon(
        onPressed: null, // 由 PopupMenuButton 处理
        icon: const Icon(Icons.play_arrow, size: 20),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '本地播放 (${files.length} 个文件)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: Size.zero,
          backgroundColor: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildFilesList(BuildContext context, List<MediaFile> files, ColorScheme colorScheme) {
    // 计算总大小
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.fileSize);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 总大小信息
        Row(
          children: [
            Icon(Icons.video_library, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '${files.length} 个文件',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '总大小: ${MediaFile.formatFileSize(totalSize)}',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 横向滚动的缩略图卡片 - 响应式布局
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final fileCount = files.length;
            
            // 根据屏幕宽度决定每排显示几个（参考场景列表）
            int crossAxisCount;
            if (availableWidth > 1200) {
              crossAxisCount = 4;
            } else if (availableWidth > 900) {
              crossAxisCount = 3;
            } else if (availableWidth > 600) {
              crossAxisCount = 2;
            } else {
              crossAxisCount = 1;
            }
            
            // 如果文件数量少于每排数量，使用文件数量
            final displayCount = fileCount < crossAxisCount ? fileCount : crossAxisCount;
            
            // 计算卡片宽度：(容器宽度 - 间距总和) / 显示数量
            final totalSpacing = (displayCount - 1) * 12.0;
            final cardWidth = (availableWidth - totalSpacing) / displayCount;
            
            // 计算卡片高度：根据宽度按 16:9 比例，限制在 180-360px
            final height16_9 = cardWidth / (16 / 9);
            final cardHeight = height16_9.clamp(180.0, 360.0);
            
            return SizedBox(
              height: cardHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  return Container(
                    width: cardWidth,
                    margin: EdgeInsets.only(right: index < files.length - 1 ? 12 : 0),
                    child: _buildVideoThumbnailCard(
                      context,
                      file,
                      index,
                      colorScheme,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVideoThumbnailCard(
    BuildContext context,
    MediaFile file,
    int index,
    ColorScheme colorScheme,
  ) {
    final streamingService = ref.read(videoStreamingServiceProvider);
    
    // 检查是否是多文件（用于显示序号）
    final isMultiFile = _mediaFiles != null && _mediaFiles!.length > 1;
    
    // 为每个文件生成缩略图 URL
    // 多文件时传递 fileIndex，单文件时使用默认值
    final thumbnailUrl = isMultiFile 
        ? streamingService.getThumbnailUrl(widget.mediaId, fileIndex: index)
        : streamingService.getThumbnailUrl(widget.mediaId);
    
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => _playLocalFile(context, file.filePath),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 缩略图区域
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 缩略图
                  CachedNetworkImage(
                    imageUrl: thumbnailUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.video_file,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // 渐变遮罩
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  // 播放按钮
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  // 文件大小角标
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        MediaFile.formatFileSize(file.fileSize),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // 序号角标（仅多文件时显示）
                  if (isMultiFile)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 文件名区域
            Container(
              padding: const EdgeInsets.all(8),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: Text(
                file.displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCastCrewSection(BuildContext context, MediaItem media) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return _buildSectionCard(
      context,
      icon: Icons.people_outline,
      title: '演职人员',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cast - 使用真实演员数据（带头像）
          _ActorListSection(mediaId: media.id),
          
          // Crew - 点击跳转到演员详情页
          if (media.crew.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '制作团队',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: media.crew.map((person) => ActionChip(
                avatar: CircleAvatar(
                  backgroundColor: colorScheme.secondaryContainer,
                  child: Text(
                    person.name.isNotEmpty ? person.name[0] : '?',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                label: Text('${person.name} · ${person.role}'),
                labelStyle: const TextStyle(fontSize: 12),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onPressed: () => _navigateToActorByName(context, person.name),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, MediaItem media) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 检查是否有任何信息需要显示
    final hasAnyInfo = (media.code != null && media.code!.isNotEmpty) ||
        (media.originalTitle != null && media.originalTitle != media.title) ||
        (media.studio != null && media.studio!.isNotEmpty) ||
        (media.series != null && media.series!.isNotEmpty) ||
        media.language != null ||
        media.country != null ||
        media.status != null ||
        (media.budget != null && media.budget! > 0) ||
        (media.revenue != null && media.revenue! > 0) ||
        media.externalIds.tmdbId != null ||
        media.externalIds.imdbId != null ||
        media.externalIds.omdbId != null ||
        media.genres.isNotEmpty;
    
    if (!hasAnyInfo) {
      return const SizedBox.shrink();
    }
    
    return _buildSectionCard(
      context,
      icon: Icons.info_outline,
      title: '详细信息',
      child: Column(
        children: [
          // 识别码 - 可点击
          if (media.code != null && media.code!.isNotEmpty)
            _buildClickableInfoRow(
              context,
              colorScheme,
              '识别码',
              media.code!,
              onTap: () => _navigateToSearchWithPrefix(context, media.code!),
              showBorder: false,
            ),
          // 原名 - 不可点击
          if (media.originalTitle != null && media.originalTitle != media.title)
            _buildInfoRow(context, colorScheme, '原名', media.originalTitle!, showBorder: false),
          // 制作商 - 跳转到筛选页面
          if (media.studio != null && media.studio!.isNotEmpty)
            _buildClickableInfoRow(
              context,
              colorScheme,
              '制作商',
              media.studio!,
              onTap: () => _navigateToFilterByStudio(context, media.studio!),
              showBorder: false,
            ),
          // 系列 - 跳转到筛选页面
          if (media.series != null && media.series!.isNotEmpty)
            _buildClickableInfoRow(
              context,
              colorScheme,
              '系列',
              media.series!,
              onTap: () => _navigateToFilterBySeries(context, media.series!),
              showBorder: false,
            ),
          // 语言 - 不可点击
          if (media.language != null)
            _buildInfoRow(context, colorScheme, '语言', media.language!, showBorder: false),
          // 国家/地区 - 不可点击
          if (media.country != null)
            _buildInfoRow(context, colorScheme, '国家/地区', media.country!, showBorder: false),
          // 状态 - 不可点击
          if (media.status != null)
            _buildInfoRow(context, colorScheme, '状态', media.status!, showBorder: false),
          // 预算 - 不可点击
          if (media.budget != null && media.budget! > 0)
            _buildInfoRow(context, colorScheme, '预算', _formatNumber(media.budget!), showBorder: false),
          // 票房 - 不可点击
          if (media.revenue != null && media.revenue! > 0)
            _buildInfoRow(context, colorScheme, '票房', _formatNumber(media.revenue!), showBorder: false),
          // External IDs
          if (media.externalIds.tmdbId != null)
            _buildInfoRow(context, colorScheme, 'TMDB ID', media.externalIds.tmdbId.toString(), showBorder: false),
          if (media.externalIds.imdbId != null)
            _buildInfoRow(context, colorScheme, 'IMDB ID', media.externalIds.imdbId!, showBorder: false),
          if (media.externalIds.omdbId != null)
            _buildInfoRow(context, colorScheme, 'OMDB ID', media.externalIds.omdbId!, showBorder: false),
          // 类型 - 可点击的标签
          if (media.genres.isNotEmpty)
            _buildGenresRow(context, colorScheme, media.genres, showBorder: false),
        ],
      ),
    );
  }

  // 普通信息行（不可点击）
  Widget _buildInfoRow(
    BuildContext context,
    ColorScheme colorScheme,
    String label,
    String value, {
    required bool showBorder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // 可点击的信息行
  Widget _buildClickableInfoRow(
    BuildContext context,
    ColorScheme colorScheme,
    String label,
    String value, {
    required VoidCallback onTap,
    required bool showBorder,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: showBorder
              ? Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,  // 使用加粗代替下划线
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 类型行（多个可点击标签）- 跳转到筛选页面
  Widget _buildGenresRow(
    BuildContext context,
    ColorScheme colorScheme,
    List<String> genres, {
    required bool showBorder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '类型',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: genres.map((genre) => InkWell(
                onTap: () => _navigateToFilterByGenre(context, genre),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    genre,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 提取识别码前缀（例如 "SSIS-001" → "SSIS"）
  String _extractCodePrefix(String code) {
    final match = RegExp(r'^([A-Za-z]+)').firstMatch(code);
    return match?.group(1) ?? code;
  }

  // 跳转到搜索页面（搜索识别码前缀）
  void _navigateToSearchWithPrefix(BuildContext context, String code) {
    final prefix = _extractCodePrefix(code);
    context.push('/search?query=$prefix');
  }

  // 跳转到搜索页面（通用）
  void _navigateToSearch(BuildContext context, String query) {
    context.push('/search?query=$query');
  }

  // 跳转到筛选页面（按制作商筛选）
  void _navigateToFilterByStudio(BuildContext context, String studio) {
    // 先设置筛选条件，然后跳转
    ref.read(mediaFiltersProvider.notifier).updateStudio(studio);
    context.push('/filter');
  }

  // 跳转到筛选页面（按系列筛选）
  void _navigateToFilterBySeries(BuildContext context, String series) {
    // 先设置筛选条件，然后跳转
    ref.read(mediaFiltersProvider.notifier).updateSeries(series);
    context.push('/filter');
  }

  // 跳转到筛选页面（按类型/流派筛选）
  void _navigateToFilterByGenre(BuildContext context, String genre) {
    // 先设置筛选条件，然后跳转
    ref.read(mediaFiltersProvider.notifier).updateGenre(genre);
    context.push('/filter');
  }

  // 通过演员名字跳转到演员详情页
  Future<void> _navigateToActorByName(BuildContext context, String actorName) async {
    try {
      // 通过名字搜索演员
      final repository = ref.read(actorRepositoryProvider);
      final actors = await repository.searchActors(actorName);
      
      if (actors.isNotEmpty && context.mounted) {
        // 跳转到第一个匹配的演员详情页
        context.push('/actors/${actors.first.id}');
      } else if (context.mounted) {
        // 如果找不到演员，显示提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未找到演员: $actorName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('查找演员失败: $e')),
        );
      }
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000000) {
      return '\$${(number / 1000000000).toStringAsFixed(1)}B';
    } else if (number >= 1000000) {
      return '\$${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '\$${(number / 1000).toStringAsFixed(1)}K';
    }
    return '\$$number';
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    } else if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '$bytes B';
  }

  Widget _getDownloadIcon(DownloadLinkType type) {
    IconData iconData;
    Color color;
    
    switch (type) {
      case DownloadLinkType.magnet:
        iconData = Icons.link;
        color = Colors.orange;
      case DownloadLinkType.ed2k:
        iconData = Icons.electric_bolt;
        color = Colors.blue;
      case DownloadLinkType.http:
        iconData = Icons.http;
        color = Colors.green;
      case DownloadLinkType.ftp:
        iconData = Icons.folder_shared;
        color = Colors.purple;
      case DownloadLinkType.torrent:
        iconData = Icons.file_download;
        color = Colors.teal;
      case DownloadLinkType.pan:
        iconData = Icons.cloud;
        color = Colors.lightBlue;
      case DownloadLinkType.other:
        iconData = Icons.download;
        color = Colors.grey;
    }
    
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: color, size: 20),
    );
  }

  void _showFullScreenImage(BuildContext context, List<String> urls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageGalleryScreen(
          imageUrls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    // 复制链接到剪贴板，因为 web 平台不支持直接打开外部链接
    Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('链接已复制: $url'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '知道了',
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _playLocalFile(BuildContext context, String filePath) async {
    try {
      // 检查后端模式
      final backendMode = ref.read(backendModeManagerProvider);
      final mediaDetail = await ref.read(mediaDetailProvider(widget.mediaId).future);
      
      // 桌面端（Windows/macOS/Linux）：始终使用系统默认播放器
      // 原因：更好的格式支持（WMV等），正确的时长显示，更好的性能
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('无法打开文件: $filePath'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      
      // 移动端：使用流式 API 播放
      // PC 模式下，移动端始终使用流式 API（如果有文件）
      // 独立模式下，检查是否有本地视频文件
      final shouldUseStreaming = (backendMode.isPcMode && _mediaFiles != null && _mediaFiles!.isNotEmpty) || 
                                 (mediaDetail != null && mediaDetail.files.isNotEmpty);
      
      if (shouldUseStreaming && mediaDetail != null) {
        // 使用流式 API 播放
        final streamingService = ref.read(videoStreamingServiceProvider);
        final streamUrl = streamingService.getVideoStreamUrl(widget.mediaId);
        
        // 在应用内播放（使用 VideoPreviewPlayer）
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.black,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.black87,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              mediaDetail.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    // 视频播放器
                    Expanded(
                      child: VideoPreviewPlayer(
                        videoUrl: streamUrl,
                        autoPlay: true,
                        showControls: true,
                        loop: false,
                        muted: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        // 回退到系统默认播放器（向后兼容）
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('无法打开文件: $filePath'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开文件失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareMedia(BuildContext context, MediaItem media) {
    final text = '${media.title}${media.year != null ? ' (${media.year})' : ''}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleDownloadLink(BuildContext context, DownloadLink link) {
    if (link.linkType == DownloadLinkType.pan && link.password != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(link.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('链接:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              SelectableText(
                link.url,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('提取码: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      link.password!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            FilledButton.tonal(
              onPressed: () {
                _copyToClipboard(context, '${link.url}\n提取码: ${link.password}', '链接和提取码已复制');
                Navigator.pop(context);
              },
              child: const Text('复制全部'),
            ),
          ],
        ),
      );
    } else {
      _copyToClipboard(context, link.url, '链接已复制');
    }
  }

  void _toggleCollection(WidgetRef ref, MediaItem media, bool isInCollection) {
    if (isInCollection) {
      ref.read(collectionListProvider.notifier).removeFromCollection(media.id);
    } else {
      ref.read(collectionListProvider.notifier).addToCollection(media.id);
    }
  }

  void _showStatusSheet(BuildContext context, WidgetRef ref, Collection collection) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _StatusSheet(
        collection: collection,
        onStatusChanged: (status) {
          ref.read(collectionListProvider.notifier).updateStatus(
            collection.mediaId,
            status,
          );
          Navigator.pop(context);
        },
      ),
    );
  }

  /// 生成系列+日期格式的搜索关键词
  /// 格式: dorcelclub.25.01.25
  String? _generateSeriesDateQuery(MediaItem media) {
    if (media.series == null || media.series!.isEmpty || 
        media.releaseDate == null || media.releaseDate!.isEmpty) {
      return null;
    }
    
    try {
      // 解析日期 (格式: "2025-01-25")
      final date = DateTime.parse(media.releaseDate!);
      // 生成格式: dorcelclub.25.01.25
      final year = date.year.toString().substring(2); // 取后两位
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final seriesLower = media.series!.toLowerCase().replaceAll(' ', '');
      return '$seriesLower.$year.$month.$day';
    } catch (e) {
      return null;
    }
  }
}


class _StatusSheet extends StatelessWidget {
  final Collection collection;
  final Function(WatchStatus) onStatusChanged;

  const _StatusSheet({
    required this.collection,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '更新观看状态',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...WatchStatus.values.map((status) {
            final isSelected = status == collection.watchStatus;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(
                  _getStatusIcon(status),
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  _getStatusLabel(status),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? colorScheme.onPrimaryContainer : null,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: colorScheme.primary)
                    : null,
                onTap: () => onStatusChanged(status),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _getStatusIcon(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return Icons.bookmark_outline;
      case WatchStatus.watching:
        return Icons.play_circle_outline;
      case WatchStatus.completed:
        return Icons.check_circle_outline;
      case WatchStatus.onHold:
        return Icons.pause_circle_outline;
      case WatchStatus.dropped:
        return Icons.cancel_outlined;
    }
  }

  String _getStatusLabel(WatchStatus status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return '想看';
      case WatchStatus.watching:
        return '在看';
      case WatchStatus.completed:
        return '看过';
      case WatchStatus.onHold:
        return '暂停';
      case WatchStatus.dropped:
        return '弃剧';
    }
  }
}


/// 全屏图片查看器
class _ImageGalleryScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _ImageGalleryScreen({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<_ImageGalleryScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${_currentIndex + 1} / ${widget.imageUrls.length}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.imageUrls[_currentIndex]));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('图片链接已复制'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            tooltip: '复制图片链接',
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: getProxiedImageUrl(widget.imageUrls[index]),
                    fit: BoxFit.contain,
                    memCacheWidth: 1200,  // 全屏查看器使用较大缓存
                    memCacheHeight: 1800,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, color: Colors.grey, size: 64),
                          SizedBox(height: 8),
                          Text('加载失败', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Bottom indicator
          if (widget.imageUrls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.imageUrls.length,
                  (index) => Container(
                    width: index == _currentIndex ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: index == _currentIndex ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
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

/// 带缩略图的文件项
class _FileItemWithThumbnail extends ConsumerStatefulWidget {
  final MediaFile file;
  final int index;
  final ColorScheme colorScheme;
  final VoidCallback onPlay;

  const _FileItemWithThumbnail({
    super.key,
    required this.file,
    required this.index,
    required this.colorScheme,
    required this.onPlay,
  });

  @override
  ConsumerState<_FileItemWithThumbnail> createState() => _FileItemWithThumbnailState();
}

class _FileItemWithThumbnailState extends ConsumerState<_FileItemWithThumbnail> {
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
      print('=== 开始生成缩略图 ===');
      print('文件路径: ${widget.file.filePath}');
      print('文件是否存在: ${File(widget.file.filePath).existsSync()}');
      
      final thumbnailService = ref.read(videoThumbnailServiceProvider);
      final thumbnail = await thumbnailService.generateThumbnail(
        widget.file.filePath,
        quality: 75,
        maxWidth: 120,
        maxHeight: 80,
        timeMs: 2000,
      );

      print('缩略图路径: $thumbnail');
      print('==================');

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
      margin: EdgeInsets.only(top: widget.index > 0 ? 8 : 0),
      decoration: BoxDecoration(
        color: widget.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧缩略图
          _buildThumbnail(),
          
          // 右侧信息
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: widget.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            '${widget.index + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: widget.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.file.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.file.formattedSize,
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 播放按钮
          IconButton(
            icon: Icon(Icons.play_circle_outline, size: 24, color: widget.colorScheme.primary),
            onPressed: widget.onPlay,
            tooltip: '播放',
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    return Container(
      width: 120,
      height: 80,
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceVariant,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
        child: _buildThumbnailContent(),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (_isLoadingThumbnail) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.colorScheme.primary,
          ),
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
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 14,
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
          Icons.video_file,
          size: 32,
          color: widget.colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ],
    );
  }
}


/// 预览视频播放器组件（支持清晰度切换）
class _PreviewVideoPlayer extends StatefulWidget {
  final List<String> videoUrls;
  final List<dynamic> videoData;  // 原始数据，用于提取清晰度标签
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Function(String) onCopyLink;

  const _PreviewVideoPlayer({
    required this.videoUrls,
    required this.videoData,
    required this.theme,
    required this.colorScheme,
    required this.onCopyLink,
  });

  @override
  State<_PreviewVideoPlayer> createState() => _PreviewVideoPlayerState();
}

class _PreviewVideoPlayerState extends State<_PreviewVideoPlayer> {
  int _currentQualityIndex = 0;

  // 清晰度标签（从数据中提取或推断）
  List<String> get _qualityLabels {
    final labels = <String>[];
    
    for (int i = 0; i < widget.videoData.length; i++) {
      final item = widget.videoData[i];
      if (item is Map<String, dynamic> && item.containsKey('quality')) {
        labels.add(item['quality'] as String);
      } else {
        // 向后兼容：如果没有清晰度信息，使用默认标签
        if (widget.videoUrls.length == 1) {
          labels.add('默认');
        } else if (widget.videoUrls.length == 2) {
          labels.add(i == 0 ? '高清' : '标清');
        } else if (widget.videoUrls.length == 3) {
          labels.add(['高清', '中清', '标清'][i]);
        } else {
          labels.add('清晰度 ${i + 1}');
        }
      }
    }
    
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoUrls.isEmpty) return const SizedBox.shrink();

    final currentUrl = widget.videoUrls[_currentQualityIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.videocam_outlined, size: 20, color: widget.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '预览视频',
                style: widget.theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // 清晰度选择器（如果有多个清晰度）
              if (widget.videoUrls.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: widget.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _qualityLabels.asMap().entries.map((entry) {
                      final index = entry.key;
                      final label = entry.value;
                      final isSelected = index == _currentQualityIndex;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _currentQualityIndex = index;
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? widget.colorScheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected 
                                  ? widget.colorScheme.onPrimary 
                                  : widget.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        // 视频播放器 - 响应式高度
        LayoutBuilder(
          builder: (context, constraints) {
            // 根据容器宽度计算 16:9 比例的高度
            final availableWidth = constraints.maxWidth;
            final height16_9 = availableWidth / (16 / 9);
            
            // 限制高度范围：240px - 720px
            final clampedHeight = height16_9.clamp(240.0, 720.0);
            
            return VideoPreviewPlayer(
              key: ValueKey(currentUrl), // 使用 key 强制重新创建播放器
              videoUrl: currentUrl,
              height: clampedHeight,
              autoPlay: false,
              showControls: true,
              loop: false,
              muted: true,
            );
          },
        ),
        const SizedBox(height: 8),
        // 操作按钮
        Row(
          children: [
            Expanded(
              child: Text(
                _qualityLabels[_currentQualityIndex],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: widget.colorScheme.onSurface,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => widget.onCopyLink(currentUrl),
              icon: const Icon(Icons.content_copy, size: 16),
              label: const Text('复制链接'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


/// 演员列表组件 - 显示真实演员数据（带头像）
class _ActorListSection extends ConsumerWidget {
  final String mediaId;

  const _ActorListSection({required this.mediaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actorsAsync = ref.watch(mediaActorListProvider(mediaId));
    final colorScheme = Theme.of(context).colorScheme;

    return actorsAsync.when(
      data: (actors) {
        if (actors.isEmpty) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '演员',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                cacheExtent: 280,
                itemCount: actors.length,
                itemBuilder: (context, index) {
                  final actor = actors[index];
                  return RepaintBoundary(
                    child: InkWell(
                      onTap: () => context.push('/actors/${actor.id}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 70,
                        margin: EdgeInsets.only(right: index < actors.length - 1 ? 12 : 0),
                        child: Column(
                          children: [
                            // 使用 avatarUrl 显示真实头像
                            _buildAvatar(actor, colorScheme),
                            const SizedBox(height: 4),
                            Text(
                              actor.name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 90,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildAvatar(Actor actor, ColorScheme colorScheme) {
    if (actor.avatarUrl != null && actor.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: colorScheme.surfaceContainerHighest,
        backgroundImage: CachedNetworkImageProvider(
          getProxiedImageUrl(actor.avatarUrl!),
        ),
      );
    }
    
    // 没有头像时显示首字母
    return CircleAvatar(
      radius: 28,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        actor.name.isNotEmpty ? actor.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
