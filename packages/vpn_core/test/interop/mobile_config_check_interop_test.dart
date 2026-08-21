// Real protocol interop test: `sing-box check` against the COMPLETE
// generated mobile tunnel configuration.
//
// Unlike reality_interop_test.dart/hysteria2_interop_test.dart (which
// swap the `tun` inbound for a `mixed`/SOCKS5 one so a raw-socket driver
// can prove bytes flow), this test uses the exact, unmodified document
// `SingBoxConfigBuilder.buildSingleOutboundDocument` produces for the
// real mobile app -- `tun` inbound, DNS, route, and all -- and validates
// it with the real pinned sing-box binary's own `check` subcommand. This
// is what catches schema drift the protocol-interop tests can't: they
// never exercise the `tun` inbound or DNS server blocks at all, since
// both are replaced for loopback testing purposes.
//
// Motivating regression: `buildSingleOutboundDocument` emitted the tun
// inbound's `inet4_address`/`inet6_address` fields, which sing-box's own
// option/tun.go marks `// Deprecated: merged to Address` and
// protocol/tun/inbound.go rejects outright as of the pinned v1.13.19
// ("legacy tun address fields are deprecated in sing-box 1.10.0 and
// removed in sing-box 1.12.0") -- a config that never reached this
// specific check before now would have looked fine in every other test
// here (none of them build a `tun` inbound) and then failed for real
// users on-device. This test exists so that regression, and any future
// one shaped like it, fails CI instead of shipping.
//
// Skips (does not fail) if no sing-box binary is available -- CI sets
// VPN_CORE_REQUIRE_REAL_INTEROP=1 (see common.dart) so a missing binary
// there is a hard failure, not a silent skip.
@Tags(['interop'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

import 'common.dart';

// Fake, syntactically-valid test-only values -- never a real credential.
// See the redaction assertions below: this test also asserts none of
// these appear in captured process output, so a leak here would fail the
// test itself, not just be bad practice.
const _testUuid = '11111111-2222-3333-4444-555555555555';
const _testPublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _testShortId = 'deadbeef01234567';
const _testHy2Password = 'sing-box-check-fake-password-000';
const _testSalamanderPassword = 'sing-box-check-fake-salamander-000';

void main() {
  late String? singBoxBin;
  late Directory workDir;

  setUpAll(() async {
    singBoxBin = await findSingBoxBinary();
    requireRealInteropIfDemanded(
      available: singBoxBin != null,
      what: 'sing-box binary',
    );
    workDir = await Directory.systemTemp.createTemp(
      'vpn_core_mobile_config_check_',
    );
  });

  tearDownAll(() async {
    await workDir.delete(recursive: true).catchError((_) => workDir);
  });

  Future<void> writeAndCheck(String name, String json) async {
    final path = '${workDir.path}/$name.json';
    await File(path).writeAsString(json);
    // Throws (failing the test) with sing-box's own stderr on a real
    // schema rejection -- exactly the failure mode the motivating
    // regression above hit.
    await checkSingBoxConfig(singBoxBin!, path);
  }

  test('complete generated VLESS+REALITY mobile config passes '
      'sing-box v1.13.19 check', () async {
    if (singBoxBin == null) {
      markTestSkipped('sing-box binary not available.');
      return;
    }

    const params = VlessRealityParams(
      tag: 'mobile-vless-reality',
      server: 'example.invalid',
      serverPort: 443,
      uuid: _testUuid,
      sni: 'example.invalid',
      publicKey: _testPublicKey,
      shortId: _testShortId,
    );
    final json = SingBoxConfigBuilder.buildSingleOutboundDocument(
      outbound: params.toOutboundJson(),
    );

    // The exact production document, unmodified -- this is the whole
    // point of this test versus the protocol-interop ones.
    final doc = jsonDecode(json) as Map<String, Object?>;
    final inbound = (doc['inbounds'] as List).single as Map<String, Object?>;
    expect(
      inbound['type'],
      'tun',
      reason: 'must be the real tun inbound, not swapped for mixed',
    );
    expect(
      inbound.containsKey('inet4_address'),
      isFalse,
      reason: 'inet4_address is removed in sing-box 1.12.0',
    );
    expect(
      inbound.containsKey('inet6_address'),
      isFalse,
      reason: 'inet6_address is removed in sing-box 1.12.0',
    );
    expect(inbound['address'], isNotNull);

    await writeAndCheck('mobile_vless_reality', json);
  });

  test('complete generated VLESS+REALITY mobile config with UDP disabled '
      'passes sing-box v1.13.19 check', () async {
    if (singBoxBin == null) {
      markTestSkipped('sing-box binary not available.');
      return;
    }

    const params = VlessRealityParams(
      tag: 'mobile-vless-reality-noudp',
      server: 'example.invalid',
      serverPort: 443,
      uuid: _testUuid,
      sni: 'example.invalid',
      publicKey: _testPublicKey,
      shortId: _testShortId,
    );
    final json = SingBoxConfigBuilder.buildSingleOutboundDocument(
      outbound: params.toOutboundJson(),
      udpEnabled: false,
    );
    await writeAndCheck('mobile_vless_reality_noudp', json);
  });

  test('complete generated Hysteria2+Salamander mobile config passes '
      'sing-box v1.13.19 check', () async {
    if (singBoxBin == null) {
      markTestSkipped('sing-box binary not available.');
      return;
    }

    const params = Hysteria2Params(
      tag: 'mobile-hysteria2',
      server: 'example.invalid',
      serverPort: 443,
      password: _testHy2Password,
      salamanderPassword: _testSalamanderPassword,
      sni: 'example.invalid',
    );
    final json = SingBoxConfigBuilder.buildSingleOutboundDocument(
      outbound: params.toOutboundJson(),
    );
    await writeAndCheck('mobile_hysteria2', json);
  });

  test('sing-box check output never contains a credential from the '
      'generated config', () async {
    if (singBoxBin == null) {
      markTestSkipped('sing-box binary not available.');
      return;
    }

    const params = Hysteria2Params(
      tag: 'mobile-hysteria2-redaction',
      server: 'example.invalid',
      serverPort: 443,
      password: _testHy2Password,
      salamanderPassword: _testSalamanderPassword,
      sni: 'example.invalid',
    );
    final json = SingBoxConfigBuilder.buildSingleOutboundDocument(
      outbound: params.toOutboundJson(),
    );
    final path = '${workDir.path}/mobile_hysteria2_redaction.json';
    await File(path).writeAsString(json);

    final result = await Process.run(singBoxBin!, ['check', '-c', path]);
    final combined = '${result.stdout}${result.stderr}';
    expect(
      combined,
      isNot(contains(_testHy2Password)),
      reason: 'sing-box check output must never echo a credential',
    );
    expect(
      combined,
      isNot(contains(_testSalamanderPassword)),
      reason: 'sing-box check output must never echo a credential',
    );
    expect(result.exitCode, 0, reason: combined);
  });
}
