// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:karing/app/utils/platform_utils.dart';
import 'package:move_to_background/move_to_background.dart';

class MoveToBackgroundUtils {
  MoveToBackgroundUtils._();

  static Future<void> moveToBackground({Duration? duration}) async {
    if (!PlatformUtils.android) {
      return;
    }
    if (duration != null) {
      await Future.delayed(duration);
    }
    try {
      await MoveToBackground.moveTaskToBack();
    } catch (_) {}
  }
}
