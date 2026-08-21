import 'models.dart';
import 'vpn_core_platform_interface.dart';

/// The entire public surface the Flutter app is allowed to depend on for
/// controlling the VPN tunnel. Intentionally 7 operations, no more — see
/// docs/ARCHITECTURE.md for the rationale ("small typed Dart API" boundary).
class VpnCore {
  VpnCore._();

  static final VpnCore instance = VpnCore._();

  Future<void> initialize() => VpnCorePlatform.instance.initialize();

  Future<void> start(VpnCoreConfig config) =>
      VpnCorePlatform.instance.start(config);

  Future<void> stop() => VpnCorePlatform.instance.stop();

  Future<void> restart(VpnCoreConfig config) =>
      VpnCorePlatform.instance.restart(config);

  Future<VpnCoreStatus> status() => VpnCorePlatform.instance.status();

  Stream<VpnCoreStatus> statusStream() =>
      VpnCorePlatform.instance.statusStream();

  Future<String> coreVersion() => VpnCorePlatform.instance.coreVersion();

  Future<List<String>> getSanitizedLogs({int maxLines = 200}) =>
      VpnCorePlatform.instance.getSanitizedLogs(maxLines: maxLines);
}
