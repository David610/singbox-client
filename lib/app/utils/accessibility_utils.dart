// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

class AccessibilityUtils {
  AccessibilityUtils._();

  static bool _enabled = true;

  static bool getAccessibilityEnabled() => _enabled;

  static void setAccessibilityEnabled(bool enabled) {
    _enabled = enabled;
  }

  static void announce(BuildContext context, String message) {
    if (!_enabled || message.isEmpty) {
      return;
    }
    SemanticsService.announce(message, Directionality.of(context));
  }
}
