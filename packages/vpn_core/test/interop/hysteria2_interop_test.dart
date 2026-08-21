// Real protocol interop test: Hysteria2 + Salamander obfuscation.
//
// Same approach as reality_interop_test.dart: a server config in
// singbox-vpn's own shape, a client outbound built by vpn_core's own
// production `Hysteria2Params`/`SingBoxConfigBuilder`, driven against a
// real pinned sing-box binary over loopback. Verifies both a TCP request
// (proves auth + Salamander obfuscation) and, separately and explicitly
// per the task's requirement, a UDP-capable path (SOCKS5 UDP ASSOCIATE
// through the tunnel to a local UDP echo target) -- Hysteria2's whole
// point over REALITY is UDP capability, so this must not be skipped.
//
// SCOPE: see reality_interop_test.dart's header -- this is a headless
// protocol test, not proof that Android/iOS VPN integration works.
//
// insecure:true is used here ONLY because the local decoy/TLS endpoint is
// self-signed and not in any trust store; vpn_core's default
// (Hysteria2Params with no `insecure` argument) never sets this -- see
// singbox_config_builder_test.dart's "omits obfs..."/redaction tests and
// docs/ARCHITECTURE.md's security section. Do not read this test's
// `insecure: true` as vpn_core weakening TLS validation by default.
@Tags(['interop'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

import 'common.dart';

const _testPassword = 'test-h2-fake-password-000';
const _testObfsPassword = 'test-salamander-fake-000';
const _wrongPassword = 'wrong-password-000';

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
      'vpn_core_hysteria2_interop_',
    );
  });

  tearDownAll(() async {
    await workDir.delete(recursive: true).catchError((_) => workDir);
  });

  Future<Map<String, Object?>> writeServerConfig({
    required int port,
    required String certPath,
    required String keyPath,
  }) async {
    final config = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'hysteria2',
          'tag': 'hysteria2-in',
          'listen': '127.0.0.1',
          'listen_port': port,
          'users': [
            {'name': 'interop-test-user', 'password': _testPassword},
          ],
          'tls': {
            'enabled': true,
            'certificate_path': certPath,
            'key_path': keyPath,
          },
          'obfs': {'type': 'salamander', 'password': _testObfsPassword},
        },
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
      ],
    };
    final path = '${workDir.path}/hy2_server_$port.json';
    await File(path).writeAsString(jsonEncode(config));
    return {'path': path};
  }

  test('Hysteria2+Salamander: generated client outbound carries a TCP request '
      'AND a UDP-relayed datagram', () async {
    if (singBoxBin == null || !haveOpenssl) {
      markTestSkipped('sing-box binary or openssl not available.');
      return;
    }

    final decoy = await spawnLocalTls13Decoy(
      workDir,
    ); // reused purely for its cert/key
    final httpTarget = await spawnLocalHttpTarget();
    final udpEcho = await spawnLocalUdpEcho();
    addTearDown(() {
      decoy.stop();
      httpTarget.stop();
      udpEcho.stop();
    });

    final hy2Port = await _freePort();
    final socksPort = await _freePort();

    final serverCfg = await writeServerConfig(
      port: hy2Port,
      certPath: decoy.certPath,
      keyPath: decoy.keyPath,
    );
    await checkSingBoxConfig(singBoxBin!, serverCfg['path'] as String);

    // Client: THE REAL vpn_core code path.
    final outbound = Hysteria2Params(
      tag: 'hy2-test',
      server: '127.0.0.1',
      serverPort: hy2Port,
      password: _testPassword,
      salamanderPassword: _testObfsPassword,
      sni: LocalDecoy.hostname,
      insecure: true, // local self-signed cert only -- see file header
    ).toOutboundJson();

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
      'route': {'final': 'hy2-test'},
    };
    final clientConfigPath = '${workDir.path}/hy2_client.json';
    await File(clientConfigPath).writeAsString(jsonEncode(clientConfig));
    await checkSingBoxConfig(singBoxBin!, clientConfigPath);

    final server = await runSingBox(singBoxBin!, serverCfg['path'] as String);
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
      reason: 'real Hysteria2+Salamander tunnel should carry TCP',
    );
    expect(response, contains(LocalHttpTarget.responseBody));

    final probe = Uint8List.fromList(
      utf8.encode('udp-over-hysteria2-interop-probe'),
    );
    final echoed = await socks5UdpEcho(
      socksPort,
      '127.0.0.1',
      udpEcho.port,
      probe,
    );
    expect(echoed, isNotNull, reason: 'Hysteria2 must relay UDP, not just TCP');
    expect(echoed, equals(probe));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'Hysteria2: a wrong password is rejected -- auth is not weakened',
    () async {
      if (singBoxBin == null || !haveOpenssl) {
        markTestSkipped('sing-box binary or openssl not available.');
        return;
      }

      final decoy = await spawnLocalTls13Decoy(workDir);
      addTearDown(decoy.stop);

      final hy2Port = await _freePort();
      final socksPort = await _freePort();

      final serverCfg = await writeServerConfig(
        port: hy2Port,
        certPath: decoy.certPath,
        keyPath: decoy.keyPath,
      );

      final outbound = Hysteria2Params(
        tag: 'hy2-test',
        server: '127.0.0.1',
        serverPort: hy2Port,
        password: _wrongPassword,
        salamanderPassword: _testObfsPassword,
        sni: LocalDecoy.hostname,
        insecure: true,
      ).toOutboundJson();

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
        'route': {'final': 'hy2-test'},
      };
      final clientConfigPath = '${workDir.path}/hy2_client_neg.json';
      await File(clientConfigPath).writeAsString(jsonEncode(clientConfig));

      final server = await runSingBox(singBoxBin!, serverCfg['path'] as String);
      final client = await runSingBox(singBoxBin!, clientConfigPath);
      addTearDown(() {
        server.kill();
        client.kill();
      });

      final response = await socks5HttpGet(
        socksPort,
        '127.0.0.1',
        1,
        timeout: const Duration(seconds: 10),
      );
      expect(
        response,
        isNull,
        reason: 'a wrong Hysteria2 password must not tunnel traffic',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}
