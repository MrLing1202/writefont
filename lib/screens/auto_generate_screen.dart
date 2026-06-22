import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/app_config_service.dart';
import '../theme/app_theme.dart';
import 'auto_generate/processing_view.dart';
import 'auto_generate/confirm_view.dart';
import 'auto_generate/error_view.dart';
import 'auto_generate/quick_edit_dialog.dart';
import '../services/recognition_service.dart';
import 'auto_generate/processing_logic.dart';
import 'auto_generate/generate_font.dart';
import 'auto_generate/character_ops.dart';

/// 一键生成页面
/// 拍照后自动完成：分割字符 → AI 识别 → 确认字符 → 生成字体 → 跳转预览
class AutoGenerateScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const AutoGenerateScreen({
    super.key,
    required this.imageBytes,
  });

  @override
  State<AutoGenerateScreen> createState() => _AutoGenerateScreenState();
}

class _AutoGenerateScreenState extends State<AutoGenerateScreen>
    with SingleTickerProviderStateMixin {
  // 处理阶段
  String _status = '准备中...';
  double _progress = 0.0;
  bool _hasError = false;
  String? _errorMessage;

  // 处理结果
  List<Uint8List> _cells = [];
  final Map<int, String> _charAssignments = {};

  // 确认模式相关状态
  bool _isConfirming = false;
  bool _isGenerating = false;
  final Map<int, String> _editedAssignments = {};
  final Set<int> _aiRecognized = {};
  final Set<int> _failedRecognition = {};

  // 处理参数
  ProcessingParams _params = ProcessingParams();

  // 防止 _startProcessing 重入
  bool _isStartProcessingRunning = false;

  // 取消标志
  bool _cancelled = false;

  // 动画
  AnimationController? _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _startProcessing();
  }

  @override
  void dispose() { _animController?.dispose(); super.dispose(); }

  /// 取消处理
  void _cancelProcessing() {
    _cancelled = true;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 获取当前字符分配（合并 AI 识别和用户修正）
  String? _getCharAt(int index) {
    if (_editedAssignments.containsKey(index)) {
      return _editedAssignments[index];
    }
    return _charAssignments[index];
  }

  bool _isAiRecognized(int index) => _aiRecognized.contains(index);
  bool _isUserEdited(int index) => _editedAssignments.containsKey(index);
  bool _isFailedRecognition(int index) =>
      _failedRecognition.contains(index) && !_editedAssignments.containsKey(index);

  /// 重试单个字符的识别
  Future<void> _retryRecognition(int index) async {
    if (!mounted) return;
    if (index >= _cells.length) return;
    setState(() => _status = '正在重新识别第 ${index + 1} 个字符...');
    try {
      final result = await retryCharacterRecognition(_cells[index])
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('识别超时');
      });
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        setState(() {
          _charAssignments[index] = result;
          _aiRecognized.add(index);
          _failedRecognition.remove(index);
          _editedAssignments.remove(index);
          _status = '识别完成';
        });
      } else {
        setState(() => _status = '识别完成');
        if (mounted) {
          WFSnackBar.show(context, '未能识别该字符，请手动修改');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = '识别完成');
        WFSnackBar.error(context, '重试失败: $e');
      }
    }
  }

  Future<void> _startProcessing() async {
    if (_isStartProcessingRunning) return;
    _isStartProcessingRunning = true;
    try {
      final config = AppConfigService.instance;
      _params = ProcessingParams(
        threshold: await config.getThreshold(),
        contrast: await config.getContrast(),
        smoothness: await config.getSmoothness(),
        strokeWidth: await config.getStrokeWidth(),
      );

      if (!mounted) return;
      setState(() {
        _status = '正在分割字符...'; _progress = 0.1;
        _isConfirming = false; _isGenerating = false;
        _editedAssignments.clear(); _aiRecognized.clear(); _failedRecognition.clear();
      });

      final result = await runProcessing(
        widget.imageBytes,
        _params,
        onProgress: (progress, status) {
          if (mounted && !_cancelled) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              _status = status;
            });
          }
        },
      );

      // 如果已取消，不处理结果
      if (_cancelled) return;

      if (result.hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = result.error ?? '未知错误';
          _status = result.errorStatus ?? '处理失败';
        });
        return;
      }

      setState(() {
        _cells = result.cells;
        _charAssignments..clear()..addAll(result.charAssignments);
        _aiRecognized..clear()..addAll(result.aiRecognized);
        _failedRecognition..clear()..addAll(result.failedRecognition);
        _progress = 1.0; _status = '识别完成'; _isConfirming = true;
      });
    } catch (e) {
      if (mounted) {
        final mapped = mapProcessingError(e.toString());
        setState(() {
          _hasError = true;
          _errorMessage = mapped['message'] ?? '未知错误';
          _status = mapped['status'] ?? '处理失败';
        });
      }
    } finally {
      _isStartProcessingRunning = false;
    }
  }

  /// 打开字符编辑对话框
  void _editCharacter(int index) {
    final currentChar = _getCharAt(index) ?? '';
    if (currentChar.isEmpty) return;
    showCharacterEditDialog(
      context,
      currentChar: currentChar,
      projectId: '',
      onChanged: (newChar) => setState(() => _editedAssignments[index] = newChar),
      onDeleted: () => setState(() {
        _charAssignments.remove(index);
        _editedAssignments.remove(index);
      }),
    );
  }

  /// 快速修改字符
  void _quickEditCharacter(int index) async {
    final currentChar = _getCharAt(index) ?? '';
    final newChar = await showQuickEditCharacterDialog(
      context,
      cellImage: _cells[index],
      index: index,
      currentChar: currentChar,
    );
    if (newChar != null && newChar.isNotEmpty && newChar != currentChar) {
      if (!mounted) return;
      setState(() {
        _editedAssignments[index] = newChar;
      });
      // 存入用户反馈学习系统，提升后续识别率
      RecognitionService.correctRecognition(_cells[index], newChar);
    }
  }

  /// 确认生成字体
  Future<void> _confirmAndGenerate() async {
    setState(() { _isGenerating = true; _progress = 0.0; _status = '正在生成字体...'; });
    try {
      final finalAssignments = <int, String>{};
      for (int i = 0; i < _cells.length; i++) {
        final char = _getCharAt(i);
        if (char != null && char.isNotEmpty) finalAssignments[i] = char;
      }
      if (!mounted) return;
      final project = await generateFontFromCells(
        _cells, finalAssignments, _params, widget.imageBytes,
        onProgress: (p, s) { if (mounted) setState(() { _progress = p; _status = s; }); },
      );
      if (project != null && mounted) {
        Navigator.of(context).pushReplacementNamed('/preview', arguments: {'project': project});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false; _isConfirming = true; _hasError = true;
          _errorMessage = '生成字体出错：请检查字符数据是否完整，或尝试重新识别。\n错误详情：$e';
          _status = '生成失败';
        });
      }
    }
  }

  /// 重置并重新识别
  void _resetAndReidentify() {
    setState(() {
      _charAssignments.clear(); _editedAssignments.clear();
      _aiRecognized.clear(); _failedRecognition.clear();
      _isConfirming = false; _hasError = false; _errorMessage = null; _progress = 0.0;
    });
    _startProcessing();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: _isConfirming ? '确认字符' : '一键生成',
      ),
      body: _hasError
          ? ErrorView(
              status: _status,
              errorMessage: _errorMessage,
              hasRecognizedChars: _charAssignments.isNotEmpty || _editedAssignments.isNotEmpty,
              onReturnConfirm: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = null;
                  _isConfirming = true;
                });
              },
              onReidentify: _resetAndReidentify,
              onRetry: _resetAndReidentify,
              onPop: () => Navigator.of(context).pop(),
              colorScheme: colorScheme,
            )
          : _isConfirming
              ? ConfirmView(
                  cells: _cells,
                  getCharAt: _getCharAt,
                  isAiRecognized: _isAiRecognized,
                  isUserEdited: _isUserEdited,
                  isFailedRecognition: _isFailedRecognition,
                  isGenerating: _isGenerating,
                  progress: _progress,
                  status: _status,
                  stats: getRecognitionStats(
                    _cells.length, _charAssignments, _aiRecognized,
                    _failedRecognition, _editedAssignments,
                  ),
                  onQuickEdit: _quickEditCharacter,
                  onRetryRecognition: _retryRecognition,
                  onReidentify: _resetAndReidentify,
                  onConfirmGenerate: _confirmAndGenerate,
                  colorScheme: colorScheme,
                )
              : ProcessingView(
                  imageBytes: widget.imageBytes,
                  progress: _progress,
                  status: _status,
                  colorScheme: colorScheme,
                  onCancel: _isConfirming ? null : _cancelProcessing,
                ),
    );
  }
}
