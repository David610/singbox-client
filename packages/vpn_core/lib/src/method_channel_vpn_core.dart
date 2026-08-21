import 'package:flutter/services.dart';

import 'models.dart';
import 'vpn_core_platform_interface.dart';

/// Default [VpnCorePlatform] implementation, talking to native code over a
/// single MethodChannel + a single EventChannel for status updates. This is
/// the entire native API surface of the plugin — see
/// android/.../VpnCorePlugin.kt and ios/Classes/VpnCorePlugin.swift for the
/// matching native side.
class MethodChannelVpnCore extends VpnCorePlatform {
  MethodChannelVpnCore({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _method = methodChannel ?? const MethodChannel('vpn_core/methods'),
       _events = eventChannel ?? const EventChannel('vpn_core/status');

  final MethodChannel _method;
  final EventChannel _events;

  Stream<VpnCoreStatus>? _statusStream;

  @override
  Future<void> initialize() async {
    try {
      await _method.invokeMethod<void>('initialize');
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'initialize failed');
    }
  }

  @override
  Future<void> start(VpnCoreConfig config) async {
    try {
      await _method.invokeMethod<void>('start', config.toWire());
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'start failed');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'stop failed');
    }
  }

  @override
  Future<void> restart(VpnCoreConfig config) async {
    try {
      await _method.invokeMethod<void>('restart', config.toWire());
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'restart failed');
    }
  }

  @override
  Future<VpnCoreStatus> status() async {
    try {
      final wire = await _method.invokeMapMethod<Object?, Object?>('status');
      if (wire == null) return VpnCoreStatus.disconnected;
      return VpnCoreStatus.fromWire(wire);
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'status failed');
    }
  }

  @override
  Stream<VpnCoreStatus> statusStream() {
    return _statusStream ??= _events.receiveBroadcastStream().map((event) {
      return VpnCoreStatus.fromWire(Map<Object?, Object?>.from(event as Map));
    });
  }

  @override
  Future<String> coreVersion() async {
    try {
      final version = await _method.invokeMethod<String>('coreVersion');
      return version ?? 'unknown';
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'coreVersion failed');
    }
  }

  @override
  Future<List<String>> getSanitizedLogs({int maxLines = 200}) async {
    try {
      final lines = await _method.invokeListMethod<String>('getSanitizedLogs', {
        'maxLines': maxLines,
      });
      return lines ?? const [];
    } on PlatformException catch (e) {
      throw VpnCoreException(e.code, e.message ?? 'getSanitizedLogs failed');
    }
  }
}
