import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
// 统一设计系统 — 手迹造字 App
// ═══════════════════════════════════════════════════════════

/// 统一色彩方案
class WFColors {
  WFColors._();

  // ── 主色调：温暖的墨色系 ──
  static const primary = Color(0xFF2C3E50);      // 深墨蓝
  static const primaryLight = Color(0xFF34495E);  // 浅墨蓝
  static const accent = Color(0xFFE74C3C);        // 朱红（强调色）
  static const accentLight = Color(0xFFFF6B6B);   // 浅朱红

  // ── 功能色 ──
  static const success = Color(0xFF27AE60);       // 成功绿
  static const warning = Color(0xFFF39C12);       // 警告黄
  static const error = Color(0xFFE74C3C);         // 错误红
  static const info = Color(0xFF3498DB);          // 信息蓝

  // ── 背景色 ──
  static const bgPrimary = Color(0xFFF8F9FA);     // 主背景
  static const bgCard = Color(0xFFFFFFFF);        // 卡片背景
  static const bgDark = Color(0xFF1A1A2E);        // 深色背景

  // ── 文字色 ──
  static const textPrimary = Color(0xFF2C3E50);
  static const textSecondary = Color(0xFF7F8C8D);
  static const textLight = Color(0xFFBDC3C7);
}

// ═══════════════════════════════════════════════════════════
// 卡片组件
// ═══════════════════════════════════════════════════════════

/// 带左侧彩色边条的通用卡片
///
/// 统一圆角 12px、统一阴影，左侧可配置彩色边条。
class WFCard extends StatelessWidget {
  final Widget child;
  final Color? accentColor;
  final VoidCallback? onTap;
  final EdgeInsets? padding;

  const WFCard({
    super.key,
    required this.child,
    this.accentColor,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: accentColor != null
            ? Border(left: BorderSide(color: accentColor!, width: 4))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

/// 带图标 + 标题 + 副标题的操作卡片，用于首页入口
///
/// 左侧彩色圆角图标区 + 右侧文字 + 箭头。
class WFActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const WFActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return WFCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.75)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // 图标区
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),

            // 文字区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),

            // 箭头
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 按钮组件
// ═══════════════════════════════════════════════════════════

/// 主要操作按钮 — 圆角 24px，渐变效果
class WFPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;

  const WFPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [WFColors.primary, WFColors.primaryLight],
        ),
        boxShadow: [
          BoxShadow(
            color: WFColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(text),
          ],
        ),
      ),
    );
  }
}

/// 次要按钮 — 描边样式
class WFSecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const WFSecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: WFColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        side: const BorderSide(color: WFColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(text),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// AppBar
// ═══════════════════════════════════════════════════════════

/// 统一的 AppBar — 标题居中，统一高度，白色背景
class WFAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const WFAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: WFColors.textPrimary,
        ),
      ),
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: WFColors.bgPrimary,
      surfaceTintColor: Colors.transparent,
      leading: leading,
      actions: actions,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 对话框
// ═══════════════════════════════════════════════════════════

/// 统一对话框样式 — 圆角 16px，统一内边距
class WFDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;

  const WFDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  /// 快速显示对话框
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context,
      builder: (_) => WFDialog(
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: WFColors.bgCard,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: WFColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            content,
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 动画工具
// ═══════════════════════════════════════════════════════════

/// 统一动画工具类
class WFAnimations {
  WFAnimations._();

  /// 页面切换动画 — 从右滑入
  static Route<T> slideRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  /// 卡片出现动画 — 淡入 + 上移
  static Widget fadeInSlide(Widget child, {Duration delay = Duration.zero}) {
    return _FadeInSlideWrapper(delay: delay, child: child);
  }

  /// 按钮点击缩放
  static Widget tapScale(Widget child, VoidCallback onTap) {
    return _TapScaleWrapper(onTap: onTap, child: child);
  }
}

// ── 淡入 + 上移动画内部实现 ──

class _FadeInSlideWrapper extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeInSlideWrapper({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeInSlideWrapper> createState() => _FadeInSlideWrapperState();
}

class _FadeInSlideWrapperState extends State<_FadeInSlideWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

// ── 点击缩放动画内部实现 ──

class _TapScaleWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TapScaleWrapper({required this.child, required this.onTap});

  @override
  State<_TapScaleWrapper> createState() => _TapScaleWrapperState();
}

class _TapScaleWrapperState extends State<_TapScaleWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
      value: 1.0,
      lowerBound: 0.92,
      upperBound: 1.0,
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        widget.onTap();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
