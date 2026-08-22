// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:vpn_core/vpn_core.dart' show redactText;

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
    // This log persists to disk (see PathUtils.logFilePath()) and can be
    // exported from the app, so every line written here MUST go through
    // redactText -- server credentials, subscription tokens, and REALITY
    // keys pass through this path via ServerManager/HTTP error messages
    // and must never land on disk unredacted. Console debugPrint output
    // is redacted too, for the same reason (device logs are exportable
    // via adb/Xcode console).
    final redacted = redactText(message);
    final line = '${DateTime.now().toIso8601String()} [$level] $redacted';
    if (kDebugMode) {
      debugPrint(line);
    }
    try {
      _sink?.writeln(line);
    } catch (_) {}
  }
}
