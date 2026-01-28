import 'package:flutter/services.dart';

/// 小数输入格式化器
/// 只允许输入数字和一个小数点，保持光标位置
class DecimalInputFormatter extends TextInputFormatter {
  final int? decimalPlaces;

  DecimalInputFormatter({this.decimalPlaces});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 如果是空字符串，允许
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // 只允许数字和小数点
    final filteredText = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');

    // 如果过滤后没有变化，直接返回（保持光标位置）
    if (filteredText == newValue.text) {
      // 检查小数点数量
      final dotCount = filteredText.split('.').length - 1;
      if (dotCount > 1) {
        // 如果有多个小数点，只保留第一个
        final firstDotIndex = filteredText.indexOf('.');
        final beforeDot = filteredText.substring(0, firstDotIndex + 1);
        final afterDot = filteredText.substring(firstDotIndex + 1).replaceAll('.', '');
        final result = beforeDot + afterDot;
        
        // 计算新的光标位置
        int newOffset = newValue.selection.baseOffset;
        if (newOffset > result.length) {
          newOffset = result.length;
        }
        
        return TextEditingValue(
          text: result,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      }

      // 如果指定了小数位数，限制小数位数
      if (decimalPlaces != null && filteredText.contains('.')) {
        final parts = filteredText.split('.');
        if (parts.length == 2 && parts[1].length > decimalPlaces!) {
          final result = '${parts[0]}.${parts[1].substring(0, decimalPlaces!)}';
          
          // 计算新的光标位置
          int newOffset = newValue.selection.baseOffset;
          if (newOffset > result.length) {
            newOffset = result.length;
          }
          
          return TextEditingValue(
            text: result,
            selection: TextSelection.collapsed(offset: newOffset),
          );
        }
      }

      // 没有问题，保持原样（包括光标位置）
      return newValue;
    }

    // 如果过滤掉了字符，需要调整光标位置
    int newOffset = newValue.selection.baseOffset;
    
    // 计算被过滤掉的字符数
    int removedChars = newValue.text.length - filteredText.length;
    newOffset = (newOffset - removedChars).clamp(0, filteredText.length);

    return TextEditingValue(
      text: filteredText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
