// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:karing/app/utils/platform_utils.dart';

class DeviceUtils {
  DeviceUtils._();

  /// Whether this device's OS already manages screen-orientation lock
  /// itself (so the app shouldn't fight it with `SystemChrome`). Tablets
  /// and desktop platforms: true. Phones: false.
  static Future<bool> disableOrientation() async {
    return !PlatformUtils.isMobile();
  }
}
