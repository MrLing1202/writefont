import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/recognition_history.dart';
import '../theme/app_theme.dart';

/// 智能字帖生成器
///
/// 根据识别历史分析薄弱字符，生成田字格练习字帖。
/// 用户可选择字符、调整网格大小，生成可分享的图片。
class PracticeSheetScreen extends StatefulWidget {
  const PracticeSheetScreen({super.key});

  @override
  State<PracticeSheetScreen> createState() => _PracticeSheetScreenState();
}

class _PracticeSheetScreenState extends State<PracticeSheetScreen> {
  // 数据
  List<_CharPracticeInfo> _charInfos = [];
  bool _isLoading = true;

  // 用户选择
  final Set<String> _selectedChars = {};
  int _columns = 5; // 每行列数
  bool _selectAll = true;
  bool _showPinyin = false; // 是否显示拼音提示

  // 用于截图分享
  final GlobalKey _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载识别历史，按置信度排序
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final entries = await RecognitionHistoryService.getAll();
      if (!mounted) return;

      // 按字符分组，计算每个字符的平均置信度
      final charMap = <String, _CharPracticeInfo>{};
      for (final entry in entries) {
        final char = entry.character;
        if (char.isEmpty) continue;
        if (charMap.containsKey(char)) {
          charMap[char]!.totalConfidence += entry.confidence;
          charMap[char]!.count++;
          if (entry.wasCorrected) charMap[char]!.correctionCount++;
        } else {
          charMap[char] = _CharPracticeInfo(
            character: char,
            totalConfidence: entry.confidence,
            count: 1,
            correctionCount: entry.wasCorrected ? 1 : 0,
          );
        }
      }

      // 计算平均置信度并排序（低置信度在前 = 最需要练习的）
      final list = charMap.values.toList();
      for (final info in list) {
        info.avgConfidence = info.totalConfidence / info.count;
      }
      list.sort((a, b) => a.avgConfidence.compareTo(b.avgConfidence));

