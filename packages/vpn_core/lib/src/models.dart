/// Connection state of the tunnel, mirrored 1:1 from the platform side.
///
/// Deliberately small and stable: this is the contract the Flutter app
/// depends on, so it changes only when the underlying platform state
/// machine genuinely changes shape.
enum VpnCoreState {
  invalid,
  disconnected,
  connecting,
  connected,
  reasserting,
  disconnecting,
}

VpnCoreState vpnCoreStateFromWire(String value) {
  switch (value) {
    case 'connecting':
      return VpnCoreState.connecting;
    case 'connected':
      return VpnCoreState.connected;
    case 'reasserting':
      return VpnCoreState.reasserting;
    case 'disconnecting':
      return VpnCoreState.disconnecting;
    case 'disconnected':
      return VpnCoreState.disconnected;
    default:
      return VpnCoreState.invalid;
  }
}

String vpnCoreStateToWire(VpnCoreState state) => state.name;

/// A fully-resolved sing-box configuration ready to hand to the native core.
///
/// [singBoxConfigJson] is a complete sing-box configuration document (the
/// same JSON shape `sing-box run -c config.json` accepts). Building that
/// JSON from a user profile (VLESS/REALITY/Hysteria2/Salamander parameters,
/// routing rules, DNS) is the job of [SingBoxConfigBuilder] — this class is
/// intentionally just a typed envelope, so the Dart<->native boundary never
/// has to know about protocol internals.
class VpnCoreConfig {
  const VpnCoreConfig({required this.tag, required this.singBoxConfigJson});

  /// Human-readable identifier for the active profile/server, used only for
  /// logging and status reporting. Never put secrets in this field.
  final String tag;

  final String singBoxConfigJson;

  Map<String, Object?> toWire() => {
    'tag': tag,
    'configJson': singBoxConfigJson,
  };
}

class VpnCoreStatus {
  const VpnCoreStatus({
    required this.state,
    this.uplinkBytes = 0,
    this.downlinkBytes = 0,
    this.activeTag,
  });

  final VpnCoreState state;
  final int uplinkBytes;
  final int downlinkBytes;
  final String? activeTag;

  factory VpnCoreStatus.fromWire(Map<Object?, Object?> wire) {
    return VpnCoreStatus(
      state: vpnCoreStateFromWire(wire['state'] as String? ?? ''),
      uplinkBytes: (wire['uplinkBytes'] as num?)?.toInt() ?? 0,
      downlinkBytes: (wire['downlinkBytes'] as num?)?.toInt() ?? 0,
      activeTag: wire['activeTag'] as String?,
    );
  }

  static const disconnected = VpnCoreStatus(state: VpnCoreState.disconnected);
}

/// Thrown for any failure crossing the Dart<->native boundary (permission
/// denied, core start failure, invalid config, ...). [code] is a stable,
/// machine-readable string; [message] is safe to show to a user or log —
/// implementations MUST NOT put credentials in either field.
class VpnCoreException implements Exception {
  const VpnCoreException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'VpnCoreException($code): $message';
}
