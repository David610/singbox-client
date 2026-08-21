// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Windows-only version-gating helper; out of scope for the Android/iOS
// mobile VPN target of this milestone (see docs/ARCHITECTURE.md
// "Remaining incompatibilities"). Every call site guards use of this with
// `Platform.isWindows`, so a constant `false` here is inert on all other
// platforms and only disables the Windows-specific branch it guards until
// a real Win32 version check is implemented.
library;

class VersionHelper {
  VersionHelper._();

  static final VersionHelper instance = VersionHelper._();

  bool get isWindows10RS5OrGreater => false;
}
