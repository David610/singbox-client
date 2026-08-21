import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

DiagnosticsSnapshot _snapshotWithLeakAttempt() {
  return DiagnosticsSnapshot(
    capturedAt: DateTime.utc(2026, 8, 21, 12),
    appVersion: '1.2.24+2704',
    appBuildSha: 'a1b2c3d4e5f6',
    platform: 'android',
    osVersion: '14',
    vpnState: VpnCoreState.connected,
    selectedProfileLabel: 'Reality',
    selectedTransport: 'vless-reality',
    vpnCoreVersion: '1.13.19',
    serverHostname: 'vpn.singboxvpn.test.invalid',
    publicIpBefore: '203.0.113.5',
    publicIpAfter: '203.0.113.10',
    ipv4: ProbeResult.pass(latency: const Duration(milliseconds: 40)),
    ipv6: ProbeResult.fail(detail: 'network unreachable'),
    dns: ProbeResult.pass(latency: const Duration(milliseconds: 12)),
    tcp: ProbeResult.pass(latency: const Duration(milliseconds: 38)),
    udp: ProbeResult.pass(latency: const Duration(milliseconds: 15)),
    quicHeuristic: ProbeResult.pass(detail: 'UDP/443 send accepted (heuristic only)'),
    approximateLatency: const Duration(milliseconds: 38),
    tunnelUptime: const Duration(minutes: 5, seconds: 12),
    reconnectCount: 1,
    // Deliberately smuggling credential-shaped content into fields that
    // shouldn't have it (a malformed detail string, an engine error
    // containing raw config) -- these tests exist to prove the exporter's
    // whole-bundle redaction pass catches this even when a field is
    // misused, not just the well-behaved case.
    lastEngineError:
        'handshake failed for outbound uuid: 9c7e12d1-64c3-46f2-9e21-d707f05c88d9 '
        'pbk=anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w',
    profileIdentifierRedacted: '****88d9',
  );
}

void main() {
  const exporter = DiagnosticsExporter();

  group('exportJson', () {
    test('contains the expected safe fields', () {
      final json = exporter.exportJson(_snapshotWithLeakAttempt());
      expect(json, contains('vpn.singboxvpn.test.invalid'));
      expect(json, contains('1.13.19'));
      expect(json, contains('203.0.113.10'));
      expect(json, contains('reconnectCount'));
    });

    test('never contains a credential, even one smuggled into lastEngineError', () {
      final json = exporter.exportJson(_snapshotWithLeakAttempt());
      expect(json.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
      expect(json.contains('anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'), isFalse);
    });

    test('is valid, parseable JSON after redaction', () {
      // Proves the whole-bundle redaction pass (string substitution)
      // didn't corrupt JSON syntax while masking values -- a real risk
      // for any regex-based post-processing of already-serialized JSON.
      final json = exporter.exportJson(_snapshotWithLeakAttempt());
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['vpnCoreVersion'], '1.13.19');
      expect(decoded['lastEngineError'], isNot(contains('9c7e12d1')));
    });
  });

  group('exportText', () {
    test('contains the expected safe fields', () {
      final text = exporter.exportText(_snapshotWithLeakAttempt());
      expect(text, contains('singbox-client diagnostics'));
      expect(text, contains('vpn.singboxvpn.test.invalid'));
      expect(text, contains('reconnect count: 1'));
    });

    test('never contains a credential, even one smuggled into lastEngineError', () {
      final text = exporter.exportText(_snapshotWithLeakAttempt());
      expect(text.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
      expect(text.contains('anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'), isFalse);
    });

    test('formats tunnel uptime as h/m/s', () {
      final text = exporter.exportText(_snapshotWithLeakAttempt());
      expect(text, contains('tunnel uptime: 0h 5m 12s'));
    });

    test('reports "not connected" when uptime is null', () {
      final snap = DiagnosticsSnapshot(
        capturedAt: DateTime.utc(2026, 8, 21),
        appVersion: '1.0.0',
        appBuildSha: 'abc123',
        platform: 'ios',
        osVersion: '18.0',
        vpnState: VpnCoreState.disconnected,
        ipv4: ProbeResult.unknown,
        ipv6: ProbeResult.unknown,
        dns: ProbeResult.unknown,
        tcp: ProbeResult.unknown,
        udp: ProbeResult.unknown,
        quicHeuristic: ProbeResult.unknown,
        reconnectCount: 0,
      );
      expect(exporter.exportText(snap), contains('tunnel uptime: not connected'));
    });
  });

  group('exportFullLog', () {
    test('redacts credentials across multiple log lines', () {
      final out = exporter.exportFullLog([
        '[info] starting core version 1.13.19',
        '[info] outbound[0] uuid: 9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
        '[error] REALITY: processed invalid connection',
      ]);
      expect(out.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
      expect(out, contains('1.13.19'));
      expect(out, contains('REALITY: processed invalid connection'));
    });
  });
}
