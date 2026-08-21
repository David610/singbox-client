// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Desktop main-process/service IPC channel (Windows/macOS/Linux
// background-service coordination); out of scope for the Android/iOS
// mobile VPN target of this milestone.
library;

class MainChannel {
  MainChannel._();

  static void init() {}

  static void uninit() {}

  static Future<String?> call(String command, Map<String, dynamic> args) async {
    return null;
  }
}
