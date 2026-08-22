import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/backup_and_sync_utils.dart';

void main() {
  test('portable backup allowlist excludes every credential-bearing file', () {
    final names = BackupAndSyncUtils.getZipFileNameList()
        .map((entry) => entry.fileName)
        .toSet();
    expect(names, {'diversion_group.json', 'subscribe_use.json'});
    expect(names, isNot(contains('subscribe.json')));
    expect(names, isNot(contains('setting.json')));
  });
}
