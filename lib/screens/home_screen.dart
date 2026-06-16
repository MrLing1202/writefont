import 'package:flutter/cupertino.dart';

import '../models/font_project.dart';
import '../widgets/glyph_tile.dart';
import 'capture_screen.dart' show CaptureScreen, ImageSource;
import 'glyph_editor_screen.dart';
import 'font_preview_screen.dart';

/// 主页 - Tab 导航
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final FontProject _project = FontProject();
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: _currentTab,
        onTap: (index) => setState(() => _currentTab = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.camera_fill),
            label: '造字',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.textformat_abc),
            label: '字库',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.eye_fill),
            label: '预览',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return _buildCaptureTab(context);
          case 1:
            return _buildGlyphsTab(context);
          case 2:
            return _buildPreviewTab(context);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  /// 造字 Tab
  Widget _buildCaptureTab(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('手迹造字'),
        trailing: GestureDetector(
          onTap: () => _showProjectSettings(context),
          child: const Icon(CupertinoIcons.settings, size: 22),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // 项目信息卡片
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _project.name,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已收录 ${_project.glyphs.length} 个字符',
                      style: TextStyle(
                        color: CupertinoColors.white.withOpacity(0.8),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '包含 ${_project.includedGlyphCount} 个字符将生成字体',
                      style: TextStyle(
                        color: CupertinoColors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // 操作按钮
              _buildActionButton(
                context,
                icon: CupertinoIcons.camera_fill,
                title: '拍照识别',
                subtitle: '拍摄手写字符照片，自动识别',
                color: CupertinoColors.activeBlue,
                onTap: () => _navigateToCapture(context, ImageSource.camera),
              ),
              const SizedBox(height: 16),
              _buildActionButton(
                context,
                icon: CupertinoIcons.photo_fill,
                title: '从相册选取',
                subtitle: '选择已有的手写字符图片',
                color: CupertinoColors.activeGreen,
                onTap: () => _navigateToCapture(context, ImageSource.gallery),
              ),
              const SizedBox(height: 16),
              _buildActionButton(
                context,
                icon: CupertinoIcons.pencil_circle_fill,
                title: '手动输入',
                subtitle: '输入要收录的中文字符',
                color: CupertinoColors.systemOrange,
                onTap: () => _showManualInput(context),
              ),
              const Spacer(),
              // 快速统计
              if (_project.glyphs.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('总字符', '${_project.glyphs.length}'),
                      _buildStatItem('已选中', '${_project.includedGlyphCount}'),
                      _buildStatItem(
                        '进度',
                        '${_project.glyphs.isEmpty ? 0 : (_project.includedGlyphCount * 100 ~/ _project.glyphs.length)}%',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 字库 Tab
  Widget _buildGlyphsTab(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('我的字库'),
        trailing: _project.glyphs.isNotEmpty
            ? GestureDetector(
                onTap: () => _toggleSelectAll(),
                child: const Text('全选', style: TextStyle(fontSize: 16)),
              )
            : null,
      ),
      child: _project.glyphs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.textformat_abc,
                    size: 64,
                    color: CupertinoColors.systemGrey3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有字符',
                    style: TextStyle(
                      fontSize: 18,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '去"造字"标签页添加字符吧',
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.systemGrey2,
                    ),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 100,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: _project.glyphs.length,
                itemBuilder: (context, index) {
                  final glyph = _project.glyphs[index];
                  return GlyphTile(
                    glyph: glyph,
                    onTap: () => _navigateToEditor(context, index),
                    onLongPress: () => _showGlyphOptions(context, index),
                  );
                },
              ),
            ),
    );
  }

  /// 预览 Tab
  Widget _buildPreviewTab(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('字体预览'),
      ),
      child: FontPreviewScreen(
        project: _project,
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: CupertinoColors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.systemGrey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: CupertinoColors.activeBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.secondaryLabel,
          ),
        ),
      ],
    );
  }

  // ===== Navigation =====

  void _navigateToCapture(BuildContext context, ImageSource source) async {
    final result = await Navigator.push<List<GlyphData>>(
      context,
      CupertinoPageRoute(
        builder: (context) => CaptureScreen(source: source),
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        for (final glyph in result) {
          _project.addOrUpdateGlyph(glyph);
        }
      });
    }
  }

  void _navigateToEditor(BuildContext context, int index) async {
    final result = await Navigator.push<GlyphData>(
      context,
      CupertinoPageRoute(
        builder: (context) => GlyphEditorScreen(
          glyph: _project.glyphs[index],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _project.glyphs[index] = result;
      });
    }
  }

  void _showGlyphOptions(BuildContext context, int index) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('字符: ${_project.glyphs[index].character}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _project.glyphs[index] = _project.glyphs[index].copyWith(
                  isIncluded: !_project.glyphs[index].isIncluded,
                );
              });
            },
            child: Text(_project.glyphs[index].isIncluded ? '排除' : '包含'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _project.removeGlyph(_project.glyphs[index].character);
              });
            },
            child: const Text('删除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showProjectSettings(BuildContext context) {
    final nameController = TextEditingController(text: _project.name);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('项目设置'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: nameController,
            placeholder: '字体名称',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              setState(() {
                _project.name = nameController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showManualInput(BuildContext context) {
    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('手动添加字符'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '输入中文字符，如：你好世界',
            maxLines: 3,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final text = controller.text;
              setState(() {
                for (int i = 0; i < text.length; i++) {
                  final char = text[i];
                  if (char.trim().isNotEmpty && !_project.hasCharacter(char)) {
                    _project.addOrUpdateGlyph(GlyphData(character: char));
                  }
                }
              });
              Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      final allIncluded = _project.glyphs.every((g) => g.isIncluded);
      for (int i = 0; i < _project.glyphs.length; i++) {
        _project.glyphs[i] =
            _project.glyphs[i].copyWith(isIncluded: !allIncluded);
      }
    });
  }
}
