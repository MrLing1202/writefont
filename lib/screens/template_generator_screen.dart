import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 模板类型枚举
enum TemplateType {
  tianzige,   // 田字格
  mizige,     // 米字格
  fangge,     // 方格
  hengxiange, // 横线格
}

/// 格子大小枚举
enum GridSize {
  small,  // 1cm
  medium, // 1.5cm
  large,  // 2cm
}

/// 模板配置
class TemplateConfig {
  final TemplateType type;
  final GridSize gridSize;
  final int charsPerRow;
  final int rows;
  final bool showReference;
  final String referenceChars;

  const TemplateConfig({
    this.type = TemplateType.tianzige,
    this.gridSize = GridSize.medium,
    this.charsPerRow = 10,
    this.rows = 12,
    this.showReference = false,
    this.referenceChars = '',
  });

  TemplateConfig copyWith({
    TemplateType? type,
    GridSize? gridSize,
    int? charsPerRow,
    int? rows,
    bool? showReference,
    String? referenceChars,
  }) {
    return TemplateConfig(
      type: type ?? this.type,
      gridSize: gridSize ?? this.gridSize,
      charsPerRow: charsPerRow ?? this.charsPerRow,
      rows: rows ?? this.rows,
      showReference: showReference ?? this.showReference,
      referenceChars: referenceChars ?? this.referenceChars,
    );
  }

  /// 格子像素大小（按300dpi等效）
  double get cellSizePx {
    switch (gridSize) {
      case GridSize.small:
        return 80;
      case GridSize.medium:
        return 120;
      case GridSize.large:
        return 160;
    }
  }

  String get gridSizeLabel {
    switch (gridSize) {
      case GridSize.small:
        return '小 (1cm)';
      case GridSize.medium:
        return '中 (1.5cm)';
      case GridSize.large:
        return '大 (2cm)';
    }
  }

  String get typeLabel {
    switch (type) {
      case TemplateType.tianzige:
        return '田字格';
      case TemplateType.mizige:
        return '米字格';
      case TemplateType.fangge:
        return '方格';
      case TemplateType.hengxiange:
        return '横线格';
    }
  }
}

/// 模板生成器页面
class TemplateGeneratorScreen extends StatefulWidget {
  const TemplateGeneratorScreen({super.key});

  @override
  State<TemplateGeneratorScreen> createState() => _TemplateGeneratorScreenState();
}

