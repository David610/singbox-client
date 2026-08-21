import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_vpn_core.dart';
import 'models.dart';

/// The full contract a platform implementation (Android/iOS/desktop) must
/// satisfy. This is deliberately the ONLY seam between the Flutter app and
/// native code — see docs/ARCHITECTURE.md "Dart <-> native boundary" for why
/// it is kept this small instead of exposing sing-box's full option surface.
abstract class VpnCorePlatform extends PlatformInterface {
  VpnCorePlatform() : super(token: _token);

  static final Object _token = Object();

  static VpnCorePlatform _instance = MethodChannelVpnCore();

  static VpnCorePlatform get instance => _instance;

  /// Platform implementations, and tests, set this to inject themselves.
  static set instance(VpnCorePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// One-time setup: working directories, log limits, etc. Must be called
  /// before [start]. Idempotent.
  Future<void> initialize();

  /// Starts (or replaces) the tunnel with [config]. Returns once the
  /// platform VPN permission has been granted and the core has accepted the
  /// configuration — not once the first connection succeeds, since sing-box
  /// dials outbounds lazily/on demand.
  Future<void> start(VpnCoreConfig config);

  /// Stops the tunnel. Safe to call when already stopped.
  Future<void> stop();

  /// Convenience for "stop, then start with a new config" without the UI
  /// observing an intermediate disconnected flicker where avoidable.
  Future<void> restart(VpnCoreConfig config);

  Future<VpnCoreStatus> status();

  /// Stream of status changes, e.g. for driving a connection indicator.
  Stream<VpnCoreStatus> statusStream();

  /// The exact upstream sing-box version string (e.g. "1.13.19"), sourced
  /// from `libbox.Version()` at runtime — never hand-maintained, so it can
  /// never drift from what is actually linked into the app.
  Future<String> coreVersion();

  /// Recent core log lines with credentials redacted (see
  /// docs/ARCHITECTURE.md "Log redaction"). Never returns raw config JSON.
  Future<List<String>> getSanitizedLogs({int maxLines = 200});
}
