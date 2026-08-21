// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/platform_utils.dart';
import 'package:path/path.dart' as path;
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';

class FileUtils {
  FileUtils._();

  static Future<void> deletePath(String filePath, {bool recursive = false}) async {
    try {
      final entityType = await FileSystemEntity.type(filePath);
      if (entityType == FileSystemEntityType.directory) {
        await Directory(filePath).delete(recursive: recursive);
      } else if (entityType != FileSystemEntityType.notFound) {
        await File(filePath).delete();
      }
    } catch (_) {}
  }

  static Future<void> openDirectory(String dirPath) async {
    try {
      if (PlatformUtils.windows) {
        await Process.run('explorer', [dirPath]);
      } else if (PlatformUtils.macos) {
        await Process.run('open', [dirPath]);
      } else if (PlatformUtils.linux) {
        await Process.run('xdg-open', [dirPath]);
      } else {
        final uri = Uri.directory(dirPath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      }
    } catch (_) {}
  }

  static Future<String?> readAndDelete(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final content = await file.readAsString();
      await file.delete();
      return content;
    } catch (_) {
      return null;
    }
  }

  /// Reads up to [maxBytes] from the end of [filePath]. Returns the content
  /// and whether the file was truncated (i.e. the file was larger than
  /// [maxBytes]), or null if the file doesn't exist.
  static Future<Tuple2<String, bool>?> readAsStringReverse(
    String filePath,
    int maxBytes,
    bool reverse,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final length = await file.length();
      final truncated = length > maxBytes;
      final start = truncated ? length - maxBytes : 0;
      final raf = await file.open();
      await raf.setPosition(start);
      final bytes = await raf.read(length - start);
      await raf.close();
      var content = utf8.decode(bytes, allowMalformed: true);
      if (reverse) {
        content = content.split('\n').reversed.join('\n');
      }
      return Tuple2(content, truncated);
    } catch (_) {
      return null;
    }
  }

  static List<String> recursionFile(
    String dir, {
    Set<String>? extensionFilter,
  }) {
    final result = <String>[];
    final directory = Directory(dir);
    if (!directory.existsSync()) {
      return result;
    }
    try {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        if (extensionFilter != null &&
            !extensionFilter.contains(path.extension(entity.path))) {
          continue;
        }
        result.add(entity.path);
      }
    } catch (_) {}
    return result;
  }

  static List<String> recursiveFile(String dir, {Set<String>? filter}) {
    return recursionFile(dir, extensionFilter: filter);
  }

  static Future<bool> validJsonFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }
    try {
      final content = await file.readAsString();
      jsonDecode(content);
      return true;
    } catch (_) {
      return false;
    }
  }
}
