// Regression test for the redaction wiring added to Log._write: the on-disk
// app log (PathUtils.logFilePath()) is exportable and must never carry raw
// server credentials, subscription tokens, or REALITY keys. This exercises
// the same debugPrint sink Log._write feeds in kDebugMode (the file sink
// itself needs a real filesystem/path_provider channel Log.init() doesn't
// have in a plain `flutter test` run, so it stays null and is skipped
// safely -- debugPrint is the one sink this test can observe directly).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/log.dart';

void main() {
  test('Log redacts credential-shaped values before they reach any sink', () {
    final captured = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };
    try {
      Log.e(
        'connect failed for '
        '"uuid": "d290f1ee-6c54-4b01-90e6-d701748f0851", '
        '"password": "hunter2-supersecret", '
        'server=vless://example.com?pbk=abcdefghijklmnopqrstuvwxyz012345',
      );
    } finally {
      debugPrint = original;
    }

    expect(captured, isNotEmpty);
    final line = captured.single;
    expect(line, isNot(contains('d290f1ee-6c54-4b01-90e6-d701748f0851')));
    expect(line, isNot(contains('hunter2-supersecret')));
    expect(line, isNot(contains('abcdefghijklmnopqrstuvwxyz012345')));
    expect(line, contains('[REDACTED]'));
  });
}
