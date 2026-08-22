// Regression test for the P0 fixed by this change: the real shipping
// connection path was passing a single outbound object into VpnCoreConfig
// .singBoxConfigJson as if it were the whole sing-box document, even
// though every doc comment on VpnCoreConfig/the native start() call site
// says (and requires) a COMPLETE document. packages/vpn_core's own
// SingBoxConfigBuilder was fully tested in isolation and that test suite
// stayed green throughout, because nothing exercised the ACTUAL app path
// (subscription import -> ServerConfigGroupItem -> VPNService.setServer ->
// VPNService.start()) end to end.
//
// This test drives that exact path -- AutoConfUtils.tryConvert on a
// realistic singbox-vpn-shaped subscription document, through
// VPNService.setServer/start -- and inspects the VpnCoreConfig that
// actually reaches the (faked) native boundary. If VPNService._configFor
// is ever changed back to `jsonEncode(server.raw)`, the shape assertions
// below fail: a bare outbound has no `inbounds`/`route`/`dns` keys at all.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/utils/auto_conf_utils.dart';
import 'package:vpn_core/vpn_core.dart';

/// In-memory fake standing in for native code (same approach as
/// packages/vpn_core/test/vpn_core_test.dart's `_FakeVpnCorePlatform`),
/// so this test exercises the real Dart-side app path all the way to the
/// Dart<->native boundary without needing a device or the real libbox
/// binary.
class _FakeVpnCorePlatform extends VpnCorePlatform {
  bool initialized = false;
  VpnCoreConfig? lastConfig;
  final _controller = StreamController<VpnCoreStatus>.broadcast();

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> start(VpnCoreConfig config) async {
    lastConfig = config;
    _controller.add(
      VpnCoreStatus(state: VpnCoreState.connected, activeTag: config.tag),
    );
  }

  @override
  Future<void> stop() async {
    _controller.add(VpnCoreStatus.disconnected);
  }

  @override
  Future<void> restart(VpnCoreConfig config) async {
    await stop();
    await start(config);
  }

  @override
  Future<VpnCoreStatus> status() async =>
      lastConfig == null
          ? VpnCoreStatus.disconnected
          : VpnCoreStatus(
            state: VpnCoreState.connected,
            activeTag: lastConfig!.tag,
          );

  @override
  Stream<VpnCoreStatus> statusStream() => _controller.stream;

  @override
  Future<String> coreVersion() async => '1.13.19';

  @override
  Future<List<String>> getSanitizedLogs({int maxLines = 200}) async =>
      const [];
}

// Fake, syntactically-valid test-only credentials -- never real ones.
const _testUuid = '11111111-2222-3333-4444-555555555555';
const _testPublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _testShortId = 'deadbeef01234567';
const _testHy2Password = 'shipping-path-test-fake-password-000';

/// A realistic singbox-vpn-style subscription document: multiple real
/// outbounds (VLESS+REALITY, Hysteria2) plus the pseudo-outbounds
/// (selector/urltest/direct/block/dns) every real subscription also
/// carries, exactly as `AutoConfUtils.tryConvert` must filter them.
String _subscriptionJson() => jsonEncode({
  'outbounds': [
    {
      'type': 'vless',
      'tag': 'reality-node',
      'server': 'example.invalid',
      'server_port': 443,
      'uuid': _testUuid,
      'flow': 'xtls-rprx-vision',
      'tls': {
        'enabled': true,
        'server_name': 'example.invalid',
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {
          'enabled': true,
          'public_key': _testPublicKey,
          'short_id': _testShortId,
        },
      },
    },
    {
      'type': 'hysteria2',
      'tag': 'hy2-node',
      'server': 'example2.invalid',
      'server_port': 443,
      'password': _testHy2Password,
      'tls': {'enabled': true, 'server_name': 'example2.invalid'},
    },
    {
      'type': 'selector',
      'tag': 'select-out',
      'outbounds': ['reality-node', 'hy2-node'],
    },
    {
      'type': 'urltest',
      'tag': 'auto-urltest',
      'outbounds': ['reality-node', 'hy2-node'],
    },
    {'type': 'direct', 'tag': 'direct-out'},
    {'type': 'block', 'tag': 'block-out'},
  ],
});

