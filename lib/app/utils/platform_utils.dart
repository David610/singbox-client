// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

class PlatformUtils {
  PlatformUtils._();

  static bool get android => !kIsWeb && Platform.isAndroid;
  static bool get ios => !kIsWeb && Platform.isIOS;
  static bool get macos => !kIsWeb && Platform.isMacOS;
  static bool get windows => !kIsWeb && Platform.isWindows;
  static bool get linux => !kIsWeb && Platform.isLinux;

  static bool isMobile() => android || ios;
  static bool isPC() => windows || macos || linux;
}
