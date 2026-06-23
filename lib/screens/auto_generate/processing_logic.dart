import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../models/project.dart';
import '../../models/segmented_character.dart';
import '../../services/image_processor.dart';
import '../../services/recognition_service.dart';
import '../../services/app_config_service.dart';
import '../../services/correction_learning_service.dart';

/// 处理结果
class ProcessingResult {
  final List<Uint8List> cells;
  final Map<int, String> charAssignments;
  final Set<int> aiRecognized;
  final Set<int> failedRecognition;
  final Map<int, double> confidenceMap;
  /// v5.1.0: 每个字符的 Top-N 候选列表
  final Map<int, List<String>> topCandidates;
  /// v5.1.0: 分割后的字符元数据
  final List<SegmentedCharacter>? segmentedCharacters;
  final String? error;
  final String? errorStatus;

  const ProcessingResult({
    required this.cells,
    required this.charAssignments,
    required this.aiRecognized,
    required this.failedRecognition,
    this.confidenceMap = const {},
    this.topCandidates = const {},
    this.segmentedCharacters,
    this.error,
    this.errorStatus,
  });

  bool get hasError => error != null;
}

/// 默认字符池
List<String> getDefaultChars() {
  final chars = <String>[];
  for (int i = 0x4E00; i <= 0x4E3F; i++) {
    chars.add(String.fromCharCode(i));
  }
  for (int c = 0x21; c <= 0x7E; c++) {
    chars.add(String.fromCharCode(c));
  }
  return chars;
}

/// 将处理错误映射为用户友好的消息
Map<String, String> mapProcessingError(String errorStr) {
  if (errorStr.contains('CloudAuthException') ||
      errorStr.contains('认证失败') ||
      errorStr.contains('401') ||
      errorStr.contains('403')) {
    return {
      'message': '云端识别认证失败：API Key 无效或已过期。\n请到「设置 → 云端识别配置」中重新填写 API Key，或切换为本地识别。',
      'status': '认证失败',
    };
  } else if (errorStr.contains('TimeoutException') ||
      errorStr.contains('timeout') ||
      errorStr.contains('超时')) {
    return {
      'message': '请求超时，服务器响应时间过长。\n请检查网络状况后重试，或切换到本地识别（无需网络）。',
      'status': '请求超时',
    };
  } else if (errorStr.contains('429') || errorStr.contains('rate') ||
      errorStr.contains('限流') || errorStr.contains('too many')) {
    return {
      'message': '云端识别请求频率过高，已被限流。\n请稍等片刻后重试，或切换到本地识别。',
      'status': '请求限流',
    };
  } else if (errorStr.contains('CloudNetworkException') ||
      errorStr.contains('SocketException') ||
      errorStr.contains('网络连接失败') ||
      errorStr.contains('Connection')) {
    return {
      'message': '网络连接失败，请检查网络连接后重试。\n您也可以切换到本地识别（无需网络）。',
      'status': '网络错误',
    };
  }
  return {
    'message': '处理出错：$errorStr',
    'status': '处理失败',
  };
}

/// 获取识别统计信息
Map<String, int> getRecognitionStats(
  int cellCount,
  Map<int, String> charAssignments,
  Set<int> aiRecognized,
  Set<int> failedRecognition,
  Map<int, String> editedAssignments,
) {
  int ai = 0, edited = 0, fallback = 0;
  for (int i = 0; i < cellCount; i++) {
    if (editedAssignments.containsKey(i)) {
      edited++;
    } else if (aiRecognized.contains(i)) {
      ai++;
    } else if (charAssignments.containsKey(i)) {
      fallback++;
    }
  }
  return {
    'total': cellCount,
    'aiRecognized': ai,
    'userEdited': edited,
    'fallbackAssigned': fallback,
  };
}

