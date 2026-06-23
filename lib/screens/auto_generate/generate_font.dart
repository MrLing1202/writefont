import 'dart:async';
import 'dart:typed_data';
import '../../models/project.dart';
import '../../services/image_processor.dart';
import '../../services/storage_service.dart';

/// 从已确认的字符单元格生成字体项目
/// [existingProjectId] 如果提供，则恢复已有项目而非创建新项目
/// 支持增量保存：每生成一个字符就保存到存储，确保进度不丢失
Future<FontProject?> generateFontFromCells(
  List<Uint8List> cells,
  Map<int, String> finalAssignments,
  ProcessingParams params,
  Uint8List sourceImage, {
  required void Function(double progress, String status) onProgress,
  String? existingProjectId,
  bool Function()? shouldCancel,
}) async {
  await Future.delayed(const Duration(milliseconds: 200));

  // 尝试恢复已有项目或创建新项目
  FontProject project;
  Map<int, String> remainingAssignments = finalAssignments;

  if (existingProjectId != null) {
    final existing = await StorageService.getProject(existingProjectId);
    if (existing != null) {
      project = existing;
      // 过滤掉已生成的字符
      remainingAssignments = Map.fromEntries(
        finalAssignments.entries.where((e) => !project.glyphs.containsKey(e.value)),
      );
      onProgress(
        project.glyphs.length / finalAssignments.length,
        '继续生成 ${project.glyphs.length}/${finalAssignments.length}...',
      );
    } else {
      project = FontProject(
        id: existingProjectId,
        name: '一键生成字体',
        params: params,
        sourceImages: [sourceImage],
      );
      // 提前保存项目，确保存在
      await StorageService.saveProject(project);
    }
  } else {
    project = FontProject(
      id: StorageService.generateId(),
      name: '一键生成字体',
      params: params,
      sourceImages: [sourceImage],
    );
    // 提前保存项目，确保存在
    await StorageService.saveProject(project);
  }

  final total = finalAssignments.length;
  int completed = project.glyphs.length;

  for (final entry in remainingAssignments.entries) {
    // 检查是否应取消
    if (shouldCancel != null && shouldCancel()) {
      print('[字体生成] 用户取消生成');
      return null;
    }

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
        // Isolate 超时或失败时，降级为后台 Isolate 提取（不阻塞主线程）
        print('[字体生成] 字符 "$char" Isolate 失败，降级后台提取: $e');
        contours = await ImageProcessor.extractContoursInBackground(cells[i], params)
            .timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('字符 $char 降级提取超时');
        });
      }

      final glyph = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
        contours: contours,
      );
      glyph.advanceWidth = glyph.calculateAdvanceWidth();
      project.glyphs[char] = glyph;

      // 增量保存：每生成一个字符就保存项目
      completed++;
      await StorageService.saveProject(project);
      onProgress(completed / total, '正在生成字体 $completed/$total...');
    } catch (e) {
      // 同步提取也失败时记录错误，但仍继续处理其他字符
      print('[字体生成] 字符 "$char" 处理失败: $e');
      completed++;
      onProgress(completed / total, '字符 "$char" 处理失败，继续...');
    }
  }

  if (project.glyphs.isEmpty) {
    return null;
  }

  onProgress(1.0, '生成完成！');
  await Future.delayed(const Duration(milliseconds: 500));

  // 更新时间戳
  project.updatedAt = DateTime.now();
  await StorageService.saveProject(project);

  return project;
}
