import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import 'storage_service.dart';

/// 批量处理任务类型
enum BatchTaskType {
  /// 批量导出 TTF
  exportTtf,

  /// 批量删除
  delete,

  /// 批量导出备份 (JSON)
  exportBackup,
}

/// 单个任务的执行结果
class BatchTaskResult {
  final String projectId;
  final String projectName;
  final bool success;
  final String? errorMessage;
  final String? outputPath; // 导出时的输出路径

  const BatchTaskResult({
    required this.projectId,
    required this.projectName,
    required this.success,
    this.errorMessage,
    this.outputPath,
  });
}

/// 批量处理进度信息
class BatchProgress {
  final int total;
  final int completed;
  final int successCount;
  final int failureCount;
  final String? currentProjectName;
  final bool isCancelled;

  const BatchProgress({
    required this.total,
    required this.completed,
    required this.successCount,
    required this.failureCount,
    this.currentProjectName,
    this.isCancelled = false,
  });

  double get progress => total > 0 ? completed / total : 0.0;
  bool get isDone => completed >= total;
  bool get hasFailures => failureCount > 0;
}

/// 批量处理服务
///
/// 提供批量导出 TTF、批量删除、批量导出备份等功能。
/// 支持实时进度回调和任务取消。
class BatchProcessor {
  /// 并发数限制
  static const int _maxConcurrent = 2;

  /// 已取消标志
  bool _isCancelled = false;

  /// 是否已取消
  bool get isCancelled => _isCancelled;

  /// 取消当前批量任务
  void cancel() {
    _isCancelled = true;
  }

  /// 重置状态（开始新任务前调用）
  void reset() {
    _isCancelled = false;
  }

  /// 批量导出 TTF 字体文件
  ///
  /// [projects] 要处理的项目列表
  /// [onProgress] 进度回调（可选）
  /// 返回每个项目的处理结果
  Future<List<BatchTaskResult>> batchExportTtf(
    List<FontProject> projects, {
    void Function(BatchProgress progress)? onProgress,
  }) async {
    return _executeBatch(
      projects: projects,
      type: BatchTaskType.exportTtf,
      onProgress: onProgress,
      task: (project) async {
        final filePath = await StorageService.exportTtf(project);
        return BatchTaskResult(
          projectId: project.id,
          projectName: project.name,
          success: true,
          outputPath: filePath,
        );
      },
    );
  }

  /// 批量导出项目备份（JSON 格式）
  ///
  /// [projects] 要处理的项目列表
  /// [onProgress] 进度回调（可选）
  Future<List<BatchTaskResult>> batchExportBackup(
    List<FontProject> projects, {
    void Function(BatchProgress progress)? onProgress,
  }) async {
    return _executeBatch(
      projects: projects,
      type: BatchTaskType.exportBackup,
      onProgress: onProgress,
      task: (project) async {
        final filePath = await StorageService.exportProject(project);
        return BatchTaskResult(
          projectId: project.id,
          projectName: project.name,
          success: true,
          outputPath: filePath,
        );
      },
    );
  }

  /// 批量删除项目
  ///
  /// [projects] 要删除的项目列表
  /// [onProgress] 进度回调（可选）
  Future<List<BatchTaskResult>> batchDelete(
    List<FontProject> projects, {
    void Function(BatchProgress progress)? onProgress,
  }) async {
    return _executeBatch(
      projects: projects,
      type: BatchTaskType.delete,
      onProgress: onProgress,
      task: (project) async {
        await StorageService.deleteProject(project.id);
        return BatchTaskResult(
          projectId: project.id,
          projectName: project.name,
          success: true,
        );
      },
    );
  }

  /// 通用批量执行引擎
  ///
  /// 内部使用信号量控制并发，支持取消和进度回调。
  Future<List<BatchTaskResult>> _executeBatch({
    required List<FontProject> projects,
    required BatchTaskType type,
    required Future<BatchTaskResult> Function(FontProject project) task,
    void Function(BatchProgress progress)? onProgress,
  }) async {
    reset();

    final results = <BatchTaskResult>[];
    int completed = 0;
    int successCount = 0;
    int failureCount = 0;

    // 初始化进度
    onProgress?.call(BatchProgress(
      total: projects.length,
      completed: 0,
      successCount: 0,
      failureCount: 0,
      currentProjectName: null,
    ));

    // 使用信号量控制并发
    final semaphore = _Semaphore(_maxConcurrent);
    final futures = <Future>[];

    for (int i = 0; i < projects.length; i++) {
      if (_isCancelled) {
        // 取消后，剩余任务标记为失败
        for (int j = i; j < projects.length; j++) {
          results.add(BatchTaskResult(
            projectId: projects[j].id,
            projectName: projects[j].name,
            success: false,
            errorMessage: '已取消',
          ));
          completed++;
        }
        break;
      }

      final project = projects[i];
      futures.add(() async {
        await semaphore.acquire();
        try {
          if (_isCancelled) {
            results.add(BatchTaskResult(
              projectId: project.id,
              projectName: project.name,
              success: false,
              errorMessage: '已取消',
            ));
            completed++;
            failureCount++;
            onProgress?.call(BatchProgress(
              total: projects.length,
              completed: completed,
              successCount: successCount,
              failureCount: failureCount,
              currentProjectName: project.name,
              isCancelled: true,
            ));
            return;
          }

          // 更新进度：开始处理当前项目
          onProgress?.call(BatchProgress(
            total: projects.length,
            completed: completed,
            successCount: successCount,
            failureCount: failureCount,
            currentProjectName: project.name,
          ));

          try {
            final result = await task(project);
            results.add(result);
            if (result.success) {
              successCount++;
            } else {
              failureCount++;
            }
          } catch (e) {
            debugPrint('批量处理失败 [${project.name}]: $e');
            results.add(BatchTaskResult(
              projectId: project.id,
              projectName: project.name,
              success: false,
              errorMessage: e.toString(),
            ));
            failureCount++;
          }

          completed++;

          // 更新进度
          onProgress?.call(BatchProgress(
            total: projects.length,
            completed: completed,
            successCount: successCount,
            failureCount: failureCount,
            currentProjectName: null,
            isCancelled: _isCancelled,
          ));
        } finally {
          semaphore.release();
        }
      }());
    }

    await Future.wait(futures);

    return results;
  }
}

/// 简单的信号量实现，用于控制并发数
class _Semaphore {
  final int maxCount;
  int _currentCount;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}
