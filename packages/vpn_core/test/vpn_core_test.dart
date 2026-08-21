import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

/// In-memory fake standing in for native code, so these tests exercise the
/// Dart <-> native *contract* (the platform interface) without needing a
/// device, emulator, or the real libbox binary.
class _FakeVpnCorePlatform extends VpnCorePlatform {
  bool initialized = false;
  VpnCoreConfig? lastConfig;
  VpnCoreStatus _status = VpnCoreStatus.disconnected;
  final _controller = StreamController<VpnCoreStatus>.broadcast();

  Object? failWith;

  void emit(VpnCoreStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> start(VpnCoreConfig config) async {
    if (failWith != null) throw failWith!;
    if (!initialized) {
      throw const VpnCoreException('not_initialized', 'call initialize() first');
    }
    lastConfig = config;
    emit(VpnCoreStatus(state: VpnCoreState.connected, activeTag: config.tag));
  }

  @override
  Future<void> stop() async {
    emit(VpnCoreStatus.disconnected);
  }

  @override
  Future<void> restart(VpnCoreConfig config) async {
    await stop();
    await start(config);
  }

  @override
  Future<VpnCoreStatus> status() async => _status;

  @override
  Stream<VpnCoreStatus> statusStream() => _controller.stream;

  @override
  Future<String> coreVersion() async => '1.13.19';

  @override
  Future<List<String>> getSanitizedLogs({int maxLines = 200}) async =>
      const ['[info] fake log line'];
}

void main() {
  late _FakeVpnCorePlatform fake;

  setUp(() {
    fake = _FakeVpnCorePlatform();
    VpnCorePlatform.instance = fake;
  });

  test('platform interface token prevents unverified implementations', () {
    expect(VpnCorePlatform.instance, isA<VpnCorePlatform>());
  });

  test('start requires initialize to have run first', () async {
    final config = VpnCoreConfig(tag: 'test', singBoxConfigJson: '{}');
    await expectLater(
      VpnCore.instance.start(config),
      throwsA(isA<VpnCoreException>()),
    );
  });

  test('initialize -> start -> status reflects connected state', () async {
    await VpnCore.instance.initialize();
    final config = VpnCoreConfig(tag: 'my-server', singBoxConfigJson: '{}');
    await VpnCore.instance.start(config);

    final status = await VpnCore.instance.status();
    expect(status.state, VpnCoreState.connected);
    expect(status.activeTag, 'my-server');
    expect(fake.lastConfig, same(config));
  });

  test('stop resets status to disconnected', () async {
    await VpnCore.instance.initialize();
    await VpnCore.instance.start(
      VpnCoreConfig(tag: 't', singBoxConfigJson: '{}'),
    );
    await VpnCore.instance.stop();
    expect((await VpnCore.instance.status()).state, VpnCoreState.disconnected);
  });

  test('restart replaces the active config', () async {
    await VpnCore.instance.initialize();
    final first = VpnCoreConfig(tag: 'first', singBoxConfigJson: '{}');
    final second = VpnCoreConfig(tag: 'second', singBoxConfigJson: '{}');
    await VpnCore.instance.start(first);
    await VpnCore.instance.restart(second);

    expect(fake.lastConfig, same(second));
    expect((await VpnCore.instance.status()).activeTag, 'second');
  });

  test('statusStream broadcasts state transitions', () async {
    await VpnCore.instance.initialize();
    final states = <VpnCoreState>[];
    final sub = VpnCore.instance.statusStream().listen((s) => states.add(s.state));

    await VpnCore.instance.start(
      VpnCoreConfig(tag: 't', singBoxConfigJson: '{}'),
    );
    await VpnCore.instance.stop();
    await Future<void>.delayed(Duration.zero);

    expect(states, [VpnCoreState.connected, VpnCoreState.disconnected]);
    await sub.cancel();
  });

  test('coreVersion surfaces the linked sing-box version', () async {
    expect(await VpnCore.instance.coreVersion(), '1.13.19');
  });

  test('getSanitizedLogs never returns raw config content', () async {
    final logs = await VpnCore.instance.getSanitizedLogs();
    for (final line in logs) {
      expect(line.contains('"uuid"'), isFalse);
      expect(line.contains('"password"'), isFalse);
    }
  });

  test('a platform failure surfaces as VpnCoreException, not a raw error', () async {
    await VpnCore.instance.initialize();
    fake.failWith = const VpnCoreException('permission_denied', 'user declined VPN prompt');
    await expectLater(
      VpnCore.instance.start(VpnCoreConfig(tag: 't', singBoxConfigJson: '{}')),
      throwsA(
        isA<VpnCoreException>().having((e) => e.code, 'code', 'permission_denied'),
      ),
    );
  });
}
