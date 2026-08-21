// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

typedef VpnAction = Future<void> Function(String source, bool background);

class VpnActionHandler {
  VpnActionHandler._();

  static VpnAction? vpnConnect;
  static VpnAction? vpnDisconnect;
  static VpnAction? vpnReconnect;
}
