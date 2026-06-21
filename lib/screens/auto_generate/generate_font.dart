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
      // 外层超时保护：单字符最多 20 秒
      final contours = await ImageProcessor.extractContours(
        cells[i], params,
        timeout: const Duration(seconds: 15),
      ).timeout(const Duration(seconds: 20), onTimeout: () {
        throw TimeoutException('字符 $char 处理超时');
      });

      final glyph = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
        contours: contours,
      );
      glyph.advanceWidth = glyph.calculateAdvanceWidth();
      project.glyphs[char] = glyph;
    } catch (e) {
      // 单个字符处理失败时继续处理其他字符
      print('[字体生成] 字符 "$char" 处理失败，跳过: $e');
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
