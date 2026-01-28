import 'package:flutter/services.dart';

/// 纯数字输入格式化器
/// 只允许输入数字，保持光标位置
class DigitsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 如果是空字符串，允许
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // 只允许数字
    final filteredText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // 如果过滤后没有变化，直接返回（保持光标位置）
    if (filteredText == newValue.text) {
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
