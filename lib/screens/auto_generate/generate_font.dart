import 'dart:async';
import 'dart:typed_data';
import '../../models/project.dart';
import '../../services/image_processor.dart';
import '../../services/storage_service.dart';

/// 从已确认的字符单元格生成字体项目
Future<FontProject?> generateFontFromCells(
  List<Uint8List> cells,
  Map<int, String> finalAssignments,
  ProcessingParams params,
  Uint8List sourceImage, {
  required void Function(double progress, String status) onProgress,
}) async {
  await Future.delayed(const Duration(milliseconds: 200));

  final project = FontProject(
    id: StorageService.generateId(),
    name: '一键生成字体',
    params: params,
    sourceImages: [sourceImage],
  );

  final total = finalAssignments.length;
  int completed = 0;

  for (final entry in finalAssignments.entries) {
    final i = entry.key;
    final char = entry.value;

    // 检查索引是否有效
    if (i < 0 || i >= cells.length) {
      onProgress(completed / total, '跳过无效字符 $char');
      continue;
    }

    try {
      // Isolate 轮廓提取（后台线程，不阻塞 UI）
      List<Contour> contours;
      try {
        contours = await ImageProcessor.extractContours(
          cells[i], params,
          timeout: const Duration(seconds: 15),
        ).timeout(const Duration(seconds: 20), onTimeout: () {
          throw TimeoutException('字符 $char Isolate超时');
        });
      } catch (e) {
        // Isolate 超时或失败时，降级为同步轮廓提取（不丢字符）
        print('[字体生成] 字符 "$char" Isolate 失败，降级同步提取: $e');
        contours = ImageProcessor.extractContoursSync(cells[i], params);
      }

      final glyph = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
        contours: contours,
      );
      glyph.advanceWidth = glyph.calculateAdvanceWidth();
      project.glyphs[char] = glyph;
    } catch (e) {
      // 同步提取也失败时记录错误，但仍继续处理其他字符
      print('[字体生成] 字符 "$char" 处理失败: $e');
    }

    completed++;
    onProgress(completed / total, '正在生成字体 $completed/$total...');
  }

  if (project.glyphs.isEmpty) {
    return null;
  }

  onProgress(1.0, '生成完成！');
  await Future.delayed(const Duration(milliseconds: 500));

  return project;
}
