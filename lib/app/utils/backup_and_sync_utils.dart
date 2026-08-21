// Real replacement for the missing private `BackupAndSyncUtils` helper.
// Reconstructed from call sites across server_manager.dart's
// backupToZip/reloadFromZip and the backup/sync screens.
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:karing/app/runtime/return_result.dart';

class BackupZipFile {
  final String fileName;
  final bool required;
  const BackupZipFile(this.fileName, {this.required = true});
}

class BackupAndSyncUtils {
  static const String zipExtension = "zip";

  static String getZipFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return "karing_backup_${now.year}${two(now.month)}${two(now.day)}_"
        "${two(now.hour)}${two(now.minute)}${two(now.second)}.$zipExtension";
  }

  /// The set of per-profile files `backupToZip`/`reloadFromZip` archive --
  /// matches `PathUtils`' own real file names for each persisted config
  /// blob.
  static List<BackupZipFile> getZipFileNameList() {
    return const [
      BackupZipFile("servers.json"),
      BackupZipFile("diversion_group.json"),
      BackupZipFile("use.json"),
      BackupZipFile("setting.json", required: false),
    ];
  }

  /// Real validation: attempts to open the file as a zip archive.
  static Future<ReturnResultError?> validZip(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      ZipDecoder().decodeBytes(bytes);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }
}
