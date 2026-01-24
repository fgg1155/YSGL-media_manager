import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/models/media_item.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../shared/widgets/studio_autocomplete_field.dart';
import '../../../../shared/widgets/series_autocomplete_field.dart';
import '../../../../shared/widgets/media_card.dart';
import '../../providers/media_providers.dart';

class MediaEditScreen extends ConsumerStatefulWidget {
  final String? mediaId; // null表示创建新媒体

  const MediaEditScreen({super.key, this.mediaId});

  @override
  ConsumerState<MediaEditScreen> createState() => _MediaEditScreenState();
}

class _MediaEditScreenState extends ConsumerState<MediaEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _hasChanges = false;

  // 表单控制器
  late TextEditingController _titleController;
  late TextEditingController _originalTitleController;
  late TextEditingController _codeController;
  late TextEditingController _yearController;
  late TextEditingController _overviewController;
  late TextEditingController _ratingController;
  late TextEditingController _runtimeController;
  late TextEditingController _posterUrlController;
  late TextEditingController _backdropUrlController;
  late TextEditingController _releaseDateController;
  late TextEditingController _studioController;
  late TextEditingController _seriesController;
  late TextEditingController _genresController;
  late TextEditingController _previewUrlsController;
  late TextEditingController _previewVideoUrlsController;
  late TextEditingController _coverVideoUrlController;  // 封面视频 URL

  MediaType _mediaType = MediaType.movie;
  MediaItem? _originalMedia;
  
  // 链接列表
  List<PlayLink> _playLinks = [];
  List<DownloadLink> _downloadLinks = [];
  List<Person> _cast = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _originalTitleController = TextEditingController();
    _codeController = TextEditingController();
    _yearController = TextEditingController();
    _overviewController = TextEditingController();
    _ratingController = TextEditingController();
    _runtimeController = TextEditingController();
    _posterUrlController = TextEditingController();
    _backdropUrlController = TextEditingController();
    _releaseDateController = TextEditingController();
    _studioController = TextEditingController();
    _seriesController = TextEditingController();
    _genresController = TextEditingController();
    _previewUrlsController = TextEditingController();
    _previewVideoUrlsController = TextEditingController();
    _coverVideoUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _originalTitleController.dispose();
    _codeController.dispose();
    _yearController.dispose();
    _overviewController.dispose();
    _ratingController.dispose();
    _runtimeController.dispose();
    _posterUrlController.dispose();
    _backdropUrlController.dispose();
    _releaseDateController.dispose();
    _studioController.dispose();
    _seriesController.dispose();
    _genresController.dispose();
    _previewUrlsController.dispose();
    _previewVideoUrlsController.dispose();
    _coverVideoUrlController.dispose();
    super.dispose();
  }

  void _initFormData(MediaItem media) {
    if (_originalMedia != null) return; // 只初始化一次
    _originalMedia = media;
    _titleController.text = media.title;
    _originalTitleController.text = media.originalTitle ?? '';
    _codeController.text = media.code ?? '';
    _yearController.text = media.year?.toString() ?? '';
    _overviewController.text = media.overview ?? '';
    _ratingController.text = media.rating?.toString() ?? '';
    _runtimeController.text = media.runtime?.toString() ?? '';
    _posterUrlController.text = media.posterUrl ?? '';
    _backdropUrlController.text = media.backdropUrl.join('\n');  // 多个背景图用换行分隔
    _releaseDateController.text = media.releaseDate ?? '';
    _studioController.text = media.studio ?? '';
    _seriesController.text = media.series ?? '';
    _genresController.text = media.genres.join(', ');
    _previewUrlsController.text = media.previewUrls.join('\n');
    _previewVideoUrlsController.text = media.previewVideoUrlList.join('\n');  // 使用 previewVideoUrlList 提取 URL
    _coverVideoUrlController.text = media.coverVideoUrl ?? '';
    _mediaType = media.mediaType;
    _playLinks = List.from(media.playLinks);
    _downloadLinks = List.from(media.downloadLinks);
    _cast = List.from(media.cast);
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  // 将 MediaType 枚举转换为数据库期望的字符串格式
  String _getMediaTypeString(MediaType type) {
    switch (type) {
      case MediaType.movie:
        return 'Movie';
      case MediaType.scene:
        return 'Scene';
      case MediaType.documentary:
        return 'Documentary';
      case MediaType.anime:
        return 'Anime';
      case MediaType.censored:
        return 'Censored';
      case MediaType.uncensored:
        return 'Uncensored';
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final repository = ref.read(mediaRepositoryProvider);
      
      // 解析分类
      final genres = _genresController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      
      // 解析预览图 URL（每行一个）
      final previewUrls = _previewUrlsController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      
      // 解析预览视频 URL（每行一个）
      final previewVideoUrls = _previewVideoUrlsController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      
      // 验证并规范化日期格式
      String? releaseDate;
      if (_releaseDateController.text.isNotEmpty) {
        try {
          // 尝试解析日期
          final date = DateTime.parse(_releaseDateController.text);
          // 规范化为 YYYY-MM-DD 格式
          releaseDate = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        } catch (e) {
          // 日期格式无效
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('日期格式无效，请使用 YYYY-MM-DD 格式'), backgroundColor: Colors.red),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      if (widget.mediaId == null) {
        // 创建新媒体
        final now = DateTime.now();
        const uuid = Uuid();
        final newMedia = MediaItem(
          id: uuid.v4(), // 使用 UUID 而不是时间戳
          title: _titleController.text,
          originalTitle: _originalTitleController.text.isEmpty ? null : _originalTitleController.text,
          code: _codeController.text.isEmpty ? null : _codeController.text,
          year: int.tryParse(_yearController.text),
          releaseDate: releaseDate,
          mediaType: _mediaType,
          overview: _overviewController.text.isEmpty ? null : _overviewController.text,
          rating: double.tryParse(_ratingController.text),
          runtime: int.tryParse(_runtimeController.text),
          posterUrl: _posterUrlController.text.isEmpty ? null : _posterUrlController.text,
          backdropUrl: _backdropUrlController.text.isEmpty 
              ? [] 
              : _backdropUrlController.text.split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(),  // 多个背景图用换行分隔
          studio: _studioController.text.isEmpty ? null : _studioController.text,
          series: _seriesController.text.isEmpty ? null : _seriesController.text,
          genres: genres,
          playLinks: _playLinks,
          downloadLinks: _downloadLinks,
          previewUrls: previewUrls,
          previewVideoUrls: previewVideoUrls,
          coverVideoUrl: _coverVideoUrlController.text.isEmpty ? null : _coverVideoUrlController.text,
          cast: _cast,
          crew: const [],
          externalIds: const ExternalIds(),
          createdAt: now,
          updatedAt: now,
        );

        await repository.addMedia(newMedia);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建成功'), backgroundColor: Colors.green),
          );
          // 清除图片缓存
          clearAspectRatioCache();
          ref.invalidate(mediaListProvider);
          context.go('/'); // 返回首页
        }
      } else {
        // 编辑现有媒体
        final currentMedia = ref.read(mediaDetailProvider(widget.mediaId!)).value;
        
        if (currentMedia == null) {
          throw Exception('无法获取当前媒体信息');
        }

        final updatedMedia = currentMedia.copyWith(
          title: _titleController.text,
          originalTitle: _originalTitleController.text.isEmpty ? null : _originalTitleController.text,
          code: _codeController.text.isEmpty ? null : _codeController.text,
          year: int.tryParse(_yearController.text),
          releaseDate: releaseDate,
          mediaType: _mediaType,
          overview: _overviewController.text.isEmpty ? null : _overviewController.text,
          rating: double.tryParse(_ratingController.text),
          runtime: int.tryParse(_runtimeController.text),
          posterUrl: _posterUrlController.text.isEmpty ? null : _posterUrlController.text,
          backdropUrl: _backdropUrlController.text.isEmpty 
              ? [] 
              : _backdropUrlController.text.split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(),  // 多个背景图用换行分隔
          studio: _studioController.text.isEmpty ? null : _studioController.text,
          series: _seriesController.text.isEmpty ? null : _seriesController.text,
          genres: genres,
          playLinks: _playLinks,
          downloadLinks: _downloadLinks,
          previewUrls: previewUrls,
          previewVideoUrls: previewVideoUrls,
          coverVideoUrl: _coverVideoUrlController.text.isEmpty ? null : _coverVideoUrlController.text,
          cast: _cast,
        );

        await repository.updateMedia(updatedMedia);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('保存成功'), backgroundColor: Colors.green),
          );
          // 清除图片缓存
          clearAspectRatioCache();
          ref.invalidate(mediaDetailProvider(widget.mediaId!));
          ref.invalidate(mediaListProvider);
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.mediaId == null ? "创建" : "保存"}失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃更改？'),
        content: const Text('你有未保存的更改，确定要离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // 创建模式：不需要加载数据
    if (widget.mediaId == null) {
      return _buildScaffold(context, null);
    }
    
    // 编辑模式：加载现有数据
    final mediaAsync = ref.watch(mediaDetailProvider(widget.mediaId!));
    
    return mediaAsync.when(
      data: (media) {
        if (media == null) {
          return _buildScaffold(context, null, error: '未找到媒体');
        }
        _initFormData(media);
        return _buildScaffold(context, media);
      },
      loading: () => _buildScaffold(context, null, loading: true),
      error: (e, _) => _buildScaffold(context, null, error: '加载失败: $e'),
    );
  }

  Widget _buildScaffold(BuildContext context, MediaItem? media, {bool loading = false, String? error}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCreateMode = widget.mediaId == null;

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Center(child: Text(error));
    } else {
      // 创建模式或编辑模式都显示表单
      body = _buildForm(context, media);
    }

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isCreateMode ? '创建媒体' : '编辑媒体'),
          actions: [
            if (_hasChanges)
              TextButton(
                onPressed: _isLoading ? null : _saveChanges,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isCreateMode ? '创建' : '保存'),
              ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _buildForm(BuildContext context, MediaItem? media) {
    final isCreateMode = widget.mediaId == null;
    
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 基本信息
          _buildSectionTitle('基本信息'),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '标题 *',
              hintText: '输入媒体标题',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v?.isEmpty == true ? '标题不能为空' : null,
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _originalTitleController,
            decoration: const InputDecoration(
              labelText: '原始标题',
              hintText: '输入原始标题（可选）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: '识别码',
              hintText: '如: ABC-123',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _yearController,
                  decoration: const InputDecoration(
                    labelText: '年份',
                    hintText: '2024',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _releaseDateController,
                  decoration: const InputDecoration(
                    labelText: '发行日期',
                    hintText: '2024-12-26',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<MediaType>(
            value: _mediaType,
            decoration: const InputDecoration(
              labelText: '类型',
              border: OutlineInputBorder(),
            ),
            items: MediaType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(_getMediaTypeLabel(type)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _mediaType = value);
                _onFieldChanged();
              }
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _genresController,
            decoration: const InputDecoration(
              labelText: '分类',
              hintText: '动作, 科幻, 冒险（逗号分隔）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _ratingController,
                  decoration: const InputDecoration(
                    labelText: '评分',
                    hintText: '0-10',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _runtimeController,
                  decoration: const InputDecoration(
                    labelText: '时长（分钟）',
                    hintText: '120',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 简介
          _buildSectionTitle('简介'),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _overviewController,
            decoration: const InputDecoration(
              labelText: '简介',
              hintText: '输入媒体简介...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 5,
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 24),

          // 图片
          _buildSectionTitle('图片'),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _posterUrlController,
            decoration: const InputDecoration(
              labelText: '封面图 URL（竖向 2:3）',
              hintText: '推荐尺寸：500x750px',
              helperText: '用于列表/网格视图显示',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _backdropUrlController,
            decoration: const InputDecoration(
              labelText: '背景图 URL（横向 16:9）',
              hintText: '推荐尺寸：1280x720px',
              helperText: '用于详情页背景显示',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _previewUrlsController,
            decoration: const InputDecoration(
              labelText: '预览图 URL',
              hintText: '每行一个 URL\nhttps://...\nhttps://...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 5,
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _previewVideoUrlsController,
            decoration: const InputDecoration(
              labelText: '预览视频 URL',
              hintText: '每行一个 URL\nhttps://...\nhttps://...',
              helperText: '用于详情页预览播放',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _coverVideoUrlController,
            decoration: const InputDecoration(
              labelText: '封面视频 URL',
              hintText: 'https://...',
              helperText: '用于卡片悬停播放（短视频缩略图）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onFieldChanged(),
          ),
          const SizedBox(height: 24),

          // 其他信息
          _buildSectionTitle('其他信息'),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: StudioAutocompleteField(
                  controller: _studioController,
                  labelText: '制作商',
                  hintText: '输入制作商名称',
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SeriesAutocompleteField(
                  controller: _seriesController,
                  labelText: '系列',
                  hintText: '输入系列名称',
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 演员列表
          _buildSectionTitle('演员'),
          const SizedBox(height: 12),
          _buildCastSection(),
          const SizedBox(height: 24),

          // 播放链接
          _buildSectionTitle('播放链接'),
          const SizedBox(height: 12),
          _buildPlayLinksSection(),
          const SizedBox(height: 24),

          // 下载链接
          _buildSectionTitle('下载链接'),
          const SizedBox(height: 12),
          _buildDownloadLinksSection(),
          const SizedBox(height: 32),

          // 保存按钮
          FilledButton.icon(
            onPressed: _isLoading || !_hasChanges ? null : _saveChanges,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(isCreateMode ? Icons.add : Icons.save),
            label: Text(_isLoading 
                ? (isCreateMode ? '创建中...' : '保存中...') 
                : (isCreateMode ? '创建媒体' : '保存更改')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
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

  // 播放链接编辑区域
  Widget _buildPlayLinksSection() {
    return Column(
      children: [
        ..._playLinks.asMap().entries.map((entry) {
          final index = entry.key;
          final link = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(link.name),
              subtitle: Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editPlayLink(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () => _deletePlayLink(index),
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: _addPlayLink,
          icon: const Icon(Icons.add),
          label: const Text('添加播放链接'),
        ),
      ],
    );
  }

  // 下载链接编辑区域
  Widget _buildDownloadLinksSection() {
    return Column(
      children: [
        ..._downloadLinks.asMap().entries.map((entry) {
          final index = entry.key;
          final link = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(_getDownloadLinkIcon(link.linkType)),
              title: Text(link.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (link.size != null) Text('大小: ${link.size}', style: const TextStyle(fontSize: 12)),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editDownloadLink(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () => _deleteDownloadLink(index),
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: _addDownloadLink,
          icon: const Icon(Icons.add),
          label: const Text('添加下载链接'),
        ),
      ],
    );
  }

  IconData _getDownloadLinkIcon(DownloadLinkType type) {
    switch (type) {
      case DownloadLinkType.magnet:
        return Icons.link;
      case DownloadLinkType.ed2k:
        return Icons.electric_bolt;
      case DownloadLinkType.http:
        return Icons.http;
      case DownloadLinkType.ftp:
        return Icons.folder_shared;
      case DownloadLinkType.torrent:
        return Icons.file_download;
      case DownloadLinkType.pan:
        return Icons.cloud;
      case DownloadLinkType.other:
        return Icons.link;
    }
  }

  void _addPlayLink() async {
    final result = await _showPlayLinkDialog();
    if (result != null) {
      setState(() {
        _playLinks.add(result);
        _hasChanges = true;
      });
    }
  }

  void _editPlayLink(int index) async {
    final result = await _showPlayLinkDialog(link: _playLinks[index]);
    if (result != null) {
      setState(() {
        _playLinks[index] = result;
        _hasChanges = true;
      });
    }
  }

  void _deletePlayLink(int index) {
    setState(() {
      _playLinks.removeAt(index);
      _hasChanges = true;
    });
  }

  void _addDownloadLink() async {
    final result = await _showDownloadLinkDialog();
    if (result != null) {
      setState(() {
        _downloadLinks.add(result);
        _hasChanges = true;
      });
    }
  }

  void _editDownloadLink(int index) async {
    final result = await _showDownloadLinkDialog(link: _downloadLinks[index]);
    if (result != null) {
      setState(() {
        _downloadLinks[index] = result;
        _hasChanges = true;
      });
    }
  }

  void _deleteDownloadLink(int index) {
    setState(() {
      _downloadLinks.removeAt(index);
      _hasChanges = true;
    });
  }

  Future<PlayLink?> _showPlayLinkDialog({PlayLink? link}) async {
    final nameController = TextEditingController(text: link?.name ?? '');
    final urlController = TextEditingController(text: link?.url ?? '');
    final qualityController = TextEditingController(text: link?.quality ?? '');

    return showDialog<PlayLink>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(link == null ? '添加播放链接' : '编辑播放链接'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称 *',
                  hintText: '如: 腾讯视频、爱奇艺',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'URL *',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qualityController,
                decoration: const InputDecoration(
                  labelText: '画质',
                  hintText: '如: 4K、1080P',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isEmpty || urlController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('名称和URL不能为空')),
                );
                return;
              }
              Navigator.pop(context, PlayLink(
                name: nameController.text,
                url: urlController.text,
                quality: qualityController.text.isEmpty ? null : qualityController.text,
              ));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<DownloadLink?> _showDownloadLinkDialog({DownloadLink? link}) async {
    final nameController = TextEditingController(text: link?.name ?? '');
    final urlController = TextEditingController(text: link?.url ?? '');
    final sizeController = TextEditingController(text: link?.size ?? '');
    final passwordController = TextEditingController(text: link?.password ?? '');
    DownloadLinkType linkType = link?.linkType ?? DownloadLinkType.magnet;

    return showDialog<DownloadLink>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(link == null ? '添加下载链接' : '编辑下载链接'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名称 *',
                    hintText: '如: 1080P蓝光、4K HDR',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL *',
                    hintText: 'magnet:?xt=... 或 https://...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DownloadLinkType>(
                  value: linkType,
                  decoration: const InputDecoration(
                    labelText: '链接类型',
                    border: OutlineInputBorder(),
                  ),
                  items: DownloadLinkType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_getDownloadLinkTypeLabel(type)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => linkType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: sizeController,
                  decoration: const InputDecoration(
                    labelText: '文件大小',
                    hintText: '如: 4.5GB',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: '提取码',
                    hintText: '网盘提取码',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.isEmpty || urlController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('名称和URL不能为空')),
                  );
                  return;
                }
                Navigator.pop(context, DownloadLink(
                  name: nameController.text,
                  url: urlController.text,
                  linkType: linkType,
                  size: sizeController.text.isEmpty ? null : sizeController.text,
                  password: passwordController.text.isEmpty ? null : passwordController.text,
                ));
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  String _getDownloadLinkTypeLabel(DownloadLinkType type) {
    switch (type) {
      case DownloadLinkType.magnet:
        return '磁力链接';
      case DownloadLinkType.ed2k:
        return '电驴链接';
      case DownloadLinkType.http:
        return 'HTTP直链';
      case DownloadLinkType.ftp:
        return 'FTP链接';
      case DownloadLinkType.torrent:
        return '种子文件';
      case DownloadLinkType.pan:
        return '网盘链接';
      case DownloadLinkType.other:
        return '其他';
    }
  }

  // 演员列表编辑区域
  Widget _buildCastSection() {
    return Column(
      children: [
        ..._cast.asMap().entries.map((entry) {
          final index = entry.key;
          final person = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(person.name),
              subtitle: Text(
                person.character != null 
                    ? '饰演: ${person.character}' 
                    : person.role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editCast(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () => _deleteCast(index),
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: _addCast,
          icon: const Icon(Icons.add),
          label: const Text('添加演员'),
        ),
      ],
    );
  }

  void _addCast() async {
    final result = await _showCastDialog();
    if (result != null) {
      setState(() {
        _cast.add(result);
        _hasChanges = true;
      });
    }
  }

  void _editCast(int index) async {
    final result = await _showCastDialog(person: _cast[index]);
    if (result != null) {
      setState(() {
        _cast[index] = result;
        _hasChanges = true;
      });
    }
  }

  void _deleteCast(int index) {
    setState(() {
      _cast.removeAt(index);
      _hasChanges = true;
    });
  }

  Future<Person?> _showCastDialog({Person? person}) async {
    final nameController = TextEditingController(text: person?.name ?? '');
    final roleController = TextEditingController(text: person?.role ?? 'Actor');
    final characterController = TextEditingController(text: person?.character ?? '');

    return showDialog<Person>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(person == null ? '添加演员' : '编辑演员'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '演员姓名 *',
                  hintText: '如: 张三',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: characterController,
                decoration: const InputDecoration(
                  labelText: '饰演角色',
                  hintText: '如: 主角、反派',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: roleController,
                decoration: const InputDecoration(
                  labelText: '职位类型',
                  hintText: 'Actor, Director, Producer',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('演员姓名不能为空')),
                );
                return;
              }
              Navigator.pop(context, Person(
                name: nameController.text,
                role: roleController.text.isEmpty ? 'Actor' : roleController.text,
                character: characterController.text.isEmpty ? null : characterController.text,
              ));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
