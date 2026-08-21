// Real, minimal replacement for the missing private `LocalStorage` helper
// -- a small persistent key/value store. No `shared_preferences` (or
// equivalent) dependency exists in this repo, so this reads/writes a
// single real JSON file under the app's support directory rather than
// fabricate an in-memory (non-persistent) stand-in.
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/path_utils.dart';

class LocalStorage {
  static Map<String, dynamic>? _cache;

  static Future<String> _filePath() async {
    final dir = await PathUtils.profileDataDir();
    return "$dir/local_storage.json";
  }

  static Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final file = File(await _filePath());
      if (await file.exists()) {
        final content = await file.readAsString();
        _cache = Map<String, dynamic>.from(jsonDecode(content));
        return _cache!;
      }
    } catch (_) {}
    _cache = {};
    return _cache!;
  }

  static Future<String?> read(String key) async {
    final data = await _load();
    return data[key]?.toString();
  }

  static Future<void> write(String key, String value) async {
    final data = await _load();
    data[key] = value;
    try {
      final file = File(await _filePath());
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    final data = await _load();
    data.remove(key);
    try {
      final file = File(await _filePath());
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}
