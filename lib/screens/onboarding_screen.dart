import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import '../theme/app_theme.dart';

/// 新手引导页面 — 3步引导 + 1步开始
/// 首次使用时自动显示，完成后记住状态
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  AnimationController? _floatController;

  static const _totalPages = 4;

  @override
  void initState() {
    super.initState();
    // 浮动动画控制器
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatController?.dispose();
    super.dispose();
  }

  /// 完成引导，标记已看过，跳转首页
  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            onThemeChanged: () {},
          ),
        ),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: WFColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部跳过按钮
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: _currentPage < _totalPages - 1
                    ? TextButton(
                        onPressed: _completeOnboarding,
                        child: Text(
                          '跳过',
                          style: TextStyle(
                            color: WFColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // 页面内容
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  _buildWelcomePage(colorScheme),
                  _buildStepPage(
                    colorScheme,
                    icon: Icons.camera_alt,
                    stepLabel: '第1步',
                    title: '拍照上传',
                    description: '在纸上写下指定的汉字，用手机拍下手写字迹',
                    mockChild: _buildCaptureMock(colorScheme),
                  ),
                  _buildStepPage(
                    colorScheme,
                    icon: Icons.edit_note,
                    stepLabel: '第2步',
                    title: '检查书写',
                    description: 'AI自动识别每个字符，检查并修正不准确的地方',
                    mockChild: _buildEditMock(colorScheme),
                  ),
                  _buildFinalPage(colorScheme),
                ],
              ),
            ),

            // 底部指示器 + 导航按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  // 上一步按钮
                  if (_currentPage > 0)
                    TextButton.icon(
                      onPressed: _prevPage,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('上一步'),
                    )
                  else
                    const SizedBox(width: 100),

                  // 圆点指示器
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_totalPages, (index) {
                        final isActive = index == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isActive ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive
                                ? WFColors.primary
                                : WFColors.textLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ),

                  // 下一步 / 开始按钮
                  if (_currentPage < _totalPages - 1)
                    TextButton.icon(
                      onPressed: _nextPage,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('下一步'),
                    )
                  else
                    const SizedBox(width: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // 第1页：欢迎
  // ────────────────────────────────────────────
  Widget _buildWelcomePage(ColorScheme colorScheme) {
    return _FadeInWrapper(
      key: ValueKey('welcome'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 浮动动画图标
            AnimatedBuilder(
              animation: _floatController!,
              builder: (context, child) {
                final offset = 8.0 * (_floatController!.value - 0.5);
                return Transform.translate(
                  offset: Offset(0, offset),
                  child: child,
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.font_download,
                  size: 60,
                  color: WFColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              '用你的笔迹，创造你的字体',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '只需3步，把你的手写变成专属字体',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            WFPrimaryButton(
              text: '开始',
              onPressed: _nextPage,
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // 步骤页（第2、3步通用）
  // ────────────────────────────────────────────
  Widget _buildStepPage(
    ColorScheme colorScheme, {
    required IconData icon,
    required String stepLabel,
    required String title,
    required String description,
    required Widget mockChild,
  }) {
    return _FadeInWrapper(
      key: ValueKey(stepLabel),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 步骤标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                stepLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Icon(icon, size: 48, color: WFColors.primary),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // 模拟示意图
            mockChild,
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // 第4页：生成字体（最终页）
  // ────────────────────────────────────────────
  Widget _buildFinalPage(ColorScheme colorScheme) {
    return _FadeInWrapper(
      key: ValueKey('final'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '第3步',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Icon(Icons.auto_awesome, size: 48, color: WFColors.primary),
            const SizedBox(height: 20),
            Text(
              '一键生成',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AI根据你的笔迹风格，\n自动生成6763个常用汉字',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            WFPrimaryButton(
              text: '立即开始造字！',
              icon: Icons.rocket_launch,
              onPressed: _completeOnboarding,
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // 模拟示意图
  // ────────────────────────────────────────────

  /// 拍照模拟图
  Widget _buildCaptureMock(ColorScheme colorScheme) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // 模拟纸张上的手写字
          Container(
            width: 200,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Center(
              child: Text(
                '的 一 是\n不 了 在',
                style: TextStyle(
                  fontSize: 28,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, size: 20, color: WFColors.primary),
              const SizedBox(width: 6),
              Text(
                '拍照上传',
                style: TextStyle(
                  fontSize: 14,
                  color: WFColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 编辑器模拟图
  Widget _buildEditMock(ColorScheme colorScheme) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // 模拟字符网格
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: ['的', '一', '是', '不', '了', '在'].map((c) {
              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: 24,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 18, color: WFColors.success),
              const SizedBox(width: 6),
              Text(
                'AI识别 + 手动修正',
                style: TextStyle(
                  fontSize: 13,
                  color: WFColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 淡入动画包装器 — 每页出现时播放一次淡入
class _FadeInWrapper extends StatefulWidget {
  final Widget child;

  const _FadeInWrapper({super.key, required this.child});

  @override
  State<_FadeInWrapper> createState() => _FadeInWrapperState();
}

class _FadeInWrapperState extends State<_FadeInWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.05),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _controller.forward();
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
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