void main() {
  late _FakeVpnCorePlatform fake;

  setUp(() async {
    fake = _FakeVpnCorePlatform();
    VpnCorePlatform.instance = fake;
    await FlutterVpnService.core.initialize();
  });

  test(
    'subscription import -> setServer -> start() delivers a COMPLETE '
    'sing-box document to the native boundary, not a bare outbound',
    () async {
      // 1. Real import path: AutoConfUtils parses the subscription exactly
      //    as the app does for a real "add profile" flow.
      final group = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..type = SubscriptionLinkType.singbox;
      final err = await AutoConfUtils.tryConvert(
        'https://example.invalid/sub',
        false,
        false,
        group,
        const [],
        null,
        RemoteContent()..text = _subscriptionJson(),
      );
      expect(err, isNull);

      // Only the two real outbounds should have survived the pseudo-
      // outbound filter (selector/urltest/direct/block/dns excluded).
      expect(group.servers.map((s) => s.tag), ['reality-node', 'hy2-node']);
      final selected = group.getByTag('reality-node')!;
      expect(selected.raw, isNotNull);
      expect(selected.raw!['type'], 'vless');

      // 2. Real selection + start path: exactly what the UI calls.
      final setErr = await VPNService.setServer(
        selected,
        VPNServiceSetServerOptions(),
        SingboxExportType.karing,
        null,
        '',
        '',
      );
      expect(setErr, isNull);

      final startErr = await VPNService.start(8000);
      expect(startErr, isNull);

      // 3. Inspect exactly what crossed the Dart<->native boundary.
      final captured = fake.lastConfig;
      expect(captured, isNotNull, reason: 'native start() was never called');
      expect(captured!.tag, 'reality-node');

      final doc =
          jsonDecode(captured.singBoxConfigJson) as Map<String, Object?>;

      // The old bug: this was `server.raw` directly, i.e. just
      // `{"type": "vless", "tag": "reality-node", ...}` with NONE of the
      // keys below. Every assertion here fails against a bare outbound.
      expect(
        doc.containsKey('inbounds'),
        isTrue,
        reason: 'a bare outbound object has no "inbounds" key',
      );
      expect(
        doc.containsKey('route'),
        isTrue,
        reason: 'a bare outbound object has no "route" key',
      );
      expect(
        doc.containsKey('dns'),
        isTrue,
        reason: 'a bare outbound object has no "dns" key',
      );

      final inbounds = doc['inbounds'] as List;
      expect(
        inbounds.any((i) => (i as Map)['type'] == 'tun'),
        isTrue,
        reason: 'mobile TUN mode requires a tun inbound',
      );

      final outbounds = (doc['outbounds'] as List).cast<Map<String, Object?>>();
      final matched = outbounds.where((o) => o['tag'] == 'reality-node');
      expect(
        matched,
        hasLength(1),
        reason: 'the selected real outbound must be present exactly once',
      );
      expect(matched.single['type'], 'vless');
      expect(matched.single['uuid'], _testUuid);

      final route = doc['route'] as Map<String, Object?>;
      expect(route['final'], 'reality-node');

      final dns = doc['dns'] as Map<String, Object?>;
      expect(dns['servers'], isNotEmpty);

      // No secrets in the top-level captured document's string form
      // beyond the deliberate UUID above -- catches an accidental extra
      // credential leaking in from elsewhere in doc construction.
      expect(captured.singBoxConfigJson, isNot(contains(_testHy2Password)));
    },
  );

  test('reload() (profile switch) also delivers a complete document for '
      'the newly selected server', () async {
    final group = ServerConfigGroupItem()
      ..groupid = 'g1'
      ..type = SubscriptionLinkType.singbox;
    await AutoConfUtils.tryConvert(
      'https://example.invalid/sub',
      false,
      false,
      group,
      const [],
      null,
      RemoteContent()..text = _subscriptionJson(),
    );

    final hy2 = group.getByTag('hy2-node')!;
    await VPNService.setServer(
      hy2,
      VPNServiceSetServerOptions(),
      SingboxExportType.karing,
      null,
      '',
      '',
    );
    final reloadErr = await VPNService.reload(8000);
    expect(reloadErr, isNull);

    final doc =
        jsonDecode(fake.lastConfig!.singBoxConfigJson) as Map<String, Object?>;
    final outbounds = (doc['outbounds'] as List).cast<Map<String, Object?>>();
    expect(
      outbounds.any((o) => o['tag'] == 'hy2-node' && o['type'] == 'hysteria2'),
      isTrue,
    );
    expect((doc['route'] as Map)['final'], 'hy2-node');
  });

  test('starting with no server selected (empty raw) fails loudly instead '
      'of silently sending an empty/invalid document', () async {
    // Reset the facade's static current-server state -- VPNService is a
    // process-wide singleton, so a prior test's selection would otherwise
    // leak into this one.
    VPNService.setCurrent(ProxyConfig());
    final startErr = await VPNService.start(8000);
    expect(startErr, isNotNull);
    expect(fake.lastConfig, isNull, reason: 'native start() must not run');
  });

  test('passing just the raw outbound (the old, broken shape) would fail '
      'these same document assertions', () {
    const rawOutboundOnly =
        '{"type":"vless","tag":"reality-node","server":"example.invalid"}';
    final doc = jsonDecode(rawOutboundOnly) as Map<String, Object?>;
    expect(doc.containsKey('inbounds'), isFalse);
    expect(doc.containsKey('route'), isFalse);
    expect(doc.containsKey('dns'), isFalse);
  });
}
