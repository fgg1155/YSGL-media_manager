import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/models/actor.dart';
import '../../../../core/utils/image_proxy.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/utils/loading_state.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../../providers/actor_providers.dart';
import '../../../media/providers/plugin_providers.dart';

class ActorListScreen extends ConsumerStatefulWidget {
  const ActorListScreen({super.key});

  @override
  ConsumerState<ActorListScreen> createState() => _ActorListScreenState();
}

class _ActorListScreenState extends ConsumerState<ActorListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(actorListProvider.notifier).loadMore();
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个演员吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 显示加载对话框
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text('正在删除 ${_selectedIds.length} 个演员...'),
            ],
          ),
        ),
      );
    }

    // 并发删除所有选中的演员
    final deleteIds = _selectedIds.toList();
    final results = await Future.wait(
      deleteIds.map((id) => ref.read(actorListProvider.notifier).deleteActor(id)),
      eagerError: false,
    );

    // 关闭加载对话框
    if (mounted) {
      Navigator.pop(context);
      
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      
      context.showSuccess('已删除 ${deleteIds.length} 个演员');
    }
  }

  @override
  Widget build(BuildContext context) {
    final actorList = ref.watch(actorListProvider);
    final currentRoute = GoRouterState.of(context).uri.toString();
    final isOnActorListPage = currentRoute == '/actors';

    return PopScope(
      canPop: !isOnActorListPage, // 只在演员列表页时禁止直接返回
      onPopInvoked: (didPop) {
        // 只在演员列表页时拦截返回，其他情况允许正常返回
        if (!isOnActorListPage) return;
        // 左滑无反应，用户应该使用底部导航栏切换页面
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索演员...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(actorListProvider.notifier).search(null);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) {
                ref.read(actorListProvider.notifier).search(
                      value.isEmpty ? null : value,
                    );
              },
            ),
          ),
          // 演员列表
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(actorListProvider.notifier).refresh(),
              child: actorList.when(
                data: (actors) {
                  if (actors.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return _buildActorGrid(context, actors);
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
                            ref.read(actorListProvider.notifier).refresh(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _isSelectionMode ? _buildSelectionBottomBar() : _buildNavigationBar(),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: const Text('演员'),
      actions: [
        // 插件UI注入点 - actor_list_appbar（根据后端已安装插件过滤）
        ...PluginUIRegistry()
            .getButtonsFiltered('actor_list_appbar', ref.watch(installedPluginIdsProvider))
            .map((button) => PluginUIRenderer.renderButton(
                  button,
                  context,
                  contextData: {},
                )),
        
        IconButton(
          icon: const Icon(Icons.checklist),
          onPressed: _toggleSelectionMode,
          tooltip: '批量选择',
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _showCreateActorDialog(context),
          tooltip: '添加演员',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final actorList = ref.watch(actorListProvider);
    final totalCount = actorList.maybeWhen(
      data: (actors) => actors.length,
      orElse: () => 0,
    );
    final isAllSelected = totalCount > 0 && _selectedIds.length == totalCount;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _toggleSelectionMode,
      ),
      title: Text('已选择 ${_selectedIds.length} 个'),
      actions: [
        // 全选/取消全选按钮
        IconButton(
          icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
          onPressed: () {
            setState(() {
              if (isAllSelected) {
                _selectedIds.clear();
              } else {
                actorList.whenData((actors) {
                  _selectedIds.addAll(actors.map((a) => a.id));
                });
              }
            });
          },
          tooltip: isAllSelected ? '取消全选' : '全选',
        ),
        if (_selectedIds.isNotEmpty) ...[
          // 插件UI注入点 - actor_list_selection_actions（根据后端已安装插件过滤）
          ...PluginUIRegistry()
              .getButtonsFiltered('actor_list_selection_actions', ref.watch(installedPluginIdsProvider))
              .map((button) => PluginUIRenderer.renderButton(
                    button,
                    context,
                    contextData: {
                      'actor_ids': _selectedIds.toList(),
                      'exit_selection_mode': () {
                        // 退出多选模式的回调
                        setState(() {
                          _isSelectionMode = false;
                          _selectedIds.clear();
                        });
                      },
                    },
                  )),
          
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _batchDelete,
            tooltip: '删除',
          ),
        ],
      ],
    );
  }

  NavigationBar _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: 3, // 演员页面
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/');
            break;
          case 1:
            context.go('/filter');
            break;
          case 2:
            context.go('/collection');
            break;
          case 3:
            // 已在演员页面
            break;
          case 4:
            context.go('/settings');
            break;
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.filter_list_outlined),
          selectedIcon: Icon(Icons.filter_list),
          label: '筛选',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: '收藏',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outlined),
          selectedIcon: Icon(Icons.person),
          label: '演员',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }

  Widget _buildSelectionBottomBar() {
    final actorList = ref.watch(actorListProvider);
    final totalCount = actorList.maybeWhen(
      data: (actors) => actors.length,
      orElse: () => 0,
    );
    final isAllSelected = totalCount > 0 && _selectedIds.length == totalCount;

    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text('已选择 ${_selectedIds.length} 个演员'),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (isAllSelected) {
                    _selectedIds.clear();
                  } else {
                    actorList.whenData((actors) {
                      _selectedIds.addAll(actors.map((a) => a.id));
                    });
                  }
                });
              },
              icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
              label: Text(isAllSelected ? '取消全选' : '全选'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _toggleSelectionMode,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _selectedIds.isEmpty ? null : _batchDelete,
              icon: const Icon(Icons.delete),
              label: const Text('删除'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无演员',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '添加演员以管理作品关联',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateActorDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('添加演员'),
          ),
        ],
      ),
    );
  }

  Widget _buildActorGrid(BuildContext context, List<Actor> actors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        if (width > 1200) {
          crossAxisCount = 6;
        } else if (width > 900) {
          crossAxisCount = 5;
        } else if (width > 600) {
          crossAxisCount = 4;
        } else if (width > 400) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 2;
        }

        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          cacheExtent: 600,  // 预缓存 2 行
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.6,  // 调整为 0.6，适合竖版海报（约 2:3 比例）
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: actors.length,
          itemBuilder: (context, index) {
            final actor = actors[index];
            return RepaintBoundary(
              child: _isSelectionMode
                  ? _SelectableActorCard(
                      actor: actor,
                      isSelected: _selectedIds.contains(actor.id),
                      onToggle: () => _toggleSelection(actor.id),
                    )
                  : ActorCard(actor: actor),
            );
          },
        );
      },
    );
  }

  void _showCreateActorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CreateActorDialog(),
    );
  }
}

