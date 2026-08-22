// Real pinned sing-box binary validation of the EXACT document the actual
// app shipping path (subscription import -> VPNService.setServer ->
// VPNService.start()) produces -- not a document built directly via
// SingBoxConfigBuilder in isolation (packages/vpn_core already covers
// that; see packages/vpn_core/test/interop/mobile_config_check_interop_test.dart).
//
// This is the test that should have caught the P0 this change fixes:
// `sing-box check` against what VPNService._configFor actually emits.
// Skips (does not fail) if no sing-box binary is available -- CI sets
// VPN_CORE_REQUIRE_REAL_INTEROP=1 so a missing binary there is a hard
// failure, not a silent skip (see .github/workflows/singbox-vpn-compat.yml).
@Tags(['interop'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/utils/auto_conf_utils.dart';
import 'package:vpn_core/vpn_core.dart';

const _testUuid = '11111111-2222-3333-4444-555555555555';
const _testPublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _testShortId = 'deadbeef01234567';

Future<String?> _findSingBoxBinary() async {
  final envPath = Platform.environment['SING_BOX_BIN'];
  if (envPath != null && await File(envPath).exists()) return envPath;
  try {
    final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
      'sing-box',
    ]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).split('\n').first.trim();
      if (path.isNotEmpty) return path;
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

class _FakeVpnCorePlatform extends VpnCorePlatform {
  VpnCoreConfig? lastConfig;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start(VpnCoreConfig config) async => lastConfig = config;

  @override
  Future<void> stop() async {}

  @override
  Future<void> restart(VpnCoreConfig config) async => start(config);

  @override
  Future<VpnCoreStatus> status() async => VpnCoreStatus.disconnected;

  @override
  Stream<VpnCoreStatus> statusStream() => const Stream.empty();

  @override
  Future<String> coreVersion() async => '1.13.19';

  @override
  Future<List<String>> getSanitizedLogs({int maxLines = 200}) async =>
      const [];
}

void main() {
  late String? singBoxBin;

  setUpAll(() async {
    singBoxBin = await _findSingBoxBinary();
    if (singBoxBin == null &&
        Platform.environment['VPN_CORE_REQUIRE_REAL_INTEROP'] == '1') {
      throw StateError(
        'VPN_CORE_REQUIRE_REAL_INTEROP=1 but sing-box binary is not '
        'available -- refusing to silently skip.',
      );
    }
  });

  test(
    'the exact document VPNService.start() sends for a real subscription '
    'passes sing-box v1.13.19 check',
    () async {
      if (singBoxBin == null) {
        markTestSkipped('sing-box binary not available.');
        return;
      }

      final fake = _FakeVpnCorePlatform();
      VpnCorePlatform.instance = fake;
      await FlutterVpnService.core.initialize();

      final group = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..type = SubscriptionLinkType.singbox;
      final subscription = jsonEncode({
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
          {'type': 'direct', 'tag': 'direct-out'},
          {'type': 'block', 'tag': 'block-out'},
        ],
      });
      final err = await AutoConfUtils.tryConvert(
        'https://example.invalid/sub',
        false,
        false,
        group,
        const [],
        null,
        RemoteContent()..text = subscription,
      );
      expect(err, isNull);

      final selected = group.getByTag('reality-node')!;
      await VPNService.setServer(
        selected,
        VPNServiceSetServerOptions(),
        SingboxExportType.karing,
        null,
        '',
        '',
      );
      await VPNService.start(8000);

      final captured = fake.lastConfig;
      expect(captured, isNotNull);

      final workDir = await Directory.systemTemp.createTemp(
        'app_shipping_path_check_',
      );
      try {
        final path = '${workDir.path}/shipping_config.json';
        await File(path).writeAsString(captured!.singBoxConfigJson);
        final result = await Process.run(singBoxBin!, ['check', '-c', path]);
        expect(
          result.exitCode,
          0,
          reason: 'sing-box check rejected the real app-path document: '
              '${result.stderr}',
        );
      } finally {
        await workDir.delete(recursive: true).catchError((_) => workDir);
      }
    },
  );
}
