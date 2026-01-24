import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/services/api_service.dart';
import '../../../../core/services/local_file_scanner.dart';
import '../../../../core/services/local_file_grouper.dart';
import '../../../../core/services/local_file_matcher.dart';
import '../../../../core/services/backend_mode.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/media_file.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/plugins/ui_registry.dart';
import '../../../../core/plugins/ui_renderer.dart';
import '../widgets/scan_progress_widget.dart';
import '../widgets/match_results_widget.dart';
import '../widgets/file_group_card_with_thumbnail.dart';

class FileScanScreen extends ConsumerStatefulWidget {
  const FileScanScreen({super.key});

  @override
  ConsumerState<FileScanScreen> createState() => _FileScanScreenState();
}

class _FileScanScreenState extends ConsumerState<FileScanScreen> {
  final List<String> _selectedPaths = [];  // 支持多个路径
  bool _recursive = true;
  bool _isScanning = false;
  bool _isMatching = false;
  ScanResponse? _scanResponse;
  MatchResponse? _matchResponse;

  Future<void> _selectDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        setState(() {
          // 检查是否已存在
          if (!_selectedPaths.contains(selectedDirectory)) {
            _selectedPaths.add(selectedDirectory);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        context.showError('选择目录失败: $e');
      }
    }
  }

  void _removeDirectory(String path) {
    setState(() {
      _selectedPaths.remove(path);
    });
  }

  void _clearDirectories() {
    setState(() {
      _selectedPaths.clear();
    });
  }

  Future<void> _startScan() async {
    // 过滤掉空路径
    final validPaths = _selectedPaths.where((p) => p.isNotEmpty).toList();
    
    if (validPaths.isEmpty) {
      context.showWarning('请先选择至少一个扫描目录');
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResponse = null;
      _matchResponse = null;
    });

    try {
      // 检测后端模式
      final modeManager = ref.read(backendModeManagerProvider);
      final isStandalone = modeManager.isStandaloneMode;

      if (isStandalone) {
        // 独立模式：使用本地服务
        await _scanWithLocalServices(validPaths);
      } else {
        // PC 模式：使用 API
        await _scanWithApi(validPaths);
      }

      // 自动开始匹配
      if (_scanResponse != null && _scanResponse!.scannedFiles.isNotEmpty) {
        _startMatch();
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      if (mounted) {
        context.showError('扫描失败: $e');
      }
    }
  }

  /// 使用 API 扫描（PC 模式）
  Future<void> _scanWithApi(List<String> paths) async {
    final apiService = ref.read(apiServiceProvider);
    final response = await apiService.startScan(
      paths: paths,
      recursive: _recursive,
    );

    setState(() {
      _scanResponse = response;
      _isScanning = false;
    });
  }

  /// 使用本地服务扫描（独立模式）
  Future<void> _scanWithLocalServices(List<String> paths) async {
    final scanner = ref.read(localFileScannerProvider);
    final grouper = ref.read(localFileGrouperProvider);

    // 扫描所有路径
    final allScannedFiles = <LocalScannedFile>[];
    for (final path in paths) {
      final result = await scanner.scanDirectory(path, _recursive);
      allScannedFiles.addAll(result.scannedFiles);
    }

    // 分组文件
    final fileGroups = grouper.groupFiles(allScannedFiles);
    
    // 过滤出只有多个文件的组（单文件不算多分段视频）
    final multiPartGroups = fileGroups.where((g) => g.files.length > 1).toList();

    // 转换为 API 格式
    final scannedFiles = allScannedFiles.map((f) => ScannedFile(
      filePath: f.filePath,
      fileName: f.fileName,
      fileSize: f.fileSize,
      parsedCode: f.parsedCode,
      parsedTitle: f.parsedTitle,
      parsedYear: f.parsedYear,
    )).toList();

    final apiFileGroups = multiPartGroups.map((g) => FileGroup(
      baseName: g.baseName,
      files: g.files.map((f) => ScannedFile(
        filePath: f.scannedFile.filePath,
        fileName: f.scannedFile.fileName,
        fileSize: f.scannedFile.fileSize,
        parsedCode: f.scannedFile.parsedCode,
        parsedTitle: f.scannedFile.parsedTitle,
        parsedYear: f.scannedFile.parsedYear,
      )).toList(),
      totalSize: g.totalSize,
    )).toList();

    setState(() {
      _scanResponse = ScanResponse(
        success: true,
        totalFiles: allScannedFiles.length,
        scannedFiles: scannedFiles,
        fileGroups: apiFileGroups,
        message: '扫描完成',
      );
      _isScanning = false;
    });
  }

