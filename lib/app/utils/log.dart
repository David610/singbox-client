// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:karing/app/utils/path_utils.dart';

class Log {
  Log._();

  static IOSink? _sink;

  static Future<void> init() async {
    try {
      final filePath = await PathUtils.logFilePath();
      final file = File(filePath);
      await file.parent.create(recursive: true);
      _sink = file.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
    }
  }

  static Future<void> uninit() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  static void d(String message) => _write('D', message);
  static void i(String message) => _write('I', message);
  static void w(String message) => _write('W', message);
  static void e(String message) => _write('E', message);

  static void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    if (kDebugMode) {
      debugPrint(line);
    }
    try {
      _sink?.writeln(line);
    } catch (_) {}
  }
}
