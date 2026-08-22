// Regression tests for the import-hardening added to AutoConfUtils.tryConvert:
// the same function backs every "add subscription" entry path (pasted URL,
// karing:// deep link, Android SEND text/plain, QR-scanned URL, local file
// import), so hardening it here covers all of them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/utils/auto_conf_utils.dart';

void main() {
  group('AutoConfUtils.tryConvert import hardening', () {
    test('a plain http:// remote subscription URL is rejected', () async {
      final group = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..type = SubscriptionLinkType.singbox;

      final err = await AutoConfUtils.tryConvert(
        'http://example.invalid/sub',
        false,
        false,
        group,
        const [],
        null,
        null,
      );

      expect(err, isNotNull);
      expect(err!.message, contains('https'));
      expect(group.servers, isEmpty);
    });

    test('an unsupported custom scheme is rejected, not executed', () async {
      final group = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..type = SubscriptionLinkType.singbox;

      final err = await AutoConfUtils.tryConvert(
        'javascript:alert(1)',
        false,
        false,
        group,
        const [],
        null,
        null,
      );

      expect(err, isNotNull);
    });

    test(
      'a pathologically long pasted URL is rejected before any I/O',
      () async {
        final group = ServerConfigGroupItem()
          ..groupid = 'g1'
          ..type = SubscriptionLinkType.singbox;
        final huge = 'https://example.invalid/${'a' * (9 * 1024)}';

        final err = await AutoConfUtils.tryConvert(
          huge,
          false,
          false,
          group,
          const [],
          null,
          null,
        );

        expect(err, isNotNull);
        expect(err!.message, contains('long'));
      },
    );

    test('malformed JSON content fails safely without throwing', () async {
      final dir = await Directory.systemTemp.createTemp('auto_conf_utils_');
      final file = File('${dir.path}/bad.json')
        ..writeAsStringSync('{not valid json ]]]');
      addTearDown(() => dir.delete(recursive: true));

      final group = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..type = SubscriptionLinkType.singbox;

      final err = await AutoConfUtils.tryConvert(
        file.path,
        true,
        false,
        group,
        const [],
        null,
        null,
      );

      expect(err, isNotNull);
      expect(group.servers, isEmpty);
    });

    test(
      'well-formed JSON that is not a sing-box object fails safely',
      () async {
        final dir = await Directory.systemTemp.createTemp('auto_conf_utils_');
        final file = File('${dir.path}/array.json')
          ..writeAsStringSync(jsonEncode(['not', 'an', 'object']));
        addTearDown(() => dir.delete(recursive: true));

        final group = ServerConfigGroupItem()
          ..groupid = 'g1'
          ..type = SubscriptionLinkType.singbox;

        final err = await AutoConfUtils.tryConvert(
          file.path,
          true,
          false,
          group,
          const [],
          null,
          null,
        );

        expect(err, isNotNull);
        expect(err!.message, contains('invalid'));
      },
    );

    test(
      'a well-formed https:// subscription (delivered as content) imports normally',
      () async {
        final group = ServerConfigGroupItem()
          ..groupid = 'g1'
          ..type = SubscriptionLinkType.singbox;
        final content = jsonEncode({
          'outbounds': [
            {
              'type': 'hysteria2',
              'tag': 'node-1',
              'server': 'example.invalid',
              'server_port': 443,
              'password': 'fake-password-000',
            },
          ],
        });

        final err = await AutoConfUtils.tryConvert(
          'https://example.invalid/sub',
          false,
          false,
          group,
          const [],
          null,
          RemoteContent()..text = content,
        );

        expect(err, isNull);
        expect(group.servers.map((s) => s.tag), ['node-1']);
      },
    );
  });
}
