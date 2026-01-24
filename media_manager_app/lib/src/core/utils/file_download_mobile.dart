import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

/// 移动端和桌面端文件下载实现
Future<void> downloadFile({
  required List<int> data,
  required String filename,
  required String mimeType,
}) async {
  try {
    // 桌面平台（Windows, macOS, Linux）：让用户选择保存位置
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 让用户选择文件夹
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存位置',
      );
      
      if (selectedDirectory == null) {
        // 用户取消了选择
        return;
      }
      
      // 在选择的文件夹中创建文件
      final filePath = '$selectedDirectory${Platform.pathSeparator}$filename';
      final file = File(filePath);
      await file.writeAsBytes(data);
      
      print('✓ 文件已保存到: $filePath');
      return;
    }
    
    // Android 平台：直接保存到 Downloads 目录
    if (Platform.isAndroid) {
      // 请求存储权限
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('需要存储权限才能保存文件');
        }
      }
      
      // 获取 Downloads 目录
      Directory? directory;
      final downloadPath = '/storage/emulated/0/Download';
      directory = Directory(downloadPath);
      if (!await directory.exists()) {
        // 如果 Download 不存在，尝试 Downloads
        directory = Directory('/storage/emulated/0/Downloads');
      }
      
      if (!await directory.exists()) {
        throw Exception('无法访问下载目录');
      }
      
      // 创建文件
      final filePath = '${directory.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(data);
      
      print('✓ 文件已保存到: $filePath');
      return;
    }
    
    // iOS 平台：保存到应用文档目录
    if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(data);
      
      print('✓ 文件已保存到: $filePath');
      return;
    }
  } catch (e) {
    print('✗ 保存文件失败: $e');
    rethrow;
  }
}
