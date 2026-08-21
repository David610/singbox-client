import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

class _FakeVpnCorePlatform extends VpnCorePlatform {
  VpnCoreStatus _status = VpnCoreStatus.disconnected;
  final _controller = StreamController<VpnCoreStatus>.broadcast();
  List<String> logs = const [];
  String version = '1.13.19';

  void emit(VpnCoreStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start(VpnCoreConfig config) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> restart(VpnCoreConfig config) async {}

  @override
  Future<VpnCoreStatus> status() async => _status;

  @override
  Stream<VpnCoreStatus> statusStream() => _controller.stream;

  @override
  Future<String> coreVersion() async => version;

  @override
  Future<List<String>> getSanitizedLogs({int maxLines = 200}) async => logs;
}

class _FakeIpEcho implements IpEchoService {
  _FakeIpEcho(this.ip);
  final String? ip;
  int callCount = 0;
  @override
  Future<String?> currentPublicIp() async {
    callCount++;
    return ip;
  }
}

void main() {
  late _FakeVpnCorePlatform fake;
  late DiagnosticsCollector collector;

  const app = AppContext(
    appVersion: '1.2.24+2704',
    appBuildSha: 'a1b2c3d4e5f6',
    platform: 'android',
    osVersion: '14',
    serverHostname: '127.0.0.1',
    selectedTransport: 'vless-reality',
    vlessUuidForCorrelation: '9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
  );

  setUp(() {
    fake = _FakeVpnCorePlatform();
    VpnCorePlatform.instance = fake;
  });

  tearDown(() => collector.dispose());

  test('captureStatic reflects current VPN state and never leaks the UUID', () async {
    fake.emit(const VpnCoreStatus(state: VpnCoreState.connected, activeTag: 'Reality'));
    collector = DiagnosticsCollector();

    final snap = await collector.captureStatic(app);

    expect(snap.vpnState, VpnCoreState.connected);
    expect(snap.selectedProfileLabel, 'Reality');
    expect(snap.vpnCoreVersion, '1.13.19');
    expect(snap.profileIdentifierRedacted, isNotNull);
    expect(snap.profileIdentifierRedacted, isNot(contains('9c7e12d1')));
    expect(snap.profileIdentifierRedacted, endsWith('88d9'));
  });

  test('build SHA longer than 12 chars is truncated, not rejected', () async {
    collector = DiagnosticsCollector();
    const longSha = AppContext(
      appVersion: '1.0.0',
      appBuildSha: 'a1b2c3d4e5f6g7h8i9j0',
      platform: 'ios',
      osVersion: '18.0',
    );
    final snap = await collector.captureStatic(longSha);
    expect(snap.appBuildSha.length, lessThanOrEqualTo(12));
  });

  test('reconnect count increments only on a genuine re-connection, not the first connect', () async {
    collector = DiagnosticsCollector();
    fake.emit(const VpnCoreStatus(state: VpnCoreState.connecting));
    fake.emit(const VpnCoreStatus(state: VpnCoreState.connected, activeTag: 't'));
    await Future<void>.delayed(Duration.zero);

    var snap = await collector.captureStatic(app);
    expect(snap.reconnectCount, 0);

    fake.emit(const VpnCoreStatus(state: VpnCoreState.disconnected));
    fake.emit(const VpnCoreStatus(state: VpnCoreState.connected, activeTag: 't'));
    await Future<void>.delayed(Duration.zero);

    snap = await collector.captureStatic(app);
    expect(snap.reconnectCount, 1);
  });

  test('tunnel uptime is null when disconnected and non-null once connected', () async {
    collector = DiagnosticsCollector();
    var snap = await collector.captureStatic(app);
    expect(snap.tunnelUptime, isNull);

    fake.emit(const VpnCoreStatus(state: VpnCoreState.connected, activeTag: 't'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    snap = await collector.captureStatic(app);
    expect(snap.tunnelUptime, isNotNull);
  });

  test('lastEngineError picks the most recent error-looking log line, sanitized', () async {
    fake.logs = [
      '[info] starting',
      '[info] connected uuid: 9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
      '[error] handshake failed for reality-in: REALITY: processed invalid connection',
    ];
    collector = DiagnosticsCollector();
    final snap = await collector.captureStatic(app);
    expect(snap.lastEngineError, contains('handshake failed'));
    expect(snap.lastEngineError, isNot(contains('9c7e12d1')));
  });

  test('lastEngineError is null when no log line looks like an error', () async {
    fake.logs = ['[info] starting', '[info] connected'];
    collector = DiagnosticsCollector();
    final snap = await collector.captureStatic(app);
    expect(snap.lastEngineError, isNull);
  });

  test('captureWithProbes only queries public IP when explicitly requested', () async {
    final fakeIp = _FakeIpEcho('203.0.113.10');
    // Deterministic/offline: points every probe at a closed local port
    // instead of the real internet, so this test's assertion (does the
    // collector call the IP-echo service or not) doesn't depend on
    // network availability. Real probe behavior against real sockets is
    // covered separately in network_probes_test.dart.
    const offlineProbes = NetworkProbes(
      timeout: Duration(milliseconds: 200),
      ipv4ProbeHost: '127.0.0.1',
      ipv6ProbeHost: '::1',
      dnsProbeHost: '127.0.0.1',
      quicProbeHost: '127.0.0.1',
      probePort: 1,
      dnsPort: 1,
    );
    collector = DiagnosticsCollector(probes: offlineProbes, ipEcho: fakeIp);

    final withoutIp = await collector.captureWithProbes(app);
    expect(withoutIp.publicIpAfter, isNull);
    expect(fakeIp.callCount, 0);

    final withIp = await collector.captureWithProbes(app, includePublicIp: true);
    expect(withIp.publicIpAfter, '203.0.113.10');
    expect(fakeIp.callCount, 1);
  });

  test('capturePublicIpBaseline sets publicIpBefore on later snapshots', () async {
    final fakeIp = _FakeIpEcho('198.51.100.7');
    collector = DiagnosticsCollector(ipEcho: fakeIp);

    var snap = await collector.captureStatic(app);
    expect(snap.publicIpBefore, isNull);

    final baseline = await collector.capturePublicIpBaseline();
    expect(baseline, '198.51.100.7');

    snap = await collector.captureStatic(app);
    expect(snap.publicIpBefore, '198.51.100.7');
  });
}
