import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import '../screens/auto_generate/generate_font.dart';
import 'storage_service.dart';

/// 字体生成服务 — 管理生成生命周期，支持后台运行
/// 单例模式，生成过程独立于屏幕生命周期
class GenerationService {
  static const String _generatingProjectIdKey = 'generating_project_id';
  static final GenerationService _instance = GenerationService._();
  factory GenerationService() => _instance;
  GenerationService._();

  // 内存中的生成状态
  bool _isGenerating = false;
  double _progress = 0.0;
  String _status = '';
  String? _currentProjectId;
  int _totalChars = 0;
  Completer<bool>? _generationCompleter;

  // UI 可观察的状态
  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier('');
  final ValueNotifier<bool> isGeneratingNotifier = ValueNotifier(false);

  bool get isGenerating => _isGenerating;
  double get progress => _progress;
  String get status => _status;
  String? get currentProjectId => _currentProjectId;
  int get totalChars => _totalChars;

  /// 初始化：从存储中恢复生成状态
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentProjectId = prefs.getString(_generatingProjectIdKey);
    if (_currentProjectId != null) {
      // 标记有项目正在生成（但实际生成已中断，需要用户手动恢复）
      _status = '等待继续生成...';
      statusNotifier.value = _status;
    }
  }

  /// 开始或恢复字体生成
  Future<bool> startGeneration({
    required List<Uint8List> cells,
    required Map<int, String> finalAssignments,
    required ProcessingParams params,
    required Uint8List sourceImage,
    String? existingProjectId,
    void Function(FontProject)? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_isGenerating) {
      debugPrint('[GenerationService] 已有生成任务在运行');
      return false;
    }

    _isGenerating = true;
    _progress = 0.0;
    _status = '开始生成...';
    _totalChars = finalAssignments.length;
    isGeneratingNotifier.value = true;
    progressNotifier.value = 0.0;
    statusNotifier.value = _status;

    _generationCompleter = Completer<bool>();

    try {
      final project = await generateFontFromCells(
        cells,
        finalAssignments,
        params,
        sourceImage,
        existingProjectId: existingProjectId,
        onProgress: (p, s) {
          _progress = p;
          _status = s;
          progressNotifier.value = p;
          statusNotifier.value = s;
        },
        shouldCancel: () => !_isGenerating,
      );

      if (project != null) {
        _currentProjectId = project.id;
        await _saveGeneratingProjectId(project.id);
        _progress = 1.0;
        _status = '生成完成！';
        progressNotifier.value = 1.0;
        statusNotifier.value = _status;
        onComplete?.call(project);
        _generationCompleter?.complete(true);
      } else {
        _status = '生成取消';
        statusNotifier.value = _status;
        _generationCompleter?.complete(false);
      }
    } catch (e) {
      _status = '生成失败: $e';
      statusNotifier.value = _status;
      onError?.call(e.toString());
      _generationCompleter?.completeError(e);
    } finally {
      _isGenerating = false;
      isGeneratingNotifier.value = false;
      await _clearGeneratingProjectId();
    }

    return _generationCompleter?.future ?? Future.value(false);
  }

  /// 取消当前生成
  Future<void> cancelGeneration() async {
    if (!_isGenerating) return;
    _isGenerating = false;
    isGeneratingNotifier.value = false;
    _status = '已取消';
    statusNotifier.value = _status;
    await _clearGeneratingProjectId();
  }

  /// 检查是否有项目正在生成
  Future<bool> hasGeneratingProject() async {
    final prefs = await SharedPreferences.getInstance();
    final projectId = prefs.getString(_generatingProjectIdKey);
    if (projectId == null) return false;
    final project = await StorageService.loadProject(projectId);
    return project != null;
  }

  /// 获取正在生成的项目
  Future<FontProject?> getGeneratingProject() async {
    final prefs = await SharedPreferences.getInstance();
    final projectId = prefs.getString(_generatingProjectIdKey);
    if (projectId == null) return null;
    return StorageService.loadProject(projectId);
  }

  /// 保存正在生成的项目 ID
  Future<void> _saveGeneratingProjectId(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_generatingProjectIdKey, projectId);
  }

  /// 清除正在生成的项目 ID
  Future<void> _clearGeneratingProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_generatingProjectIdKey);
    _currentProjectId = null;
  }

  /// 释放资源
  void dispose() {
    progressNotifier.dispose();
    statusNotifier.dispose();
    isGeneratingNotifier.dispose();
  }
}
