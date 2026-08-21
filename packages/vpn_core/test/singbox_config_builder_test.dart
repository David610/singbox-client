import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

void main() {
  group('VLESS + REALITY', () {
    test('parses a vless:// share link with REALITY params', () {
      final uri =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?security=reality&flow=xtls-rprx-vision&sni=www.apple.com'
          '&pbk=abcDEF123-publicKeyValue&sid=deadbeef&fp=chrome#My%20Server';

      final params = SingBoxConfigBuilder.parseVlessRealityUri(uri);

      expect(params.uuid, '11111111-2222-3333-4444-555555555555');
      expect(params.server, 'example.com');
      expect(params.serverPort, 443);
      expect(params.flow, 'xtls-rprx-vision');
      expect(params.sni, 'www.apple.com');
      expect(params.publicKey, 'abcDEF123-publicKeyValue');
      expect(params.shortId, 'deadbeef');
      expect(params.fingerprint, 'chrome');
      expect(params.tag, 'My Server');
    });

    test('rejects non-reality security', () {
      const uri = 'vless://uuid@example.com:443?security=tls&sni=example.com';
      expect(
        () => SingBoxConfigBuilder.parseVlessRealityUri(uri),
        throwsA(isA<SingBoxUriParseException>()),
      );
    });

    test('rejects a URI missing the REALITY public key', () {
      const uri = 'vless://uuid@example.com:443?security=reality';
      expect(
        () => SingBoxConfigBuilder.parseVlessRealityUri(uri),
        throwsA(isA<SingBoxUriParseException>()),
      );
    });

    test(
      'produces a sing-box outbound matching option.VLESSOutboundOptions',
      () {
        const params = VlessRealityParams(
          tag: 'srv-1',
          server: '203.0.113.10',
          serverPort: 8443,
          uuid: '11111111-2222-3333-4444-555555555555',
          sni: 'www.microsoft.com',
          publicKey: 'pubkey-value',
          shortId: 'ab12',
        );

        final outbound = params.toOutboundJson();

        expect(outbound['type'], 'vless');
        expect(outbound['server'], '203.0.113.10');
        expect(outbound['server_port'], 8443);
        expect(outbound['uuid'], '11111111-2222-3333-4444-555555555555');
        expect(outbound['flow'], 'xtls-rprx-vision');

        final tls = outbound['tls'] as Map<String, Object?>;
        expect(tls['enabled'], true);
        expect(tls['server_name'], 'www.microsoft.com');

        final reality = tls['reality'] as Map<String, Object?>;
        expect(reality['enabled'], true);
        expect(reality['public_key'], 'pubkey-value');
        expect(reality['short_id'], 'ab12');

        final utls = tls['utls'] as Map<String, Object?>;
        expect(utls['enabled'], true);
        expect(utls['fingerprint'], 'chrome');
      },
    );

    test('omits flow when explicitly empty (non-Vision transport)', () {
      const params = VlessRealityParams(
        tag: 's',
        server: 'h',
        serverPort: 443,
        uuid: 'u',
        flow: '',
        sni: 'h',
        publicKey: 'k',
        shortId: '',
      );
      expect(params.toOutboundJson().containsKey('flow'), isFalse);
    });

    test('toString never leaks the uuid or REALITY public key', () {
      const params = VlessRealityParams(
        tag: 's',
        server: 'h',
        serverPort: 443,
        uuid: 'super-secret-uuid',
        sni: 'h',
        publicKey: 'super-secret-pubkey',
        shortId: 'sid',
      );
      final text = params.toString();
      expect(text.contains('super-secret-uuid'), isFalse);
      expect(text.contains('super-secret-pubkey'), isFalse);
    });
  });

  group('Hysteria2 + Salamander', () {
    test('parses a hysteria2:// share link with salamander obfuscation', () {
      const uri =
          'hysteria2://p%40ssw0rd@203.0.113.20:36712'
          '?obfs=salamander&obfs-password=obfsSecret&sni=cdn.example.com'
          '&insecure=1#EU%20Node';

      final params = SingBoxConfigBuilder.parseHysteria2Uri(uri);

      expect(params.password, 'p@ssw0rd');
      expect(params.server, '203.0.113.20');
      expect(params.serverPort, 36712);
      expect(params.salamanderPassword, 'obfsSecret');
      expect(params.sni, 'cdn.example.com');
      expect(params.insecure, isTrue);
      expect(params.tag, 'EU Node');
    });

    test('accepts the hy2:// scheme alias', () {
      const uri = 'hy2://pw@example.com:443';
      final params = SingBoxConfigBuilder.parseHysteria2Uri(uri);
      expect(params.password, 'pw');
      expect(params.server, 'example.com');
    });

    test('rejects an unsupported obfs type', () {
      const uri = 'hysteria2://pw@example.com:443?obfs=other';
      expect(
        () => SingBoxConfigBuilder.parseHysteria2Uri(uri),
        throwsA(isA<SingBoxUriParseException>()),
      );
    });

    test(
      'produces a sing-box outbound matching option.Hysteria2OutboundOptions',
      () {
        const params = Hysteria2Params(
          tag: 'hy-1',
          server: '203.0.113.30',
          serverPort: 443,
          password: 'auth-pass',
          salamanderPassword: 'obfs-pass',
          sni: 'cdn.example.com',
        );

        final outbound = params.toOutboundJson();

        expect(outbound['type'], 'hysteria2');
        expect(outbound['password'], 'auth-pass');

        final obfs = outbound['obfs'] as Map<String, Object?>;
        expect(obfs['type'], 'salamander');
        expect(obfs['password'], 'obfs-pass');

        final tls = outbound['tls'] as Map<String, Object?>;
        expect(tls['server_name'], 'cdn.example.com');
      },
    );

    test('omits obfs entirely when no salamander password is set', () {
      const params = Hysteria2Params(
        tag: 'h',
        server: 'h',
        serverPort: 443,
        password: 'p',
      );
      expect(params.toOutboundJson().containsKey('obfs'), isFalse);
    });

    test('toString never leaks the password or obfs password', () {
      const params = Hysteria2Params(
        tag: 'h',
        server: 'h',
        serverPort: 443,
        password: 'top-secret-password',
        salamanderPassword: 'top-secret-obfs',
      );
      final text = params.toString();
      expect(text.contains('top-secret-password'), isFalse);
      expect(text.contains('top-secret-obfs'), isFalse);
    });
  });

  group('document assembly', () {
    test('wraps an outbound in a UDP-enabled tun document', () {
      const params = Hysteria2Params(
        tag: 'hy-1',
        server: 'h',
        serverPort: 443,
        password: 'p',
      );
      final json = SingBoxConfigBuilder.buildSingleOutboundDocument(
        outbound: params.toOutboundJson(),
      );
      final doc = jsonDecode(json) as Map<String, Object?>;

      final inbound = (doc['inbounds'] as List).single as Map<String, Object?>;
      expect(inbound['type'], 'tun');
      expect(inbound['udp_timeout'], isNotNull);

      final outbounds = doc['outbounds'] as List;
      expect(outbounds.map((o) => (o as Map)['tag']), contains('hy-1'));
      expect((doc['route'] as Map)['final'], 'hy-1');
    });

    test('disables udp_timeout when UDP is turned off', () {
      const params = Hysteria2Params(
        tag: 'hy-1',
        server: 'h',
        serverPort: 443,
        password: 'p',
      );
      final json = SingBoxConfigBuilder.buildSingleOutboundDocument(
        outbound: params.toOutboundJson(),
        udpEnabled: false,
      );
      final doc = jsonDecode(json) as Map<String, Object?>;
      final inbound = (doc['inbounds'] as List).single as Map<String, Object?>;
      expect(inbound['udp_timeout'], isNull);
    });
  });
}
