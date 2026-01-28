import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../core/models/actor.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/utils/loading_state.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../providers/actor_providers.dart';
import '../../../../shared/widgets/expandable_text.dart';
import '../../../../shared/widgets/media_card.dart';
import '../../../../shared/widgets/preview_image_list.dart';
import '../../../media/providers/plugin_providers.dart';

class ActorDetailScreen extends ConsumerWidget {
  final String actorId;

  const ActorDetailScreen({super.key, required this.actorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actorDetail = ref.watch(actorDetailProvider(actorId));

    return Scaffold(
      body: actorDetail.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('演员不存在'));
          }
          return _buildContent(context, ref, detail);
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
                onPressed: () =>
                    ref.read(actorDetailProvider(actorId).notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, Actor detail) {
    // 获取演员的媒体作品列表
    final mediaListAsync = ref.watch(actorMediaListProvider(actorId));
    
    return CustomScrollView(
      slivers: [
        // 固定的顶部 AppBar + Hero header（集成头图）
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.black.withOpacity(0.3),
          expandedHeight: () {
            final w = MediaQuery.of(context).size.width;
            if (w <= 768) return 400.0;
            if (w <= 1024) return 550.0;
            if (w <= 1600) return 625.0;
            return 800.0;
          }(),
          flexibleSpace: Stack(
            children: [
              // 背景图 - 自适应高度
              _buildHeroImage(detail),
              
              // 顶部渐变遮罩 - 确保顶部区域可见
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            detail.name,
            style: const TextStyle(
              shadows: [
                Shadow(blurRadius: 8, color: Colors.black),
                Shadow(blurRadius: 4, color: Colors.black),
              ],
            ),
          ),
          iconTheme: const IconThemeData(
            shadows: [
              Shadow(blurRadius: 8, color: Colors.black),
              Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
          actions: [
            // 插件UI注入点 - actor_detail_appbar（根据后端已安装插件过滤）
            ...PluginUIRegistry()
                .getButtonsFiltered('actor_detail_appbar', ref.watch(installedPluginIdsProvider))
                .map((button) => PluginUIRenderer.renderButton(
                      button,
                      context,
                      contextData: {'actor_id': detail.id.toString()},
                    )),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditDialog(context, ref, detail),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(context, ref, detail);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('删除', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        
        // Actor info
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 基本信息
                if (detail.nationality != null || detail.birthDate != null)
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (detail.nationality != null)
                        Chip(
                          avatar: const Icon(Icons.flag, size: 18),
                          label: Text(detail.nationality!),
                        ),
                      if (detail.birthDate != null)
                        Chip(
                          avatar: const Icon(Icons.cake, size: 18),
                          label: Text(detail.birthDate!),
                        ),
                    ],
                  ),
                // 简介
                if (detail.biography != null &&
                    detail.biography!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '简介',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ExpandableText(
                    text: detail.biography!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 4,
                  ),
                ],
                // 写真展示
                if (detail.photoUrls != null && detail.photoUrls!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildPhotoGallerySection(context, detail),
                ],
                // 作品列表标题
                const SizedBox(height: 24),
                mediaListAsync.when(
                  data: (mediaList) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '作品 (${mediaList.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  loading: () => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '作品',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  error: (_, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '作品',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 作品网格 - 通过检测图片比例自动选择布局
        mediaListAsync.when(
          data: (mediaList) {
            if (mediaList.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('暂无作品', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              );
            }
            
            // 通过检测图片比例来判断使用哪个网格
            return FutureBuilder<bool>(
              future: _detectIsLandscape(mediaList),
              builder: (context, snapshot) {
                final isLandscape = snapshot.data ?? false;
                
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: isLandscape
                      ? SliverMasonryMediaGridLandscape(items: mediaList)
                      : SliverMasonryMediaGridPortrait(items: mediaList),
                );
              },
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('加载作品失败: $error', style: const TextStyle(color: Colors.red)),
              ),
            ),
          ),
        ),
        // 底部间距
        const SliverToBoxAdapter(
          child: SizedBox(height: 32),
        ),
      ],
    );
  }

  Widget _buildHeroImage(Actor detail) {
    // 优先使用 backdrop_url（横幅背景），如果没有则使用第一张写真
    final imageUrl = detail.backdropUrl ?? 
                     (detail.photoUrls != null && detail.photoUrls!.isNotEmpty 
                       ? detail.photoUrls!.first 
                       : null);
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: getProxiedImageUrl(imageUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => Container(
          width: double.infinity,
          height: 400,
          color: Colors.grey[300],
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPhotoGallerySection(BuildContext context, Actor detail) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 使用 photoUrls 列表
    final photoUrls = detail.photoUrls ?? <String>[];
    
    if (photoUrls.isEmpty) return const SizedBox.shrink();
    
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
                '写真',
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
                  '${photoUrls.length}',
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
          imageUrls: photoUrls,
          onImageTap: (index) => _showFullScreenImage(context, photoUrls, index),
        ),
      ],
    );
  }

  void _showFullScreenImage(BuildContext context, List<String> imageUrls, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullScreenImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: 280, // 占位符使用固定高度
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: 100,
        color: Colors.grey[500],
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, Actor detail) {
    showDialog(
      context: context,
      builder: (context) => EditActorDialog(actor: detail),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Actor detail) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除演员 "${detail.name}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(actorListProvider.notifier).deleteActor(detail.id);
              if (context.mounted) {
                context.go('/actors');
                context.showSuccess('演员 "${detail.name}" 已删除');
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 检测图片列表是否主要为横图
  Future<bool> _detectIsLandscape(List<MediaItem> items) async {
    if (items.isEmpty) return false;
    
    // 采样前5张图片来判断
    final sampleSize = items.length > 5 ? 5 : items.length;
    int landscapeCount = 0;
    int portraitCount = 0;
    
    for (int i = 0; i < sampleSize; i++) {
      final media = items[i];
      if (media.posterUrl == null || media.posterUrl!.isEmpty) continue;
      
      try {
        final proxiedUrl = getProxiedImageUrl(media.posterUrl);
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
        
        final info = await completer.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () => throw TimeoutException('Image load timeout'),
        );
        
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        final ratio = width / height;
        
        // 判断横竖：比例 >= 1.0 为横图，< 1.0 为竖图
        if (ratio >= 1.0) {
          landscapeCount++;
        } else {
          portraitCount++;
        }
      } catch (e) {
        // 忽略单张图片的错误，继续检测下一张
        continue;
      }
    }
    
    // 横图数量更多则返回 true
    return landscapeCount > portraitCount;
  }
}

/// 全屏图片查看器
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.imageUrls.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: getProxiedImageUrl(widget.imageUrls[index]),
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white, size: 64),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 编辑演员对话框
class EditActorDialog extends ConsumerStatefulWidget {
  final Actor actor;

  const EditActorDialog({super.key, required this.actor});

  @override
  ConsumerState<EditActorDialog> createState() => _EditActorDialogState();
}

class _EditActorDialogState extends ConsumerState<EditActorDialog> with LoadingStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _avatarUrlController;
  late final TextEditingController _photoUrlsController;  // 支持多个URL
  late final TextEditingController _posterUrlController;
  late final TextEditingController _backdropUrlController;
  late final TextEditingController _biographyController;
  late final TextEditingController _birthDateController;
  late final TextEditingController _nationalityController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.actor.name);
    _avatarUrlController = TextEditingController(text: widget.actor.avatarUrl ?? '');
    // 将 photoUrls 列表转换为换行分隔的字符串
    _photoUrlsController = TextEditingController(
      text: widget.actor.photoUrls?.join('\n') ?? '',
    );
    _posterUrlController = TextEditingController(text: widget.actor.posterUrl ?? '');
    _backdropUrlController = TextEditingController(text: widget.actor.backdropUrl ?? '');
    _biographyController = TextEditingController(text: widget.actor.biography ?? '');
    _birthDateController = TextEditingController(text: widget.actor.birthDate ?? '');
    _nationalityController = TextEditingController(text: widget.actor.nationality ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _avatarUrlController.dispose();
    _photoUrlsController.dispose();
    _posterUrlController.dispose();
    _backdropUrlController.dispose();
    _biographyController.dispose();
    _birthDateController.dispose();
    _nationalityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑演员'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '姓名 *',
                  ),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入姓名';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _avatarUrlController,
                  decoration: const InputDecoration(
                    labelText: '头像URL',
                    hintText: '圆形小头像（用于媒体详情页）',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _photoUrlsController,
                  decoration: const InputDecoration(
                    labelText: '写真URLs',
                    hintText: '多个URL用换行分隔',
                  ),
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _posterUrlController,
                  decoration: const InputDecoration(
                    labelText: '封面URL',
                    hintText: '竖版海报（用于演员列表卡片）',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _backdropUrlController,
                  decoration: const InputDecoration(
                    labelText: '背景图URL',
                    hintText: '横版大图（用于详情页背景）',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nationalityController,
                  decoration: const InputDecoration(
                    labelText: '国籍',
                  ),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _birthDateController,
                  decoration: const InputDecoration(
                    labelText: '出生日期',
                    hintText: 'YYYY-MM-DD',
                  ),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _biographyController,
                  decoration: const InputDecoration(
                    labelText: '简介',
                  ),
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // 辅助函数：处理字符串字段，去除空白后如果为空则返回 null
    String? processTextField(String text) {
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    // 解析多个写真URL（按换行分隔）
    final photoUrlsText = _photoUrlsController.text.trim();
    final photoUrls = photoUrlsText.isEmpty
        ? null
        : photoUrlsText
            .split('\n')
            .map((url) => url.trim())
            .where((url) => url.isNotEmpty)
            .toList();
    
    // 如果列表为空，设置为 null
    final finalPhotoUrls = (photoUrls == null || photoUrls.isEmpty) ? null : photoUrls;

    final updatedActor = widget.actor.copyWith(
      name: _nameController.text.trim(),
      avatarUrl: processTextField(_avatarUrlController.text),
      photoUrls: finalPhotoUrls,
      posterUrl: processTextField(_posterUrlController.text),
      backdropUrl: processTextField(_backdropUrlController.text),
      biography: processTextField(_biographyController.text),
      birthDate: processTextField(_birthDateController.text),
      nationality: processTextField(_nationalityController.text),
      updatedAt: DateTime.now(),
    );

    await executeWithLoading(
      () => ref.read(actorMutationProvider.notifier).updateActor(updatedActor),
      onSuccess: (actor) {
        if (mounted && actor != null) {
          Navigator.pop(context);
          context.showSuccess('演员信息已更新');
        }
      },
    );
  }
}
