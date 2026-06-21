import 'package:flutter/foundation.dart';

/// 泛型撤销/重做服务
///
/// 支持任何类型的状态快照，维护操作历史栈，
/// 通过 ChangeNotifier 通知 UI 更新。
///
/// 用法：
/// ```dart
/// final service = UndoRedoService<List<String>>(maxDepth: 50);
/// service.push(['a', 'b']);
/// service.push(['a', 'b', 'c']);
/// service.undo(); // 恢复到 ['a', 'b']
/// service.redo(); // 恢复到 ['a', 'b', 'c']
/// ```
class UndoRedoService<T> extends ChangeNotifier {
  /// 最大历史深度，超出时丢弃最早的记录
  final int maxDepth;

  final List<T> _undoStack = [];
  final List<T> _redoStack = [];

  /// 当前状态（最近一次 push 的值）
  T? _currentState;

  UndoRedoService({this.maxDepth = 50});

  /// 当前状态
  T? get currentState => _currentState;

  /// 是否可以撤销
  bool get canUndo => _undoStack.isNotEmpty;

  /// 是否可以重做
  bool get canRedo => _redoStack.isNotEmpty;

  /// 撤销栈深度（用于 UI 显示历史数量）
  int get undoDepth => _undoStack.length;

  /// 重做栈深度
  int get redoDepth => _redoStack.length;

  /// 推入新状态
  ///
  /// 将当前状态保存到撤销栈，清空重做栈。
  /// 每次编辑操作前调用此方法。
  void push(T state) {
    if (_currentState != null) {
      _undoStack.add(_currentState as T);
      // 限制历史深度
      while (_undoStack.length > maxDepth) {
        _undoStack.removeAt(0);
      }
    }
    _currentState = state;
    _redoStack.clear();
    notifyListeners();
  }

  /// 撤销：恢复到上一个状态
  ///
  /// 将当前状态保存到重做栈，从撤销栈弹出上一个状态。
  void undo() {
    if (!canUndo) return;
    _redoStack.add(_currentState as T);
    _currentState = _undoStack.removeLast();
    notifyListeners();
  }

  /// 重做：恢复到下一个状态
  ///
  /// 将当前状态保存到撤销栈，从重做栈弹出下一个状态。
  void redo() {
    if (!canRedo) return;
    _undoStack.add(_currentState as T);
    _currentState = _redoStack.removeLast();
    notifyListeners();
  }

  /// 清空所有历史记录
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _currentState = null;
    notifyListeners();
  }

  @override
  String toString() =>
      'UndoRedoService(undo=${_undoStack.length}, redo=${_redoStack.length}, maxDepth=$maxDepth)';
}