  Future<void> _startMatch() async {
    if (_scanResponse == null || _scanResponse!.scannedFiles.isEmpty) {
      return;
    }

    setState(() {
      _isMatching = true;
    });

    try {
      // 检测后端模式
      final modeManager = ref.read(backendModeManagerProvider);
      final isStandalone = modeManager.isStandaloneMode;

      if (isStandalone) {
        // 独立模式：使用本地匹配服务
        await _matchWithLocalServices();
      } else {
        // PC 模式：使用 API
        await _matchWithApi();
      }
    } catch (e) {
      setState(() {
        _isMatching = false;
      });
      if (mounted) {
        context.showError('匹配失败: $e');
      }
    }
  }

  /// 使用 API 匹配（PC 模式）
  Future<void> _matchWithApi() async {
    final apiService = ref.read(apiServiceProvider);
    final response = await apiService.matchFiles(
      _scanResponse!.scannedFiles,
      _scanResponse!.fileGroups,
    );

    setState(() {
      _matchResponse = response;
      _isMatching = false;
    });
  }

  /// 使用本地服务匹配（独立模式）
  Future<void> _matchWithLocalServices() async {
    final matcher = ref.read(localFileMatcherProvider);
    final mediaRepo = ref.read(mediaRepositoryProvider);

    // 获取所有媒体数据
    final allMedia = await mediaRepo.getAllMedia();

    // 转换扫描文件为本地格式
    final localScannedFiles = _scanResponse!.scannedFiles.map((f) => LocalScannedFile(
      filePath: f.filePath,
      fileName: f.fileName,
      fileSize: f.fileSize,
      parsedCode: f.parsedCode,
      parsedTitle: f.parsedTitle,
      parsedYear: f.parsedYear,
    )).toList();

    // 转换文件组为本地格式
    final localFileGroups = _scanResponse!.fileGroups.map((g) {
      final localFiles = g.files.map((f) => LocalScannedFileWithPart(
        scannedFile: LocalScannedFile(
          filePath: f.filePath,
          fileName: f.fileName,
          fileSize: f.fileSize,
          parsedCode: f.parsedCode,
          parsedTitle: f.parsedTitle,
          parsedYear: f.parsedYear,
        ),
        partInfo: null,
      )).toList();

      return LocalFileGroup(
        baseName: g.baseName,
        files: localFiles,
        totalSize: g.totalSize,
      );
    }).toList();

    // 执行匹配
    final fileMatchResults = matcher.matchFiles(localScannedFiles, allMedia);
    final groupMatchResults = matcher.matchFileGroups(localFileGroups, allMedia);

    // 转换为 API 格式
    final matchResults = fileMatchResults.map((r) => MatchResult(
      scannedFile: ScannedFile(
        filePath: r.scannedFile.filePath,
        fileName: r.scannedFile.fileName,
        fileSize: r.scannedFile.fileSize,
        parsedCode: r.scannedFile.parsedCode,
        parsedTitle: r.scannedFile.parsedTitle,
        parsedYear: r.scannedFile.parsedYear,
      ),
      matchType: r.matchType.toString().split('.').last,
      matchedMedia: r.matchedMedia,
      confidence: r.confidence,
      suggestions: r.suggestions,
    )).toList();

    final apiGroupMatchResults = groupMatchResults.map((r) {
      final apiFileGroup = FileGroup(
        baseName: r.fileGroup.baseName,
        files: r.fileGroup.files.map((f) => ScannedFile(
          filePath: f.scannedFile.filePath,
          fileName: f.scannedFile.fileName,
          fileSize: f.scannedFile.fileSize,
          parsedCode: f.scannedFile.parsedCode,
          parsedTitle: f.scannedFile.parsedTitle,
          parsedYear: f.scannedFile.parsedYear,
        )).toList(),
        totalSize: r.fileGroup.totalSize,
      );

      return GroupMatchResult(
        fileGroup: apiFileGroup,
        matchType: r.matchType.toString().split('.').last,
        matchedMedia: r.matchedMedia,
        confidence: r.confidence,
        suggestions: r.suggestions,
      );
    }).toList();

    // 统计匹配结果
    int exactMatches = 0;
    int fuzzyMatches = 0;
    int noMatches = 0;

    for (final result in matchResults) {
      if (result.matchType == 'exact') {
        exactMatches++;
      } else if (result.matchType == 'fuzzy') {
        fuzzyMatches++;
      } else {
        noMatches++;
      }
    }

    for (final result in apiGroupMatchResults) {
      if (result.matchType == 'exact') {
        exactMatches++;
      } else if (result.matchType == 'fuzzy') {
        fuzzyMatches++;
      } else {
        noMatches++;
      }
    }

    setState(() {
      _matchResponse = MatchResponse(
        success: true,
        matchResults: matchResults,
        groupMatchResults: apiGroupMatchResults,
        exactMatches: exactMatches,
        fuzzyMatches: fuzzyMatches,
        noMatches: noMatches,
      );
      _isMatching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地文件扫描'),
        actions: [
          // Plugin UI injection point: scan_results_page
          ...PluginUIRegistry.instance.getButtons('scan_results_page').map((button) {
            return PluginUIRenderer.renderButton(
              button,
              context,
              contextData: {
                'total_files': _scanResponse?.totalFiles.toString() ?? '0',
                'scanned_files': _scanResponse?.scannedFiles.length.toString() ?? '0',
              },
            );
          }),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选择目录
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '扫描设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_selectedPaths.isNotEmpty)
                          TextButton.icon(
                            onPressed: _isScanning ? null : _clearDirectories,
                            icon: const Icon(Icons.clear_all, size: 16),
                            label: const Text('清空'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // 已选择的目录列表
                    if (_selectedPaths.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.folder_outlined, color: Colors.grey),
                            SizedBox(width: 8),
                            Text(
                              '未选择目录',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _selectedPaths.length,
                          itemBuilder: (context, index) {
                            final path = _selectedPaths[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.folder, size: 20),
                                title: Text(
                                  path,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: _isScanning ? null : () => _removeDirectory(path),
                                  tooltip: '移除',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isScanning ? null : _selectDirectory,
                            icon: const Icon(Icons.add),
                            label: Text(_selectedPaths.isEmpty ? '选择目录' : '添加目录'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('递归扫描子目录'),
                      value: _recursive,
                      onChanged: _isScanning
                          ? null
                          : (value) {
                              setState(() {
                                _recursive = value ?? true;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _startScan,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(_isScanning ? '扫描中...' : '开始扫描'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 扫描进度
            if (_isScanning)
              const ScanProgressWidget(),

            // 扫描结果
            if (_scanResponse != null && !_isScanning) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '扫描结果',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('扫描了 ${_selectedPaths.length} 个目录'),
                      Text('找到 ${_scanResponse!.totalFiles} 个视频文件'),
                      if (_scanResponse!.fileGroups.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '检测到 ${_scanResponse!.fileGroups.length} 组多分段视频',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 匹配进度
            if (_isMatching)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('正在匹配文件...'),
                    ],
                  ),
                ),
              ),

            // 匹配结果
            if (_matchResponse != null && !_isMatching)
              MatchResultsWidget(
                matchResponse: _matchResponse!,
                onConfirm: () {
                  // 刷新媒体列表
                  Navigator.of(context).pop(true);
                },
              ),
          ],
        ),
      ),
    );
  }
}
