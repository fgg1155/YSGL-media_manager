import 'dart:ui';
import 'package:flutter/material.dart';

/// 毛玻璃容器组件 - 提供统一的毛玻璃效果
/// 
/// 使用示例：
/// ```dart
/// GlassmorphismContainer(
///   child: Text('内容'),
/// )
/// ```
class GlassmorphismContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? color;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassmorphismContainer({
    super.key,
    required this.child,
    this.blur = 15.0,  // 模糊度
    this.opacity = 0.7,  // 不透明度 - 既能看到背景又能清晰阅读内容
    this.color,
    this.borderRadius,
    this.border,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveColor = color ?? colorScheme.surfaceContainerLow;
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(12);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: effectiveColor.withOpacity(opacity),
              borderRadius: effectiveBorderRadius,
              border: border,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃卡片组件 - 带标题和图标的卡片
class GlassmorphismCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final double blur;
  final double opacity;

  const GlassmorphismCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.blur = 15.0,  // 模糊度
    this.opacity = 0.7,  // 不透明度 - 既能看到背景又能清晰阅读内容
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassmorphismContainer(
      blur: blur,
      opacity: opacity,
      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
