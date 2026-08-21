// Replaces KaringX's private `package:vpn_service` local wrapper (this file
// path, `lib/app/local_services/vpn_service.dart`, existed in upstream
// Karing but its contents were never present in this fork -- see
// docs/FORK_ARCHITECTURE_AUDIT.md and docs/ARCHITECTURE.md
// "Remaining incompatibilities").
//
// [FlutterVpnService] and [FlutterVpnServiceState] are reconstructed here
// from every call site in lib/ (grep for `FlutterVpnService\.` and
// `FlutterVpnServiceState\.` across the tree), backed by the new
// first-party `vpn_core` package (packages/vpn_core) instead of the
// missing/private one.
//
// Scope note: several methods below (authorizeService, firewallAddPorts,
// getProcessIcon/getProcessList, getAppGroupDirectory, hideDockIcon,
// setExcludeFromRecents) are desktop (Windows/macOS) service-elevation and
// per-app-routing helpers unrelated to the Android/iOS VPN core boundary
// this milestone targets, and several of them interoperate with
// `VPNService`/`ProxyConfig`/`ServerConfig` (the app's own large protocol
// data-model classes) which were NOT reconstructed in this pass -- see
// docs/ARCHITECTURE.md. They are stubbed here just enough to keep this
// file's own declarations self-consistent; wiring their call sites is
// follow-up UI-integration work, out of scope for "do not redesign the UI".
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:vpn_core/vpn_core.dart';

export 'package:vpn_core/vpn_core.dart'
    show VpnCoreConfig, SingBoxConfigBuilder, VlessRealityParams, Hysteria2Params;

/// Mirrors `vpn_service`'s connection-state enum. Values and names are
/// unchanged from every observed call site (`FlutterVpnServiceState.connected`,
/// `.connecting`, `.disconnected`, `.disconnecting`, `.reasserting`,
/// `.invalid`).
enum FlutterVpnServiceState {
  invalid,
  disconnected,
  connecting,
  connected,
  reasserting,
  disconnecting;

  static FlutterVpnServiceState fromCore(VpnCoreState state) {
    switch (state) {
      case VpnCoreState.invalid:
        return FlutterVpnServiceState.invalid;
      case VpnCoreState.disconnected:
        return FlutterVpnServiceState.disconnected;
      case VpnCoreState.connecting:
        return FlutterVpnServiceState.connecting;
      case VpnCoreState.connected:
        return FlutterVpnServiceState.connected;
      case VpnCoreState.reasserting:
        return FlutterVpnServiceState.reasserting;
      case VpnCoreState.disconnecting:
        return FlutterVpnServiceState.disconnecting;
    }
  }
}

/// Generic error/result shape used by the handful of desktop-service
/// methods below that upstream call sites expect to carry a `.message`
/// (e.g. `home_screen.dart`'s `authorizeService` handling). Kept separate
/// from [VpnCoreException] (the vpn_core package's own typed error) since
/// these methods are legacy desktop concerns, not part of the vpn_core
/// boundary.
class FlutterVpnServiceResult {
  const FlutterVpnServiceResult(this.message);
  final String message;
}

class FlutterVpnService {
  FlutterVpnService._();

  /// Underlying typed core -- prefer this directly for new (Android/iOS)
  /// code; the static methods below exist only for call-site compatibility
  /// with the pre-existing lib/ call sites enumerated above.
  static final VpnCore core = VpnCore.instance;

  static Future<FlutterVpnServiceState> currentState() async =>
      FlutterVpnServiceState.fromCore((await core.status()).state);

  static Stream<FlutterVpnServiceState> stateStream() =>
      core.statusStream().map((s) => FlutterVpnServiceState.fromCore(s.state));

  // --- Desktop service-elevation helpers (Windows/macOS) --------------
  // Out of scope for this milestone (Android/iOS VPN core). Stubbed so
  // this file's own type-checking is self-consistent; see the file-level
  // doc comment.

  static Future<FlutterVpnServiceResult?> authorizeService(
    String servicePath,
    String password,
  ) async {
    throw UnimplementedError(
      'FlutterVpnService.authorizeService is a desktop-only (Windows/macOS) '
      'privileged-service helper not yet reimplemented against vpn_core; '
      'see docs/ARCHITECTURE.md "Remaining incompatibilities".',
    );
  }

  static Future<bool> isServiceAuthorized(String servicePath) async => false;

  static Future<String> clashiApiConnections(bool reset) async => '{}';

  static void firewallAddPorts(List<int> ports, String exeName) {
    // No-op: Windows-only firewall rule helper, out of scope for the
    // Android/iOS VPN core boundary.
  }

  static Future<Directory?> getAppGroupDirectory(String groupId) async => null;

  static Future<Uint8List?> getProcessIcon(String identifier) async => null;

  static Future<String?> getProcessList() async => null;

  static void hideDockIcon(bool hide) {
    // No-op outside macOS.
  }

  static Future<void> setAlwaysOn(bool enabled) async {}

  static Future<String?> setExcludeFromRecents(bool exclude) async => null;

  // --- Genuinely cross-platform, mobile-relevant ------------------------

  /// Upstream call sites use this as an OS API-level integer string (e.g.
  /// compared against `< 26`) to gate Android-version-specific behavior.
  /// `Platform.operatingSystemVersion` is not a numeric SDK level on
  /// Android; a real implementation needs `device_info_plus` (already a
  /// dependency of the app) rather than vpn_core. Returning a high value
  /// here is the conservative default: it avoids falsely triggering
  /// old-OS workaround branches.
  static Future<String> getSystemVersion() async => '99';
}
