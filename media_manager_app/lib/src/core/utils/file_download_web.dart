import 'dart:html' as html;

/// Web 平台文件下载实现
Future<void> downloadFile({
  required List<int> data,
  required String filename,
  required String mimeType,
}) async {
  final blob = html.Blob([data], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  
  final anchor = html.AnchorElement()
    ..href = url
    ..download = filename
    ..click();
  
  html.Url.revokeObjectUrl(url);
}
