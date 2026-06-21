import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../services/image_processor.dart';
import '../../services/storage_service.dart';
import '../../services/recognition_service.dart';
import '../../services/app_config_service.dart';
import '../widgets/edit_character_dialog.dart';
import 'cell_result.dart';
import '../processing_screen.dart';
import 'semaphore.dart';

/// ProcessingScreen 的业务逻辑 mixin
///
/// 包含图片处理、AI 识别、置信度计算、导航等方法。
/// 字段使用非 private 命名以便跨文件访问。
mixin ProcessingLogic on TickerProviderStateMixin<ProcessingScreen> {
  ProcessingParams params = ProcessingParams();
  List<Uint8List> processedCells = [];
  bool isProcessing = true;
  final Set<int> selectedCells = {};
  Timer? debounceTimer;

  // 参数历史栈（撤销/重做支持）
  final List<ProcessingParams> _undoStack = [];
  final List<ProcessingParams> _redoStack = [];
  static const int _maxHistorySize = 20;

  // 参数预设
  static final Map<String, ProcessingParams> _presets = {
    '默认': ProcessingParams(),
    '粗笔': ProcessingParams(
      threshold: 0.45, strokeWidth: 1.5, smoothness: 0.2,
      erosion: 0, dilation: 2, contrast: 1.2,
    ),
    '细笔': ProcessingParams(
      threshold: 0.55, strokeWidth: 0.8, smoothness: 0.4,
      erosion: 2, dilation: 0, contrast: 1.5,
    ),
    '铅笔': ProcessingParams(
      threshold: 0.6, strokeWidth: 0.7, smoothness: 0.5,
      erosion: 1, dilation: 0, contrast: 2.0,
    ),
    '马克笔': ProcessingParams(
      threshold: 0.4, strokeWidth: 2.0, smoothness: 0.1,
      erosion: 0, dilation: 3, contrast: 1.0,
    ),
  };

  /// 获取预设名称列表
  List<String> get presetNames => _presets.keys.toList();

  /// 应用预设
  void applyPreset(String name) {
    final preset = _presets[name];
    if (preset != null) {
      onParamsChanged(preset);
    }
  }

  /// 是否可以撤销
  bool get canUndo => _undoStack.isNotEmpty;

  /// 是否可以重做
  bool get canRedo => _redoStack.isNotEmpty;

  /// 撤销参数修改
  void undo() {
    if (!canUndo) return;
    _redoStack.add(params);
    final previous = _undoStack.removeLast();
    setState(() {
      params = previous;
    });
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () {
      processImages();
    });
  }

  /// 重做参数修改
  void redo() {
    if (!canRedo) return;
    _undoStack.add(params);
    final next = _redoStack.removeLast();
    setState(() {
      params = next;
    });
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () {
      processImages();
    });
  }

  // AI recognition
  final RecognitionService recognitionService = RecognitionService.instance;
  bool isRecognizing = false;
  int recognizedCount = 0;
  int totalCount = 0;
  bool useCloudRecognition = false;

  // 逐字识别结果
  final Map<int, CellResult> cellResults = {};

  // 动画：每个格子完成时的弹跳动画
  final Map<int, AnimationController> bounceControllers = {};

  // 全部完成的庆祝动画
  AnimationController? celebrationController;
  Animation<double>? celebrationAnimation;

  // 是否显示完成汇总
  bool showSummary = false;

  // 任务代数计数器，用于取消过期的异步任务
  int generation = 0;

  // Character assignment
  final List<String> defaultCharacters = getDefaultChars();
  final Map<int, String> charAssignments = {};

  /// 统计信息
  int get highConfidenceCount =>
      cellResults.values.where((r) => r.confidence == ConfidenceLevel.high).length;
  int get needConfirmCount =>
      cellResults.values.where((r) => r.confidence != ConfidenceLevel.high).length;
  int get recognizedSuccessCount =>
      cellResults.values.where((r) => r.status == CellStatus.recognized).length;

  static List<String> getDefaultChars() {
    final chars = <String>[];
    for (int i = 0x4E00; i <= 0x4E3F; i++) {
      chars.add(String.fromCharCode(i));
    }
    for (int c = 0x21; c <= 0x7E; c++) {
      chars.add(String.fromCharCode(c));
    }
    return chars;
  }

  Future<void> loadParams() async {
    final config = AppConfigService.instance;
    params = ProcessingParams(
      threshold: await config.getThreshold(),
      contrast: await config.getContrast(),
      smoothness: await config.getSmoothness(),
      strokeWidth: await config.getStrokeWidth(),
    );
    loadUseCloudSetting();
  }

  /// 读取 OCR 识别模式设置
  Future<void> loadUseCloudSetting() async {
    final useCloud = await recognitionService.getUseCloud();
    if (mounted) {
      setState(() => useCloudRecognition = useCloud);
    }
  }

  void processImages() {
    final gen = ++generation; // 递增代数，取消旧任务
    setState(() => isProcessing = true);

    Future.microtask(() async {
      final allCells = <Uint8List>[];
      for (final img in widget.sourceImages) {
        final cells = ImageProcessor.segmentCharacters(img, params);
        allCells.addAll(cells);
      }

      // 代数不匹配，旧任务已过期
      if (!mounted || generation != gen) return;

      setState(() {
        processedCells = allCells;
        isProcessing = false;
        // 初始化所有格子为 pending 状态
        cellResults.clear();
        for (int i = 0; i < allCells.length; i++) {
          cellResults[i] = const CellResult(status: CellStatus.pending);
        }
        showSummary = false;
      });

      // 逐个识别字符
      await recognizeCharacters(allCells, gen);
    });
  }

  /// 根据识别结果和目标字符计算置信度
  ConfidenceLevel calcConfidence(int index, String? recognized) {
    if (recognized == null) return ConfidenceLevel.low;
    final charset = widget.charset;
    if (charset != null && charset.isNotEmpty && index < charset.length) {
      // 标准字表模式：比较识别结果与目标字符
      if (recognized == charset[index]) return ConfidenceLevel.high;
      return ConfidenceLevel.medium; // 识别到文字但不匹配
    }
    // 自由模式：只要识别到就算中等置信度
    return ConfidenceLevel.medium;
  }

  Future<void> recognizeCharacters(List<Uint8List> cells, [int? gen]) async {
    if (cells.isEmpty) return;
    if (gen != null && generation != gen) return; // 代数不匹配，取消

    final charset = widget.charset;
    final useStandardCharset = charset != null && charset.isNotEmpty;

    if (mounted) {
      setState(() {
        isRecognizing = true;
        recognizedCount = 0;
        totalCount = cells.length;
        showSummary = false;
      });
    }

    // 逐个识别，带并发控制，每完成一个就更新 UI
    const maxConcurrent = 3;
    final semaphore = Semaphore(maxConcurrent);
    bool anyRecognized = false;
    int completed = 0;

    final futures = <Future>[];
    for (int i = 0; i < cells.length; i++) {
      futures.add(() async {
        await semaphore.acquire();
        try {
          // 代数不匹配，跳过
          if (gen != null && generation != gen) return;

          if (mounted) {
            setState(() {
              cellResults[i] = const CellResult(status: CellStatus.recognizing);
            });
          }

          String? result;
          try {
            result = await recognitionService.recognizeCharacter(cells[i]);
          } catch (_) {
            result = null;
          }

          // 代数不匹配，丢弃结果
          if (gen != null && generation != gen) return;

          final confidence = calcConfidence(i, result);
          final status = result != null ? CellStatus.recognized : CellStatus.failed;

          if (mounted && (gen == null || generation == gen)) {
            setState(() {
              if (result != null) {
                charAssignments[i] = result;
                anyRecognized = true;
              }
              cellResults[i] = CellResult(
                character: result,
                status: status,
                confidence: confidence,
              );
              completed++;
              recognizedCount = completed;
            });
          }

          // 触发弹跳动画
          if (gen == null || generation == gen) {
            triggerBounce(i);
          }
        } finally {
          semaphore.release();
        }
      }());
    }

    await Future.wait(futures);

    // 代数不匹配，取消后续逻辑
    if (gen != null && generation != gen) return;

    // 标准字表模式：用字表顺序补齐未识别的格子
    if (useStandardCharset) {
      for (int i = 0; i < cells.length; i++) {
        if (!charAssignments.containsKey(i)) {
          if (i < charset.length) {
            charAssignments[i] = charset[i];
            cellResults[i] = CellResult(
              character: charset[i],
              status: CellStatus.recognized,
              confidence: ConfidenceLevel.low, // 字表补齐，非实际识别
            );
          }
        }
      }
    } else {
      // 自由模式：如果识别失败，用默认字符凑数
      if (!anyRecognized) {
        assignFallbackCharacters(cells.length);
      } else {
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
      }
    }

    // 最终检查代数
    if (gen != null && generation != gen) return;

    if (mounted) {
      setState(() {
        isRecognizing = false;
        showSummary = true;
      });
      celebrationController?.forward(from: 0);
    }
  }

  void assignFallbackCharacters(int count) {
    for (int i = 0; i < count && i < defaultCharacters.length; i++) {
      charAssignments[i] = defaultCharacters[i];
    }
  }

  /// 触发格子弹跳动画
  void triggerBounce(int index) {
    bounceControllers[index]?.dispose();
    final controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    bounceControllers[index] = controller;
    // AnimatedBuilder 会监听 controller 并局部刷新对应格子，无需全局 setState
    controller.forward();
  }

  void onParamsChanged(ProcessingParams newParams) {
    // 保存当前参数到撤销栈
    if (params.threshold != newParams.threshold ||
        params.contrast != newParams.contrast ||
        params.smoothness != newParams.smoothness ||
        params.strokeWidth != newParams.strokeWidth ||
        params.erosion != newParams.erosion ||
        params.dilation != newParams.dilation ||
        params.invertColors != newParams.invertColors) {
      _undoStack.add(params);
      if (_undoStack.length > _maxHistorySize) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear(); // 新操作清空重做栈
    }

    setState(() {
      params = newParams;
    });
    final config = AppConfigService.instance;
    config.setThreshold(newParams.threshold);
    config.setContrast(newParams.contrast);
    config.setSmoothness(newParams.smoothness);
    config.setStrokeWidth(newParams.strokeWidth);
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 500), () {
      processImages();
    });
  }

  Future<void> proceedToPreview() async {
    if (processedCells.isEmpty) {
      WFSnackBar.show(context, '没有识别到字符，请调整参数后重试');
      return;
    }

    final project = FontProject(
      id: StorageService.generateId(),
      name: '我的手写字体',
      params: params,
    );

    try {
      for (int i = 0; i < processedCells.length; i++) {
        final char = charAssignments[i];
        if (char == null) continue;

        final contours = await ImageProcessor.extractContours(
          processedCells[i],
          params,
        );

        if (!mounted) return;

        project.glyphs[char] = GlyphData(
          character: char,
          unicode: char.codeUnitAt(0),
          contours: contours,
          advanceWidth: 500,
        );
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '处理字符轮廓失败: $e');
      }
      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushNamed('/preview', arguments: {'project': project});
  }

  /// 跳转到字符编辑器，从第一个需确认的字符开始
  void proceedToEditor() {
    // 找到第一个需确认（低置信度或失败）的字符索引
    int startIndex = 0;
    for (int i = 0; i < processedCells.length; i++) {
      final result = cellResults[i];
      if (result != null && result.confidence != ConfidenceLevel.high) {
        startIndex = i;
        break;
      }
    }
    proceedToPreview(); // 暂时直接跳转预览，后续可改为跳转到编辑器指定位置
  }

  /// 弹出编辑对话框（带图片预览）
  void showEditDialog(int index) {
    final result = cellResults[index];
    final confidence = result?.confidence ?? ConfidenceLevel.low;

    showDialog(
      context: context,
      builder: (context) {
        return EditCharacterDialog(
          index: index,
          imageBytes: processedCells[index],
          currentChar: charAssignments[index],
          confidence: confidence,
          onConfirm: (text) {
            setState(() {
              charAssignments[index] = text;
              cellResults[index] = CellResult(
                character: text,
                status: CellStatus.recognized,
                confidence: ConfidenceLevel.high, // 用户手动修正 = 高置信
              );
            });
          },
          onMarkCorrect: charAssignments[index] != null
              ? () {
                  setState(() {
                    cellResults[index] = CellResult(
                      character: charAssignments[index],
                      status: CellStatus.recognized,
                      confidence: ConfidenceLevel.high,
                    );
                  });
                }
              : null,
        );
      },
    );
  }
}
