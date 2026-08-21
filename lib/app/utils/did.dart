// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/path_utils.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class Did {
  Did._();

  static String? _did;

  static Future<String> _didFilePath() async =>
      path.join(await PathUtils.profileDir(), 'did.json');

  static Future<String> getDid() async {
    if (_did != null) {
      return _did!;
    }
    final file = File(await _didFilePath());
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map;
        _did = map['did']?.toString();
      } catch (_) {}
    }
    if (_did == null || _did!.isEmpty) {
      _did = newUUID();
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode({'did': _did}));
      } catch (_) {}
    }
    return _did!;
  }

  static Future<bool> getFirstTime() async {
    final file = File(await _didFilePath());
    final firstTime = !await file.exists();
    if (firstTime) {
      await getDid();
    }
    return firstTime;
  }

  static String newUUID() => const Uuid().v4();
}
