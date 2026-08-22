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
  /// must match `PathUtils`' own real on-disk file names
  /// (`PathUtils.subscribeFileName()` == "subscribe.json",
  /// `PathUtils.subscribeUseFileName()` == "subscribe_use.json") for each
  /// persisted config blob, not a guessed/aspirational name. A mismatch
  /// here made `backupToZip` fail on every call (it looks up a required
  /// file by this exact name via `File(path.join(dir, file.fileName))` and
  /// errors out with "not exist" if the file is missing) -- see
  /// docs/CLIENT_PRODUCTION_BASELINE.md's backup-security section for the
  /// P0 audit that found and fixed this.
  ///
  /// `subscribe.json` no longer carries credential material in plaintext
  /// (see `ServerManager._buildSecureServerConfigJson` /
  /// `CredentialStore`) -- VLESS UUIDs, Hysteria2 passwords, REALITY keys,
  /// and remote subscription URLs/tokens live in the platform Keystore/
  /// Keychain and are intentionally excluded from this list, so a portable
  /// backup zip does not become an unencrypted credential bundle. Restoring
  /// a backup on the same device keeps working (the secrets are still in
  /// that device's secure store); restoring on a different device requires
  /// re-importing credentials, which is the documented, safer trade-off
  /// over bundling raw secrets into every export.
  static List<BackupZipFile> getZipFileNameList() {
    return const [
      BackupZipFile("subscribe.json"),
      BackupZipFile("diversion_group.json"),
      BackupZipFile("subscribe_use.json"),
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
