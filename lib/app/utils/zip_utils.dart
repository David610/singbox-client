// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:path/path.dart' as path;

class ZipUtils {
  ZipUtils._();

  static Future<ReturnResultError?> zip(
    List<String> filePaths,
    String zipPath,
  ) async {
    try {
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      for (final filePath in filePaths) {
        final entity = File(filePath);
        if (await entity.exists()) {
          await encoder.addFile(entity, path.basename(filePath));
        } else if (await Directory(filePath).exists()) {
          await encoder.addDirectory(
            Directory(filePath),
            includeDirName: false,
          );
        }
      }
      await encoder.close();
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }

  static Future<ReturnResultError?> unzip(
    String zipPath,
    String targetDir, {
    Set<String>? whiteList,
  }) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (whiteList != null && !whiteList.contains(file.name)) {
          continue;
        }
        final outPath = path.join(targetDir, file.name);
        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }

  static Future<ReturnResult<List<String>>> list(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      return ReturnResult(data: archive.map((e) => e.name).toList());
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString(), report: false));
    }
  }
}
