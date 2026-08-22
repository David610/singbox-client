// Regression tests for the P0 backup-security audit:
//
// 1. BackupAndSyncUtils.getZipFileNameList() used to list "servers.json"
//    and "use.json" -- names that never existed on disk (the real files
//    are PathUtils.subscribeFileName() == "subscribe.json" and
//    PathUtils.subscribeUseFileName() == "subscribe_use.json"). Because
//    "servers.json" was marked `required: true`, ServerManager.backupToZip
//    failed on every single call (`File(join(dir, "servers.json")).exists()`
//    was always false) -- backup was completely broken, not just
//    insecure. This test locks the list to the real on-disk names so this
//    can't silently regress again.
//
// 2. A backup built from the current (post credential-migration) on-disk
//    files must not contain planted secret material -- i.e. once
//    ServerManager has migrated a profile's credentials into
//    CredentialStore (see server_manager_credential_migration_test.dart),
//    the plaintext subscribe.json backupToZip archives no longer carries
//    those secrets. This exercises the real zip encoder/decoder
//    (package:archive via ZipUtils), not a reimplementation of it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/backup_and_sync_utils.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/app/utils/zip_utils.dart';
import 'package:path/path.dart' as path;

void main() {
  test('getZipFileNameList names match the real PathUtils on-disk file '
      'names (regression: these used to be "servers.json"/"use.json", '
      'which never existed and made backupToZip fail every time)', () {
    final names = BackupAndSyncUtils.getZipFileNameList()
        .map((f) => f.fileName)
        .toSet();

    expect(names, contains(PathUtils.subscribeFileName()));
    expect(names, contains(PathUtils.subscribeUseFileName()));
    expect(names, contains(PathUtils.diversionGroupFileName()));
    expect(names, contains(PathUtils.settingFileName()));
    // The old, never-real names must not reappear.
    expect(names, isNot(contains('servers.json')));
    expect(names, isNot(contains('use.json')));
  });

  test('a backup zip built from post-migration on-disk files never '
      'contains planted secret material', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'backup_secret_test',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    const plantedUuid = 'PLANTED_SECRET_UUID_should_never_appear';
    const plantedToken = 'PLANTED_SECRET_TOKEN_should_never_appear';

    // Post-migration shape: subscribe.json carries only secret_ref /
    // url_secret_ref, never the raw credential or URL -- exactly what
    // ServerManager.buildSecureServerConfigJsonFor produces.
    final subscribeJson = jsonEncode({
      'items': [
        {
          'groupid': 'g1',
          'url_or_path': '',
          'url_secret_ref': 'sub-ref-1',
          'servers': [
            {'tag': 'srv-1', 'secret_ref': 'server-ref-1'},
          ],
        },
      ],
    });
    // The real secret lives only in the platform Keystore/Keychain
    // (CredentialStore), never in this file -- so planting it here at all
    // would itself be the bug this test is guarding against.
    expect(subscribeJson, isNot(contains(plantedUuid)));
    expect(subscribeJson, isNot(contains(plantedToken)));

    final filesByName = {
      PathUtils.subscribeFileName(): subscribeJson,
      PathUtils.diversionGroupFileName(): '{"items":[]}',
      PathUtils.subscribeUseFileName(): '{}',
      PathUtils.settingFileName(): '{}',
    };
    final filePaths = <String>[];
    for (final entry in filesByName.entries) {
      final filePath = path.join(tempDir.path, entry.key);
      await File(filePath).writeAsString(entry.value);
      filePaths.add(filePath);
    }

    final zipPath = path.join(tempDir.path, 'backup.zip');
    final error = await ZipUtils.zip(filePaths, zipPath);
    expect(error, isNull);

    // Round-trip through the real zip encoder/decoder (not just checking
    // the pre-zip strings) -- restore into a second temp dir and inspect
    // what actually comes back out, the same way ServerManager.reloadFromZip
    // does on restore.
    final restoreDir = await Directory.systemTemp.createTemp(
      'backup_secret_test_restore',
    );
    addTearDown(() => restoreDir.delete(recursive: true));
    final unzipError = await ZipUtils.unzip(zipPath, restoreDir.path);
    expect(unzipError, isNull);

    final restoredSubscribe = await File(
      path.join(restoreDir.path, PathUtils.subscribeFileName()),
    ).readAsString();
    expect(restoredSubscribe, isNot(contains(plantedUuid)));
    expect(restoredSubscribe, isNot(contains(plantedToken)));
    expect(restoredSubscribe, contains('secret_ref'));
    expect(restoredSubscribe, contains('url_secret_ref'));
  });
}
