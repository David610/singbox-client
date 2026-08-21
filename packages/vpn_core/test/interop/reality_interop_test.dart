// Real protocol interop test: VLESS+REALITY.
//
// Builds a server config in singbox-vpn's own shape
// (server::render_singbox_server_config -- see
// test/fixtures/singbox_vpn/server_config_reference.json, which this test
// uses verbatim) and a client outbound via vpn_core's OWN production
// `SingBoxConfigBuilder`/`VlessRealityParams` (the exact code path the app
// uses), drives a REAL pinned sing-box binary as both ends over loopback
// with a local TLS 1.3 decoy, and asserts a real HTTP GET through the
// tunnel succeeds -- then that it fails against a wrong (but
// well-formed) REALITY public key, proving validation isn't weakened.
//
// SCOPE: this proves the generated config + pinned sing-box core
// interoperate. It does NOT exercise android.net.VpnService or
// NEPacketTunnelProvider -- see docs/SINGBOX_VPN_COMPATIBILITY.md. Do not
// read a pass here as "the mobile app works."
//
// Skips (does not fail) if no sing-box binary or openssl is available --
// set SING_BOX_BIN to a pinned v1.13.19 binary to run this for real; see
// packages/vpn_core/UPSTREAM_VERSION.md for how one was built and verified
// in this project's own development session.
@Tags(['interop'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

import 'common.dart';

const _testUuid = '9c7e12d1-64c3-46f2-9e21-d707f05c88d9';
const _testPublicKey = 'anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w';
const _testPrivateKey = '6BCFEAfj1E78_XMA9Ue0gkg0td145QdwizDSJ_fjvVA';
const _wrongPublicKey = 'qvVV9d8L22TV7uplmwiiUj57UPeRpixH5yMavAy7tgo';
const _testShortId = '580686c710f58181';

void main() {
  late String? singBoxBin;
  late bool haveOpenssl;
  late Directory workDir;

  setUpAll(() async {
    singBoxBin = await findSingBoxBinary();
    haveOpenssl = await findOpenssl();
    requireRealInteropIfDemanded(
      available: singBoxBin != null,
      what: 'sing-box binary',
    );
    requireRealInteropIfDemanded(available: haveOpenssl, what: 'openssl');
    workDir = await Directory.systemTemp.createTemp(
      'vpn_core_reality_interop_',
    );
  });

  tearDownAll(() async {
    await workDir.delete(recursive: true).catchError((_) {});
  });

  test('VLESS+REALITY: generated client outbound completes a real handshake '
      'and carries an HTTP GET', () async {
    if (singBoxBin == null || !haveOpenssl) {
      markTestSkipped(
        'sing-box binary or openssl not available in this environment; '
        'see this file\'s header for how to provide SING_BOX_BIN. CI '
        'should treat this skip as a hard failure, matching '
        'VPN1_REQUIRE_REAL_INTEROP=1 in singbox-vpn itself.',
      );
      return;
    }

    final decoy = await spawnLocalTls13Decoy(workDir);
    final httpTarget = await spawnLocalHttpTarget();
    addTearDown(() {
      decoy.stop();
      httpTarget.stop();
    });

    final realityPort = await _freePort();
    final socksPort = await _freePort();

    // Server: singbox-vpn's own render_singbox_server_config shape (see
    // test/fixtures/singbox_vpn/server_config_reference.json for the
    // static copy of exactly this).
    final serverConfig = {
      'log': {'level': 'warn', 'timestamp': true},
      'inbounds': [
        {
          'type': 'vless',
          'tag': 'vless-reality-in',
          'listen': '127.0.0.1',
          'listen_port': realityPort,
          'users': [
            {
              'name': 'interop-test-user',
              'uuid': _testUuid,
              'flow': 'xtls-rprx-vision',
            },
          ],
          'tls': {
            'enabled': true,
            'server_name': LocalDecoy.hostname,
            'reality': {
              'enabled': true,
              'handshake': {
                'server': LocalDecoy.hostname,
                'server_port': decoy.port,
              },
              'private_key': _testPrivateKey,
              'short_id': [_testShortId],
            },
          },
        },
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
      ],
    };
    final serverConfigPath = '${workDir.path}/server.json';
    await File(
      serverConfigPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(serverConfig));
    await checkSingBoxConfig(singBoxBin!, serverConfigPath);

    // Client: THE REAL vpn_core code path, not hand-written JSON.
    // `final`, not `const` -- realityPort is a runtime-assigned free
    // port (await _freePort()), not a compile-time constant.
    final params = VlessRealityParams(
      tag: 'reality-test',
      server: '127.0.0.1',
      serverPort: realityPort,
      uuid: _testUuid,
      sni: LocalDecoy.hostname,
      publicKey: _testPublicKey,
      shortId: _testShortId,
    );
    final outbound = params.toOutboundJson();
    final clientConfig = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': socksPort,
        },
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': 'reality-test'},
    };
    final clientConfigPath = '${workDir.path}/client.json';
    await File(
      clientConfigPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(clientConfig));
    await checkSingBoxConfig(singBoxBin!, clientConfigPath);

    final server = await runSingBox(singBoxBin!, serverConfigPath);
    final client = await runSingBox(singBoxBin!, clientConfigPath);
    addTearDown(() {
      server.kill();
      client.kill();
    });

    final response = await socks5HttpGet(
      socksPort,
      '127.0.0.1',
      httpTarget.port,
    );
    expect(
      response,
      isNotNull,
      reason: 'real VLESS+REALITY tunnel should have carried the request',
    );
    expect(response, contains(LocalHttpTarget.responseBody));
    expect(response, startsWith('HTTP/1.1 200'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('VLESS+REALITY: a wrong (but well-formed) REALITY public key is '
      'rejected -- validation is not weakened', () async {
    if (singBoxBin == null || !haveOpenssl) {
      markTestSkipped('sing-box binary or openssl not available.');
      return;
    }

    final decoy = await spawnLocalTls13Decoy(workDir);
    addTearDown(decoy.stop);

    final realityPort = await _freePort();
    final socksPort = await _freePort();

    final serverConfig = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'vless',
          'tag': 'vless-reality-in',
          'listen': '127.0.0.1',
          'listen_port': realityPort,
          'users': [
            {
              'name': 'interop-test-user',
              'uuid': _testUuid,
              'flow': 'xtls-rprx-vision',
            },
          ],
          'tls': {
            'enabled': true,
            'server_name': LocalDecoy.hostname,
            'reality': {
              'enabled': true,
              'handshake': {
                'server': LocalDecoy.hostname,
                'server_port': decoy.port,
              },
              'private_key': _testPrivateKey,
              'short_id': [_testShortId],
            },
          },
        },
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
      ],
    };
    final serverConfigPath = '${workDir.path}/server_neg.json';
    await File(serverConfigPath).writeAsString(jsonEncode(serverConfig));
    await checkSingBoxConfig(singBoxBin!, serverConfigPath);

    // Same builder, deliberately wrong public key -- a different real
    // X25519 key, not a malformed string, so this actually exercises
    // the REALITY handshake's cryptographic check rather than input
    // validation.
    // `final`, not `const` -- same reason as the positive test above.
    final params = VlessRealityParams(
      tag: 'reality-test',
      server: '127.0.0.1',
      serverPort: realityPort,
      uuid: _testUuid,
      sni: LocalDecoy.hostname,
      publicKey: _wrongPublicKey,
      shortId: _testShortId,
    );
    final clientConfig = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': socksPort,
        },
      ],
      'outbounds': [
        params.toOutboundJson(),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': 'reality-test'},
    };
    final clientConfigPath = '${workDir.path}/client_neg.json';
    await File(clientConfigPath).writeAsString(jsonEncode(clientConfig));

    final server = await runSingBox(singBoxBin!, serverConfigPath);
    final client = await runSingBox(singBoxBin!, clientConfigPath);
    addTearDown(() {
      server.kill();
      client.kill();
    });

    final response = await socks5HttpGet(
      socksPort,
      '127.0.0.1',
      1, // no target needed -- expected to fail before this matters
      timeout: const Duration(seconds: 10),
    );
    expect(
      response,
      isNull,
      reason: 'a wrong REALITY public key must not tunnel traffic',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}
