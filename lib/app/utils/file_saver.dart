// Real, self-contained replacement for the missing private `FileSaver`
// helper (previously exported by `package:vpn_service`). Reconstructed from
// every call site (`_fileSaver.setSavePath(path)` then
// `_fileSaver.saveAsJson(obj)`, always on objects with a `toJson()`), which
// is exactly what this does: JSON-encode and write to the last path set.
// Debounced so rapid successive saves (e.g. several config mutations in one
// event loop turn) collapse into a single disk write.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/log.dart';

class FileSaver {
  String? _savePath;
  Timer? _debounce;
  Object? _pending;

  void setSavePath(String path) {
    _savePath = path;
  }

  Future<void> saveAsJson(Object data) async {
    _pending = data;
    _debounce?.cancel();
    final completer = Completer<void>();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      await _flush();
      completer.complete();
    });
    return completer.future;
  }

  Future<void> _flush() async {
    final path = _savePath;
    final data = _pending;
    if (path == null || data == null) return;
    try {
      final content = jsonEncode(data);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } catch (err) {
      Log.w("FileSaver.saveAsJson exception $path ${err.toString()}");
    }
  }
}