class _TemplateGeneratorScreenState extends State<TemplateGeneratorScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  TemplateConfig _config = const TemplateConfig();
  bool _exporting = false;

  /// 常用汉字集
  static const String _commonChars = '的一是不了人我在有他这中大来上个国'
      '到说们为子和你地出会也时要就可以下'
      '得生着自之年过发后作里用道行所然家'
      '种事成方多经么去法学如都同现当没动';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('模板生成器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exporting ? null : _exportAndShare,
            tooltip: '导出分享',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConfigPanel(theme),
          const Divider(height: 1),
          Expanded(child: _buildPreview()),
        ],
      ),
    );
  }

  /// 配置面板
  Widget _buildConfigPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模板类型
          Row(
            children: [
              const Text('类型: ', style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: SegmentedButton<TemplateType>(
                  segments: const [
                    ButtonSegment(value: TemplateType.tianzige, label: Text('田字格')),
                    ButtonSegment(value: TemplateType.mizige, label: Text('米字格')),
                    ButtonSegment(value: TemplateType.fangge, label: Text('方格')),
                    ButtonSegment(value: TemplateType.hengxiange, label: Text('横线')),
                  ],
                  selected: {_config.type},
                  onSelectionChanged: (v) => setState(() => _config = _config.copyWith(type: v.first)),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 格子大小 + 每行字数
          Row(
            children: [
              const Text('大小: ', style: TextStyle(fontWeight: FontWeight.w600)),
              SegmentedButton<GridSize>(
                segments: const [
                  ButtonSegment(value: GridSize.small, label: Text('小')),
                  ButtonSegment(value: GridSize.medium, label: Text('中')),
                  ButtonSegment(value: GridSize.large, label: Text('大')),
                ],
                selected: {_config.gridSize},
                onSelectionChanged: (v) => setState(() => _config = _config.copyWith(gridSize: v.first)),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 16),
              const Text('列数: ', style: TextStyle(fontWeight: FontWeight.w600)),
              DropdownButton<int>(
                value: _config.charsPerRow,
                items: [8, 10, 12, 14].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                onChanged: (v) => setState(() => _config = _config.copyWith(charsPerRow: v!)),
                isDense: true,
              ),
              const SizedBox(width: 16),
              const Text('行数: ', style: TextStyle(fontWeight: FontWeight.w600)),
              DropdownButton<int>(
                value: _config.rows,
                items: [8, 10, 12, 15, 20].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                onChanged: (v) => setState(() => _config = _config.copyWith(rows: v!)),
                isDense: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 参考字开关
          Row(
            children: [
              Switch(
                value: _config.showReference,
                onChanged: (v) => setState(() {
                  _config = _config.copyWith(
                    showReference: v,
                    referenceChars: v ? _commonChars : '',
                  );
                }),
              ),
              const SizedBox(width: 4),
              const Text('显示参考字', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 16),
              if (_config.showReference)
                Expanded(
                  child: Text(
                    '常用汉字前${_config.charsPerRow * _config.rows}字',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 预览区域
  Widget _buildPreview() {
    return InteractiveViewer(
      maxScale: 3.0,
      minScale: 0.5,
      child: Center(
        child: RepaintBoundary(
          key: _repaintKey,
          child: CustomPaint(
            size: Size(
              _config.cellSizePx * _config.charsPerRow + 40,
              _config.cellSizePx * _config.rows + 40,
            ),
            painter: TemplatePainter(config: _config),
          ),
        ),
      ),
    );
  }

  /// 导出并分享
  Future<void> _exportAndShare() async {
    setState(() => _exporting = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/writefont_template_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: '手迹造字 - ${_config.typeLabel}模板');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// 模板绘制器
class TemplatePainter extends CustomPainter {
  final TemplateConfig config;

  TemplatePainter({required this.config});

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = config.cellSizePx;
    final padding = 20.0;
    final cols = config.charsPerRow;
    final rows = config.rows;

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFFFFFF8),
    );

    // 绘制格子
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = padding + col * cellSize;
        final y = padding + row * cellSize;
        _drawCell(canvas, x, y, cellSize, row, col);
      }
    }
  }

  /// 绘制单个格子
  void _drawCell(Canvas canvas, double x, double y, double size, int row, int col) {
    final rect = Rect.fromLTWH(x, y, size, size);
    final borderPaint = Paint()
      ..color = Colors.red.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final guidePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // 外框
    canvas.drawRect(rect, borderPaint);

    switch (config.type) {
      case TemplateType.tianzige:
        // 十字虚线
        _drawDashedLine(canvas, Offset(x + size / 2, y), Offset(x + size / 2, y + size), guidePaint);
        _drawDashedLine(canvas, Offset(x, y + size / 2), Offset(x + size, y + size / 2), guidePaint);
        break;

      case TemplateType.mizige:
        // 十字 + 对角线
        _drawDashedLine(canvas, Offset(x + size / 2, y), Offset(x + size / 2, y + size), guidePaint);
        _drawDashedLine(canvas, Offset(x, y + size / 2), Offset(x + size, y + size / 2), guidePaint);
        _drawDashedLine(canvas, Offset(x, y), Offset(x + size, y + size), guidePaint);
        _drawDashedLine(canvas, Offset(x + size, y), Offset(x, y + size), guidePaint);
        break;

      case TemplateType.fangge:
        // 纯方格，无辅助线
        break;

      case TemplateType.hengxiange:
        // 横线格不画竖线，只画横线
        break;
    }

    // 参考字
    if (config.showReference && config.referenceChars.isNotEmpty) {
      final charIndex = row * config.charsPerRow + col;
      if (charIndex < config.referenceChars.length) {
        final char = config.referenceChars[charIndex];
        final tp = TextPainter(
          text: TextSpan(
            text: char,
            style: TextStyle(
              fontSize: size * 0.7,
              color: Colors.grey.withOpacity(0.15),
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(
          canvas,
          Offset(x + (size - tp.width) / 2, y + (size - tp.height) / 2),
        );
      }
    }
  }

  /// 绘制虚线
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = sqrt((dx * dx + dy * dy).abs());
    final count = (length / (dashLength + gapLength)).floor();
    final ux = dx / length;
    final uy = dy / length;

    for (int i = 0; i < count; i++) {
      final s = Offset(start.dx + ux * i * (dashLength + gapLength),
          start.dy + uy * i * (dashLength + gapLength));
      final e = Offset(s.dx + ux * dashLength, s.dy + uy * dashLength);
      canvas.drawLine(s, e, paint);
    }
  }

  @override
  bool shouldRepaint(covariant TemplatePainter oldDelegate) {
    return oldDelegate.config != config;
  }
}