/// 运行完整的处理流水线：分割字符 → AI 识别 → 分配字符
Future<ProcessingResult> runProcessing(
  Uint8List imageBytes,
  ProcessingParams params, {
  required void Function(double progress, String status) onProgress,
}) async {
  final defaultCharacters = getDefaultChars();

  onProgress(0.1, '正在分割字符...');
  await Future.delayed(const Duration(milliseconds: 300));

  // v5.1.0: 使用增强分割获取元数据
  final segmentedChars = ImageProcessor.segmentCharactersEnhanced(imageBytes, params);
  final cells = segmentedChars.map((c) => c.imageBytes).toList();

  if (cells.isEmpty) {
    return ProcessingResult(
      cells: [],
      charAssignments: {},
      aiRecognized: {},
      failedRecognition: {},
      error: '未识别到字符，请尝试以下方法：\n'
          '• 确保光线充足，避免反光和阴影\n'
          '• 使用黑色签字笔或中性笔书写\n'
          '• 在白色纸张上书写，字迹清晰工整\n'
          '• 拍照时保持手机稳定，对焦清晰\n'
          '• 调整拍摄角度，使纸张充满画面',
      errorStatus: '分割失败',
    );
  }

  onProgress(0.3, '已分割 ${cells.length} 个字符，正在识别...');
  await Future.delayed(const Duration(milliseconds: 200));

  final charAssignments = <int, String>{};
  final aiRecognized = <int>{};
  final failedRecognition = <int>{};

  final recognitionService = RecognitionService.instance;
  final batchResults = await recognitionService.recognizeBatch(
    cells,
    onProgress: (completed, total) {
      final recognitionProgress = 0.3 + (completed / total) * 0.5;
      onProgress(recognitionProgress, '正在识别字符 $completed/$total...');
    },
  );

  for (int i = 0; i < batchResults.length; i++) {
    if (batchResults[i] != null) {
      charAssignments[i] = batchResults[i]!;
      aiRecognized.add(i);
    } else {
      failedRecognition.add(i);
    }
  }

  // 为未识别的字符分配默认字符
  int fallbackIndex = 0;
  for (int i = 0; i < cells.length; i++) {
    if (!charAssignments.containsKey(i)) {
      while (fallbackIndex < defaultCharacters.length &&
          charAssignments.containsValue(defaultCharacters[fallbackIndex])) {
        fallbackIndex++;
      }
      if (fallbackIndex < defaultCharacters.length) {
        charAssignments[i] = defaultCharacters[fallbackIndex];
        fallbackIndex++;
      }
    }
  }

  // 构建置信度映射（索引 → 置信度 0.0~1.0）
  final confidenceMap = <int, double>{};
  for (int i = 0; i < cells.length; i++) {
    if (aiRecognized.contains(i)) {
      confidenceMap[i] = RecognitionService.getConfidenceForImage(cells[i]);
    } else if (failedRecognition.contains(i)) {
      confidenceMap[i] = 0.3; // 识别失败的低置信度
    }
  }

  // v5.1.0: 获取 Top-N 候选列表
  final topCandidates = RecognitionService.getBatchTopCandidates(cells, n: 3);

  // v5.1.0: 应用修正学习 — 低置信度结果尝试修正
  for (final i in aiRecognized) {
    final conf = confidenceMap[i] ?? 0.7;
    if (conf < 0.8 && charAssignments[i] != null) {
      final correction = await CorrectionLearningService.instance.findCorrection(
        recognizedChar: charAssignments[i]!,
        confidence: conf,
        imageWidth: segmentedChars[i].originalWidth,
        imageHeight: segmentedChars[i].originalHeight,
      );
      if (correction != null && correction != charAssignments[i]) {
        debugPrint('修正学习: 字符$i "${charAssignments[i]}" → "$correction"');
        charAssignments[i] = correction;
      }
    }
  }

  onProgress(1.0, '识别完成');

  return ProcessingResult(
    cells: cells,
    charAssignments: charAssignments,
    aiRecognized: aiRecognized,
    failedRecognition: failedRecognition,
    confidenceMap: confidenceMap,
    topCandidates: topCandidates,
    segmentedCharacters: segmentedChars,
  );
}
