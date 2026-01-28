import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/digits_input_formatter.dart';
import '../utils/decimal_input_formatter.dart';

/// 应用统一文本输入框
/// 自动处理键盘类型、输入限制、焦点切换等
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? initialValue;
  final bool required;
  final int? maxLines;
  final AppTextFieldType type;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool isLastField;

  const AppTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.helperText,
    this.initialValue,
    this.required = false,
    this.maxLines,
    this.type = AppTextFieldType.text,
    this.onChanged,
    this.validator,
    this.isLastField = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        helperText: helperText,
        border: const OutlineInputBorder(),
        alignLabelWithHint: maxLines != null && maxLines! > 1,
      ),
      maxLines: maxLines ?? 1,
      keyboardType: _getKeyboardType(),
      textInputAction: _getTextInputAction(),
      inputFormatters: _getInputFormatters(),
      autocorrect: _shouldAutocorrect(),
      onFieldSubmitted: _getOnFieldSubmitted(context),
      validator: validator ?? (required ? _defaultValidator : null),
      onChanged: onChanged,
    );
  }

  TextInputType _getKeyboardType() {
    switch (type) {
      case AppTextFieldType.text:
        return TextInputType.text;
      case AppTextFieldType.multiline:
        return TextInputType.multiline;
      case AppTextFieldType.number:
        return TextInputType.number;
      case AppTextFieldType.decimal:
        return const TextInputType.numberWithOptions(decimal: true);
      case AppTextFieldType.url:
        return TextInputType.url;
      case AppTextFieldType.email:
        return TextInputType.emailAddress;
      case AppTextFieldType.phone:
        return TextInputType.phone;
    }
  }

  TextInputAction _getTextInputAction() {
    if (isLastField) {
      return TextInputAction.done;
    }
    if (maxLines != null && maxLines! > 1) {
      return TextInputAction.newline;
    }
    return TextInputAction.next;
  }

  List<TextInputFormatter>? _getInputFormatters() {
    switch (type) {
      case AppTextFieldType.number:
        return [DigitsInputFormatter()];
      case AppTextFieldType.decimal:
        return [DecimalInputFormatter(decimalPlaces: 1)];
      default:
        return null;
    }
  }

  bool _shouldAutocorrect() {
    // URL 和 Email 不需要自动更正
    return type != AppTextFieldType.url && type != AppTextFieldType.email;
  }

  ValueChanged<String>? _getOnFieldSubmitted(BuildContext context) {
    if (isLastField) {
      return (_) => FocusScope.of(context).unfocus();
    }
    if (maxLines != null && maxLines! > 1) {
      return null; // 多行输入框不处理提交
    }
    return (_) => FocusScope.of(context).nextFocus();
  }

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) {
      return '$labelText不能为空';
    }
    return null;
  }
}

/// 文本输入框类型
enum AppTextFieldType {
  text,      // 普通文本
  multiline, // 多行文本
  number,    // 整数
  decimal,   // 小数
  url,       // URL
  email,     // 邮箱
  phone,     // 电话
}