/// 演员卡片
class ActorCard extends StatefulWidget {
  final Actor actor;

  const ActorCard({super.key, required this.actor});

  @override
  State<ActorCard> createState() => _ActorCardState();
}

class _ActorCardState extends State<ActorCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: _isHovered ? 8 : 2,
          child: InkWell(
            onTap: () => context.push('/actors/${widget.actor.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 头像 - 增加图片占比
                Expanded(
                  flex: 4,
                  child: _buildPhoto(),
                ),
                // 信息 - 减少文字占比
                Container(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.actor.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.actor.workCount != null)
                        Text(
                          '${widget.actor.workCount} 部作品',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    // 使用 posterUrl（演员封面，竖版海报）用于卡片显示
    if (widget.actor.posterUrl != null && widget.actor.posterUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: getProxiedImageUrl(widget.actor.posterUrl!),
        fit: BoxFit.fitWidth,  // 宽度填满，高度自适应
        memCacheWidth: 300,  // 统一缓存配置
        memCacheHeight: 400,
        maxHeightDiskCache: 600,
        maxWidthDiskCache: 450,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => Container(
          color: Colors.grey[300],
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: 48,
        color: Colors.grey[500],
      ),
    );
  }
}

/// 创建演员对话框
class CreateActorDialog extends ConsumerStatefulWidget {
  const CreateActorDialog({super.key});

  @override
  ConsumerState<CreateActorDialog> createState() => _CreateActorDialogState();
}

class _CreateActorDialogState extends ConsumerState<CreateActorDialog> with LoadingStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  final _photoUrlsController = TextEditingController();  // 支持多个URL
  final _posterUrlController = TextEditingController();
  final _backdropUrlController = TextEditingController();
  final _biographyController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _nationalityController = TextEditingController();

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
      title: const Text('添加演员'),
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
                    hintText: '输入演员姓名',
                  ),
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
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _photoUrlsController,
                  decoration: const InputDecoration(
                    labelText: '写真URLs',
                    hintText: '多个URL用换行分隔',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _posterUrlController,
                  decoration: const InputDecoration(
                    labelText: '封面URL',
                    hintText: '竖版海报（用于演员列表卡片）',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _backdropUrlController,
                  decoration: const InputDecoration(
                    labelText: '背景图URL',
                    hintText: '横版大图（用于详情页背景）',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nationalityController,
                  decoration: const InputDecoration(
                    labelText: '国籍',
                    hintText: '如：日本、美国',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _birthDateController,
                  decoration: const InputDecoration(
                    labelText: '出生日期',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _biographyController,
                  decoration: const InputDecoration(
                    labelText: '简介',
                    hintText: '输入演员简介',
                  ),
                  maxLines: 3,
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
              : const Text('添加'),
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

    final actor = Actor(
      id: '', // 空 ID，Repository 会生成
      name: _nameController.text.trim(),
      avatarUrl: processTextField(_avatarUrlController.text),
      photoUrls: finalPhotoUrls,
      posterUrl: processTextField(_posterUrlController.text),
      backdropUrl: processTextField(_backdropUrlController.text),
      biography: processTextField(_biographyController.text),
      birthDate: processTextField(_birthDateController.text),
      nationality: processTextField(_nationalityController.text),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await executeWithLoading(
      () => ref.read(actorMutationProvider.notifier).createActor(actor),
      onSuccess: (createdActor) {
        if (mounted && createdActor != null) {
          Navigator.pop(context);
          context.showSuccess('演员 "${createdActor.name}" 已添加');
        }
      },
      onError: (error) {
        if (mounted) {
          context.showError('创建演员失败: $error');
        }
      },
    );
  }
}


/// 可选择的演员卡片
class _SelectableActorCard extends StatefulWidget {
  final Actor actor;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectableActorCard({
    required this.actor,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_SelectableActorCard> createState() => _SelectableActorCardState();
}

class _SelectableActorCardState extends State<_SelectableActorCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: _isHovered ? 8 : 2,
          child: InkWell(
            onTap: widget.onToggle,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 头像 - 增加图片占比
                    Expanded(
                      flex: 4,
                      child: _buildPhoto(),
                    ),
                    // 信息 - 减少文字占比
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.actor.name,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.actor.workCount != null)
                            Text(
                              '${widget.actor.workCount} 部作品',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 选择指示器
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.isSelected ? Colors.blue : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected ? Colors.blue : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      widget.isSelected ? Icons.check : null,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    // 使用 posterUrl（演员封面，竖版海报）用于卡片显示
    if (widget.actor.posterUrl != null && widget.actor.posterUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: getProxiedImageUrl(widget.actor.posterUrl!),
        fit: BoxFit.fitWidth,  // 宽度填满，高度自适应
        memCacheWidth: 300,  // 统一缓存配置
        memCacheHeight: 400,
        maxHeightDiskCache: 600,
        maxWidthDiskCache: 450,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => Container(
          color: Colors.grey[300],
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: 48,
        color: Colors.grey[500],
      ),
    );
  }
}
