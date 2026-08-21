// Compatibility tests against fixtures traced from
// github.com/David610/singbox-vpn (see test/fixtures/singbox_vpn/README.md
// for exact provenance and commit). For each format: input -> parsed model
// -> generated core config, asserting no field is silently dropped or
// altered. See docs/SINGBOX_VPN_COMPATIBILITY.md for the compatibility
// matrix these tests back.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

String _fixture(String name) {
  // `flutter test` (and `dart test`) run with the package root (where
  // pubspec.yaml lives) as the working directory, so a path relative to
  // it is the standard, documented way to load fixture files -- more
  // reliable here than Platform.script, which flutter_tools' own test
  // runner does not preserve pointing at the individual test file.
  return File('test/fixtures/singbox_vpn/$name').readAsStringSync();
}

void main() {
  group('vless:// (REALITY, flow supplied) -- vless_reality_uri.txt', () {
    late VlessRealityParams params;

    setUp(() {
      params = SingBoxConfigBuilder.parseVlessRealityUri(
        _fixture('vless_reality_uri.txt').trim(),
      );
    });

    test('every field from the URI survives parsing', () {
      expect(params.uuid, '9c7e12d1-64c3-46f2-9e21-d707f05c88d9');
      expect(params.server, 'vpn.singboxvpn.test.invalid');
      expect(params.serverPort, 8443);
      expect(params.sni, 'www.microsoft.com');
      expect(params.fingerprint, 'chrome');
      expect(
        params.publicKey,
        'anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w',
      );
      expect(params.shortId, '580686c710f58181');
      expect(params.flow, 'xtls-rprx-vision');
      expect(params.tag, 'Reality');
    });

    test('every field survives into the generated core outbound config', () {
      final outbound = params.toOutboundJson();
      expect(outbound['type'], 'vless');
      expect(outbound['server'], 'vpn.singboxvpn.test.invalid');
      expect(outbound['server_port'], 8443);
      expect(outbound['uuid'], '9c7e12d1-64c3-46f2-9e21-d707f05c88d9');
      expect(outbound['flow'], 'xtls-rprx-vision');

      final tls = outbound['tls'] as Map<String, Object?>;
      expect(tls['server_name'], 'www.microsoft.com');

      final reality = tls['reality'] as Map<String, Object?>;
      expect(reality['public_key'], 'anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w');
      expect(reality['short_id'], '580686c710f58181');

      final utls = tls['utls'] as Map<String, Object?>;
      expect(utls['fingerprint'], 'chrome');
    });
  });

  group('vless:// (REALITY, flow NOT supplied) -- vless_reality_uri_vision_off.txt', () {
    // Regression test for a real bug found while building these fixtures:
    // the parser used to default a missing `flow` query parameter back to
    // 'xtls-rprx-vision', silently re-adding Vision to a URI that
    // singbox-vpn's own `render_vless_reality_uri_vision_off` deliberately
    // omits it from (its per-user server-side "Vision-off experiment").
    // Fixed in SingBoxConfigBuilder.parseVlessRealityUri -- flow now
    // defaults to '' (no flow) when absent, matching a genuinely absent
    // `flow` param rather than assuming Vision.
    late VlessRealityParams params;

    setUp(() {
      params = SingBoxConfigBuilder.parseVlessRealityUri(
        _fixture('vless_reality_uri_vision_off.txt').trim(),
      );
    });

    test('an absent flow parameter parses as no flow, not Vision', () {
      expect(params.flow, isEmpty);
      // Every other field must be identical to the Vision-on fixture --
      // this profile changes exactly one thing (spec requirement 2).
      expect(params.uuid, '9c7e12d1-64c3-46f2-9e21-d707f05c88d9');
      expect(params.publicKey, 'anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w');
      expect(params.shortId, '580686c710f58181');
      expect(params.sni, 'www.microsoft.com');
      expect(params.fingerprint, 'chrome');
    });

    test('the generated outbound config omits "flow" entirely (not "")', () {
      final outbound = params.toOutboundJson();
      expect(
        outbound.containsKey('flow'),
        isFalse,
        reason:
            'sing-box treats an absent flow as "no flow"; an empty-string '
            'flow key is not the same thing to every client and must not '
            'be emitted -- see VlessRealityParams.toOutboundJson().',
      );
    });
  });

  group('hysteria2:// (with Salamander obfs) -- hysteria2_uri.txt', () {
    late Hysteria2Params params;

    setUp(() {
      params = SingBoxConfigBuilder.parseHysteria2Uri(
        _fixture('hysteria2_uri.txt').trim(),
      );
    });

    test('every field from the URI survives parsing', () {
      expect(params.password, 'test-h2-fake-password-000');
      expect(params.server, 'vpn.singboxvpn.test.invalid');
      expect(params.serverPort, 8444);
      expect(params.sni, 'vpn.singboxvpn.test.invalid');
      expect(params.salamanderPassword, 'test-salamander-fake-000');
      expect(params.insecure, isFalse);
      expect(params.tag, 'Hysteria2');
    });

    test('every field survives into the generated core outbound config', () {
      final outbound = params.toOutboundJson();
      expect(outbound['type'], 'hysteria2');
      expect(outbound['password'], 'test-h2-fake-password-000');

      final obfs = outbound['obfs'] as Map<String, Object?>;
      expect(obfs['type'], 'salamander');
      expect(obfs['password'], 'test-salamander-fake-000');

      final tls = outbound['tls'] as Map<String, Object?>;
      expect(tls['server_name'], 'vpn.singboxvpn.test.invalid');
      expect(tls.containsKey('insecure'), isFalse,
          reason: 'insecure=0 in the URI must not force an "insecure" key '
              'into the generated config -- TLS validation must stay on '
              'by default.');
    });
  });

  group('hysteria2:// (no obfs) -- hysteria2_uri_no_obfs.txt', () {
    test('salamanderPassword is null and obfs is omitted from the config', () {
      final params = SingBoxConfigBuilder.parseHysteria2Uri(
        _fixture('hysteria2_uri_no_obfs.txt').trim(),
      );
      expect(params.salamanderPassword, isNull);
      expect(params.toOutboundJson().containsKey('obfs'), isFalse);
    });
  });

  group('sing-box JSON subscription -- subscription_singbox.json', () {
    late List<Map<String, Object?>> outbounds;

    setUp(() {
      outbounds = SingBoxConfigBuilder.extractOutboundsFromSubscription(
        _fixture('subscription_singbox.json'),
      );
    });

    test('contains both a vless and a hysteria2 outbound, plus routing groups', () {
      final types = outbounds.map((o) => o['type']).toSet();
      expect(types, containsAll(['vless', 'hysteria2', 'urltest', 'selector', 'direct']));
    });

    test('the vless/REALITY outbound has no field silently dropped', () {
      final vless = SingBoxConfigBuilder.findOutboundByType(outbounds, 'vless')!;
      expect(vless['server'], 'vpn.singboxvpn.test.invalid');
      expect(vless['server_port'], 8443);
      expect(vless['uuid'], '9c7e12d1-64c3-46f2-9e21-d707f05c88d9');
      expect(vless['flow'], 'xtls-rprx-vision');

      final tls = vless['tls'] as Map<String, Object?>;
      expect(tls['server_name'], 'www.microsoft.com');
      final reality = tls['reality'] as Map<String, Object?>;
      expect(reality['public_key'], 'anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w');
      expect(reality['short_id'], '580686c710f58181');
      final utls = tls['utls'] as Map<String, Object?>;
      expect(utls['fingerprint'], 'chrome');
    });

    test('the hysteria2 outbound has no field silently dropped', () {
      final hy2 = SingBoxConfigBuilder.findOutboundByType(outbounds, 'hysteria2')!;
      expect(hy2['server'], 'vpn.singboxvpn.test.invalid');
      expect(hy2['server_port'], 8444);
      expect(hy2['password'], 'test-h2-fake-password-000');
      final obfs = hy2['obfs'] as Map<String, Object?>;
      expect(obfs['type'], 'salamander');
      expect(obfs['password'], 'test-salamander-fake-000');
    });

    test('the selector defaults to REALITY, not the urltest race, matching '
        "singbox-vpn's SelectionProfile::Reliability default", () {
      final selector = outbounds.firstWhere((o) => o['tag'] == 'select');
      expect(selector['default'], 'Reality');
    });

    test('never contains a REALITY private key or any "private" substring', () {
      final flat = jsonEncode(outbounds).toLowerCase();
      expect(flat.contains('private'), isFalse);
    });
  });

  group('subscription URL import shape', () {
    test(
      'a fetched subscription body (this fixture stands in for the HTTP '
      'response body of GET /sub/{token}) parses the same way a direct '
      'JSON profile does',
      () {
        // The HTTP fetch itself (GET, headers, Cache-Control: no-store,
        // generic-404-on-bad-token) is server behavior this project does
        // not implement or test -- see docs/SINGBOX_VPN_COMPATIBILITY.md.
        // What this client owns is correctly parsing whatever body comes
        // back, which is exactly what extractOutboundsFromSubscription
        // does above; this test only pins that "subscription import" and
        // "sing-box JSON profile import" are the same code path, not two
        // separately-maintained parsers that could silently drift apart.
        final body = _fixture('subscription_singbox.json');
        final outbounds = SingBoxConfigBuilder.extractOutboundsFromSubscription(body);
        expect(outbounds, isNotEmpty);
      },
    );
  });
}
