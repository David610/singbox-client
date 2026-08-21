// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:async';
import 'dart:collection';

typedef ParallelTaskWorker = Future<String> Function(String task);
typedef ParallelTaskProgress = void Function(
  String task,
  int left,
  int total,
  bool start,
  bool finish,
);

/// Runs [worker] over a queue of string tasks (e.g. DNS/URL candidates),
/// [concurrency] at a time, reporting progress via [onProgress].
class ParallelTaskQueue {
  ParallelTaskQueue(
    this.worker,
    this.onProgress,
    this.concurrency,
    List<String> initialTasks,
  ) {
    addTasks(initialTasks);
  }

  final ParallelTaskWorker worker;
  final ParallelTaskProgress onProgress;
  final int concurrency;

  final Queue<String> _pending = Queue<String>();
  final Set<String> _all = {};
  final Set<String> _running = {};
  bool _cancelled = false;
  bool _started = false;

  void addTasks(List<String> tasks) {
    for (final task in tasks) {
      if (_all.add(task)) {
        _pending.add(task);
      }
    }
  }

  bool hasTask(String task) => _all.contains(task);

  bool running(String task) => _running.contains(task);

  void cancel() {
    _cancelled = true;
    _pending.clear();
  }

  void run() {
    if (_started) {
      return;
    }
    _started = true;
    _cancelled = false;
    _pump();
  }

  void _pump() {
    if (_cancelled) {
      return;
    }
    while (_running.length < concurrency && _pending.isNotEmpty) {
      final task = _pending.removeFirst();
      _running.add(task);
      onProgress(task, _pending.length, _all.length, true, false);
      unawaited(
        worker(task).then((_) {
          _running.remove(task);
          final finished = _pending.isEmpty && _running.isEmpty;
          onProgress(task, _pending.length, _all.length, false, finished);
          if (!finished) {
            _pump();
          }
        }),
      );
    }
    if (_all.isEmpty) {
      onProgress('', 0, 0, false, true);
    }
  }
}
