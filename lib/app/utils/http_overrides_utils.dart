// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:io';

class HttpOverridesUtils {
  HttpOverridesUtils._();

  static void install() {
    HttpOverrides.global = _AppHttpOverrides();
  }
}

class _AppHttpOverrides extends HttpOverrides {}
