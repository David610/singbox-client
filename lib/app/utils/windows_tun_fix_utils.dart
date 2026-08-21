// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Windows-only (Wintun driver reinstall helper); out of scope for the
// Android/iOS mobile VPN target of this milestone.
library;

class WindowsTunFixUtils {
  WindowsTunFixUtils._();

  static Future<void> removeDriver() async {
    throw UnimplementedError(
      'WindowsTunFixUtils.removeDriver is a Windows-only Wintun driver '
      'helper not reimplemented in this fork; see docs/ARCHITECTURE.md.',
    );
  }
}