      setState(() {
        _charInfos = list;
        // 默认选中置信度低于 80% 的字符
        _selectedChars.clear();
        for (final info in list) {
          if (info.avgConfidence < 0.8) {
            _selectedChars.add(info.character);
          }
        }
        _selectAll = _selectedChars.length == list.length;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[PracticeSheet] 加载数据失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 切换字符选择状态
  void _toggleChar(String char) {
    setState(() {
      if (_selectedChars.contains(char)) {
        _selectedChars.remove(char);
      } else {
        _selectedChars.add(char);
      }
      _selectAll = _selectedChars.length == _charInfos.length;
    });
  }

  /// 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectAll) {
        _selectedChars.clear();
      } else {
        _selectedChars.addAll(_charInfos.map((e) => e.character));
      }
      _selectAll = !_selectAll;
    });
  }

  /// 分享字帖图片
  Future<void> _shareImage() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/practice_sheet.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '手迹造字 - 智能字帖',
      );
    } catch (e) {
      debugPrint('[PracticeSheet] 分享失败: $e');
      if (mounted) {
        WFSnackBar.show(context, '分享失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: '智能字帖生成器',
        actions: [
          // 分享按钮
          if (_selectedChars.isNotEmpty)
            IconButton(
              onPressed: _shareImage,
              icon: const Icon(Icons.share_outlined),
              tooltip: '分享字帖',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _charInfos.isEmpty
              ? _buildEmptyState(colorScheme)
              : _buildContent(colorScheme),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note, size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('暂无识别记录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('识别字符后才能生成针对性字帖',
              style: TextStyle(fontSize: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    final selectedList = _charInfos
        .where((e) => _selectedChars.contains(e.character))
        .toList();

    return Column(
      children: [
        // ── 顶部控制栏 ──
        _buildControlBar(colorScheme),
        // ── 字符选择区 ──
        _buildCharSelector(colorScheme),
        // ── 字帖预览区 ──
        Expanded(
          child: selectedList.isEmpty
              ? Center(
                  child: Text('请选择要练习的字符',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: _buildPracticeSheet(selectedList, colorScheme),
                  ),
                ),
        ),
      ],
    );
  }

  /// 顶部控制栏
  Widget _buildControlBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // 选中数量
          Text('已选 ${_selectedChars.length}/${_charInfos.length}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          const SizedBox(width: 12),
          // 全选按钮
          TextButton.icon(
            onPressed: _toggleSelectAll,
            icon: Icon(_selectAll ? Icons.check_box : Icons.check_box_outline_blank, size: 18),
            label: Text(_selectAll ? '取消全选' : '全选', style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Spacer(),
          // 列数选择
          Text('每行', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 4),
          DropdownButton<int>(
            value: _columns,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 4, child: Text('4')),
              DropdownMenuItem(value: 5, child: Text('5')),
              DropdownMenuItem(value: 6, child: Text('6')),
              DropdownMenuItem(value: 8, child: Text('8')),
            ],
            onChanged: (v) => setState(() => _columns = v ?? 5),
          ),
        ],
      ),
    );
  }

  /// 字符选择区域（可横向滚动）
  Widget _buildCharSelector(ColorScheme colorScheme) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _charInfos.length,
        itemBuilder: (ctx, i) {
          final info = _charInfos[i];
          final isSelected = _selectedChars.contains(info.character);
          final confColor = info.avgConfidence >= 0.8
              ? Colors.green
              : info.avgConfidence >= 0.6
                  ? Colors.orange
                  : Colors.red;

          return GestureDetector(
            onTap: () => _toggleChar(info.character),
            child: Container(
              width: 64,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: colorScheme.primary, width: 2)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(info.character,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text('${(info.avgConfidence * 100).toInt()}%',
                      style: TextStyle(fontSize: 10, color: confColor,
                          fontWeight: FontWeight.w600)),
                  Text('${info.count}次',
                      style: TextStyle(fontSize: 9,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建田字格字帖
  Widget _buildPracticeSheet(List<_CharPracticeInfo> chars, ColorScheme colorScheme) {
    final bgColor = Colors.white;
    final gridColor = Colors.grey.shade300;
    final charColor = Colors.grey.shade400; // 浅色范字
    final rows = (chars.length / _columns).ceil();

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gridColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── 标题 ──
          Text('手迹造字 · 智能练习字帖',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800)),
          const SizedBox(height: 4),
          Text('薄弱字符优先练习 · 共 ${chars.length} 字',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          // ── 田字格网格 ──
          for (int r = 0; r < rows; r++)
            _buildGridRow(chars, r, gridColor, charColor),
          const SizedBox(height: 8),
          // ── 页脚 ──
          Text('由手迹造字 App 自动生成',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  /// 构建一行田字格
  Widget _buildGridRow(List<_CharPracticeInfo> chars, int row,
      Color gridColor, Color charColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_columns, (col) {
        final index = row * _columns + col;
        if (index >= chars.length) {
          return _buildTianZiGe(null, gridColor, charColor);
        }
        return _buildTianZiGe(chars[index], gridColor, charColor);
      }),
    );
  }

  /// 构建单个田字格
  Widget _buildTianZiGe(_CharPracticeInfo? info, Color gridColor, Color charColor) {
    const size = 56.0;

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: gridColor, width: 1.5),
      ),
      child: Stack(
        children: [
          // 十字虚线
          CustomPaint(
            size: const Size(size, size),
            painter: _TianZiGePainter(gridColor),
          ),
          // 浅色范字
          if (info != null)
            Center(
              child: Text(
                info.character,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: charColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 田字格十字虚线绘制器
class _TianZiGePainter extends CustomPainter {
  final Color lineColor;

  _TianZiGePainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // 虚线画法
    final dashWidth = 3.0;
    final dashSpace = 3.0;

    // 水平中线
    _drawDashedLine(canvas, paint,
        Offset(0, size.height / 2), Offset(size.width, size.height / 2),
        dashWidth, dashSpace);
    // 垂直中线
    _drawDashedLine(canvas, paint,
        Offset(size.width / 2, 0), Offset(size.width / 2, size.height),
        dashWidth, dashSpace);
  }

  void _drawDashedLine(Canvas canvas, Paint paint,
      Offset start, Offset end, double dashWidth, double dashSpace) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = sqrt(dx * dx + dy * dy);
    final count = (distance / (dashWidth + dashSpace)).floor();

    for (int i = 0; i < count; i++) {
      final startOffset = Offset(
        start.dx + (dx / distance) * i * (dashWidth + dashSpace),
        start.dy + (dy / distance) * i * (dashWidth + dashSpace),
      );
      final endOffset = Offset(
        start.dx + (dx / distance) * (i * (dashWidth + dashSpace) + dashWidth),
        start.dy + (dy / distance) * (i * (dashWidth + dashSpace) + dashWidth),
      );
      canvas.drawLine(startOffset, endOffset, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 字符练习信息
class _CharPracticeInfo {
  final String character;
  double totalConfidence;
  int count;
  int correctionCount;
  double avgConfidence = 0;

  _CharPracticeInfo({
    required this.character,
    required this.totalConfidence,
    required this.count,
    required this.correctionCount,
  });
}
