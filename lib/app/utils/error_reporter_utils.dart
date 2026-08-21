// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class ErrorReporterUtils {
  ErrorReporterUtils._();

  static void Function()? _onNoSpace;

  static void register(void Function()? onNoSpace) {
    _onNoSpace = onNoSpace;
  }

  static void tryReportNoSpace(String message) {
    if (message.toLowerCase().contains('no space') ||
        message.toLowerCase().contains('enospc')) {
      _onNoSpace?.call();
    }
  }
}
