import 'package:flutter/material.dart';

class ScanProgressWidget extends StatelessWidget {
  const ScanProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '正在扫描文件...',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              '请稍候',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
