import 'dart:async';

/// 简单的信号量实现，用于并发控制
class Semaphore {
  final int _maxCount;
  int _currentCount;
  final List<Completer<void>> _waiters = [];

  Semaphore(this._maxCount) : _currentCount = _maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _currentCount++;
    }
  }
}
