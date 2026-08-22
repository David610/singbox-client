// Regression test for the privacy/reliability cleanup that removed this
// app's silent Karing control-plane dependencies: on every startup, VPN
// connect, and app resume, the app used to fetch
// `https://dot.karing.app/config.json` (RemoteConfigManager),
// `https://dot.karing.app/notice2.json` (NoticeManager), a per-provider
// notice-push endpoint carrying this device's id (BoardProviderNotice-
// Manager), and `https://dot.karing.app/autoupdate.json` followed by a
// silent installer download+execution (AutoUpdateManager) -- none of
// which are required for the first-party VPN to start, import a
// subscription, or connect.
//
// Those network-calling code paths were deleted outright rather than
// merely gated behind a flag or repointed at a placeholder host, so this
// test asserts the deletion directly against the source of the four
// manager files: none of them may reference an HTTP client, a
// background Timer, or a Karing/x31415926 domain any more. This is a
// deliberately static, source-level guard (matching the "or that the
// manager/class was deleted so the call site can't exist" style of
// check) because these managers' `init()` touches `path_provider` for
// on-disk caching, which has no platform channel in a plain `flutter
// test` run -- the important, testable claim is that no network call
// exists in these files at all, not merely that one particular init
// path happens to skip it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/auto_update_manager.dart';
import 'package:karing/app/modules/board_provider_notice_manager.dart';
import 'package:karing/app/modules/notice_manager.dart';
import 'package:karing/app/modules/remote_config_manager.dart';

const _forbiddenTokens = <String>[
  'karing.app',
  'x31415926',
  'HttpUtils',
  'dio.',
  'Timer.periodic',
  'Timer(',
];

const _managerFiles = <String>[
  'lib/app/modules/remote_config_manager.dart',
  'lib/app/modules/notice_manager.dart',
  'lib/app/modules/board_provider_notice_manager.dart',
  'lib/app/modules/auto_update_manager.dart',
];

void main() {
  group('no silent Karing control-plane network calls remain', () {
    for (final path in _managerFiles) {
      test('$path makes no HTTP call and schedules no background timer', () {
        // Strip `//` line comments first: this file's own explanatory
        // comments deliberately name the Karing endpoints/domains that
        // used to be fetched here, as historical context for why the
        // code below looks the way it does. The guard below is about
        // executable code, not comments.
        final codeOnly = File(path)
            .readAsLinesSync()
            .map((line) {
              return line.replaceAll(RegExp(r'(?<!:)//.*'), '');
            })
            .join('\n');
        for (final token in _forbiddenTokens) {
          expect(
            codeOnly.contains(token),
            isFalse,
            reason: '$path still references "$token" outside a comment',
          );
        }
      });
    }

    test('RemoteConfigManager starts with only this app\'s own hardcoded '
        'defaults, never previously-fetched Karing data', () {
      final config = RemoteConfigManager.getConfig();
      // No cached "latest_check" timestamp -- proves nothing has ever
      // run a check-and-save cycle against this fresh instance.
      expect(config.latestCheck, isEmpty);
    });

    test('AutoUpdateManager never has a pending update to install without a '
        'network check ever having run', () {
      final versionCheck = AutoUpdateManager.getVersionCheck();
      expect(versionCheck.newVersion, isFalse);
      expect(versionCheck.version, isEmpty);
      expect(versionCheck.url, isEmpty);
    });

    test('NoticeManager/BoardProviderNoticeManager start with no notices '
        '(nothing populates them without a network fetch)', () {
      expect(NoticeManager.getNotices().single.items, isEmpty);
      expect(BoardProviderNoticeManager.getNotices().single.items, isEmpty);
    });
  });
}
