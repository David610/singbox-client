// Central redaction tests. This file is the actual enforcement mechanism
// for "never display/export a credential" -- see redaction.dart's header
// comment. Every credential shape this project's own generated configs
// and share links can produce (see SingBoxConfigBuilder) is exercised
// here, plus adversarial/malformed inputs.
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

void main() {
  group('key-value redaction (JSON shape)', () {
    test('redacts uuid', () {
      const input =
          '{"type":"vless","uuid":"9c7e12d1-64c3-46f2-9e21-d707f05c88d9"}';
      final out = redactText(input);
      expect(out.contains('9c7e12d1'), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('redacts REALITY public_key and short_id', () {
      const input =
          '{"reality":{"public_key":"anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w",'
          '"short_id":"580686c710f58181"}}';
      final out = redactText(input);
      expect(
        out.contains('anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'),
        isFalse,
      );
      expect(out.contains('580686c710f58181'), isFalse);
    });

    test('redacts hysteria2 password and obfs password', () {
      const input =
          '{"password":"test-h2-fake-password-000","obfs":'
          '{"type":"salamander","password":"test-salamander-fake-000"}}';
      final out = redactText(input);
      expect(out.contains('test-h2-fake-password-000'), isFalse);
      expect(out.contains('test-salamander-fake-000'), isFalse);
    });

    test('redacts private_key', () {
      const input =
          '{"private_key":"6BCFEAfj1E78_XMA9Ue0gkg0td145QdwizDSJ_fjvVA"}';
      expect(redactText(input).contains('6BCFEAfj1E78'), isFalse);
    });
  });

  group(
    'key-value redaction (query-string shape, vless:// / hysteria2:// URIs)',
    () {
      test('redacts pbk, sid, and the userinfo uuid in a vless:// URI', () {
        const uri =
            'vless://9c7e12d1-64c3-46f2-9e21-d707f05c88d9@vpn.example.com:8443'
            '?security=reality&pbk=anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'
            '&sid=580686c710f58181&flow=xtls-rprx-vision#Reality';
        final out = redactText(uri);
        expect(out.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
        expect(
          out.contains('anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'),
          isFalse,
        );
        expect(out.contains('580686c710f58181'), isFalse);
        // Non-sensitive parts survive.
        expect(out.contains('vpn.example.com'), isTrue);
        expect(out.contains('security=reality'), isTrue);
      });

      test('redacts password and obfs-password in a hysteria2:// URI', () {
        const uri =
            'hysteria2://test-h2-fake-password-000@vpn.example.com:8444'
            '?sni=vpn.example.com&obfs=salamander&obfs-password=test-salamander-fake-000';
        final out = redactText(uri);
        expect(out.contains('test-h2-fake-password-000'), isFalse);
        expect(out.contains('test-salamander-fake-000'), isFalse);
        expect(out.contains('vpn.example.com'), isTrue);
      });
    },
  );

  group('key-value redaction (log-line shape)', () {
    test('redacts "key: value" style engine log lines', () {
      const line =
          'starting vless outbound uuid: 9c7e12d1-64c3-46f2-9e21-d707f05c88d9';
      expect(redactText(line).contains('9c7e12d1'), isFalse);
    });

    test('redacts subscription token / auth token mentions', () {
      const line =
          'fetching subscription, token: abcDEF0123456789abcDEF0123456789';
      final out = redactText(line);
      expect(out.contains('abcDEF0123456789abcDEF0123456789'), isFalse);
    });
  });

  group('shape-aware defense in depth', () {
    test('redacts a standalone UUID with no surrounding key context', () {
      const input =
          'correlating profile 9c7e12d1-64c3-46f2-9e21-d707f05c88d9 with server X';
      expect(redactText(input).contains('9c7e12d1'), isFalse);
    });

    test('redacts a long base64url-shaped token with no known key name', () {
      const input =
          'unexpected value: qvVV9d8L22TV7uplmwiiUj57UPeRpixH5yMavAy7tgoXYZ';
      final out = redactText(input);
      expect(
        out.contains('qvVV9d8L22TV7uplmwiiUj57UPeRpixH5yMavAy7tgoXYZ'),
        isFalse,
      );
    });

    test(
      'redacts an unfamiliar credential-shaped field name via the shape heuristic',
      () {
        // Simulates a future/unknown field this module's key-aware pass
        // doesn't yet recognize by name -- the shape-based pass must still
        // catch it.
        const input =
            '{"futureSecretField":"aVeryLongRandomLookingCredentialValue123456"}';
        final out = redactText(input);
        expect(
          out.contains('aVeryLongRandomLookingCredentialValue123456'),
          isFalse,
        );
      },
    );
  });

  group('does not over-redact ordinary diagnostic text', () {
    test('a short build SHA survives', () {
      const input = 'app build: 1.2.24 (a1b2c3d4e5f6)';
      expect(redactText(input), contains('a1b2c3d4e5f6'));
    });

    test('a hostname survives', () {
      const input = 'server hostname: vpn.singboxvpn.test.invalid';
      expect(redactText(input), contains('vpn.singboxvpn.test.invalid'));
    });

    test('a version string survives', () {
      const input = 'vpn core version: 1.13.19';
      expect(redactText(input), contains('1.13.19'));
    });

    test('ordinary prose survives', () {
      const input = 'TCP connectivity: pass, 42ms';
      expect(redactText(input), input);
    });

    test('a short IPv4 address survives', () {
      const input = 'public ip after: 203.0.113.10';
      expect(redactText(input), contains('203.0.113.10'));
    });
  });

  group('idempotence and edge cases', () {
    test('redacting already-redacted text is a no-op', () {
      const input = '{"uuid":"9c7e12d1-64c3-46f2-9e21-d707f05c88d9"}';
      final once = redactText(input);
      final twice = redactText(once);
      expect(twice, once);
    });

    test('empty string redacts to empty string', () {
      expect(redactText(''), '');
    });

    test('multiple credentials in one blob are all redacted', () {
      const input =
          'vless://9c7e12d1-64c3-46f2-9e21-d707f05c88d9@h:443?pbk=anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w&sid=580686c710f58181\n'
          'hysteria2://test-h2-fake-password-000@h:444?obfs-password=test-salamander-fake-000';
      final out = redactText(input);
      for (final secret in [
        '9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
        'anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w',
        '580686c710f58181',
        'test-h2-fake-password-000',
        'test-salamander-fake-000',
      ]) {
        expect(out.contains(secret), isFalse, reason: 'leaked: $secret');
      }
    });
  });

  group('seeded regression credentials (mobile security audit)', () {
    // Exact seed values used by the mobile security audit's native-logging
    // methodology (see docs/ notes on that pass): if any of these ever
    // shows up unredacted in an exported/logged diagnostics string, that is
    // a confirmed secret leak, not a maybe.
    const seededUuid = 'TEST_VLESS_UUID_SECRET_123';
    const seededHy2Password = 'TEST_HYSTERIA_PASSWORD_SECRET_456';
    const seededSubToken = 'TEST_SUBSCRIPTION_TOKEN_SECRET_789';

    test('redacts the seeded credentials in JSON shape', () {
      const input =
          '{"uuid":"$seededUuid","password":"$seededHy2Password",'
          '"subscription_token":"$seededSubToken"}';
      final out = redactText(input);
      expect(out.contains(seededUuid), isFalse);
      expect(out.contains(seededHy2Password), isFalse);
      expect(out.contains(seededSubToken), isFalse);
    });

    test('redacts the seeded credentials with no key context at all '
        '(shape-aware fallback)', () {
      const input =
          'engine panic while dialing: last known uuid was $seededUuid, '
          'password fallback $seededHy2Password, token $seededSubToken';
      final out = redactText(input);
      expect(out.contains(seededUuid), isFalse);
      expect(out.contains(seededHy2Password), isFalse);
      expect(out.contains(seededSubToken), isFalse);
    });
  });

  group('redactKeepingSuffix', () {
    test('shows only the last N characters', () {
      final out = redactKeepingSuffix('9c7e12d1-64c3-46f2-9e21-d707f05c88d9');
      expect(out, '****88d9');
      expect(out.contains('9c7e12d1'), isFalse);
    });

    test('fully masks a value shorter than the visible suffix', () {
      expect(redactKeepingSuffix('ab'), '**');
    });
  });
}
