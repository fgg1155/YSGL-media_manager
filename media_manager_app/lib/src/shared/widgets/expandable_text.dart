import 'package:flutter/material.dart';

/// 可展开/收起的文本组件
/// 当文本超过指定行数时，显示"展开"按钮
class ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final String expandText;
  final String collapseText;

  const ExpandableText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 3,
    this.expandText = '展开',
    this.collapseText = '收起',
  });

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _isExpanded = false;
  bool _hasOverflow = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = widget.style ?? theme.textTheme.bodyMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算文本是否会溢出
        final span = TextSpan(text: widget.text, style: textStyle);
        final tp = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: constraints.maxWidth);

        // 检查是否需要显示展开按钮
        final overflow = tp.didExceedMaxLines;
        
        // 只在第一次检测到溢出时更新状态
        if (overflow != _hasOverflow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _hasOverflow = overflow;
              });
            }
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: textStyle,
              maxLines: _isExpanded ? null : widget.maxLines,
              overflow: _isExpanded ? null : TextOverflow.ellipsis,
            ),
            if (_hasOverflow)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isExpanded ? widget.collapseText : widget.expandText,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
