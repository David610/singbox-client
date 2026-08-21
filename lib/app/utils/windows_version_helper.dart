// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Windows-only version-gating helper; out of scope for the Android/iOS
// mobile VPN target of this milestone (see docs/ARCHITECTURE.md
// "Remaining incompatibilities"). Every call site guards use of this with
// `Platform.isWindows`, so a constant `false` here is inert on all other
// platforms and only disables the Windows-specific branch it guards until
// a real Win32 version check is implemented.
library;

import 'dart:io';

class VersionHelper {
  VersionHelper._();

  static final VersionHelper instance = VersionHelper._();

  bool get isWindows10RS5OrGreater => false;

  /// Real Windows major version number, parsed from
  /// `Platform.operatingSystemVersion` (e.g. "Windows 10.0.19045" -> 10);
  /// 0 on any non-Windows platform or if parsing fails.
  int get majorVersion {
    if (!Platform.isWindows) return 0;
    final match = RegExp(r'(\d+)\.\d+\.\d+').firstMatch(Platform.operatingSystemVersion);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }
}
