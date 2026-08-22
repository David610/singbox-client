// This app ships with no third-party crash/analytics telemetry (see
// docs/CLIENT_PRODUCTION_BASELINE.md "Privacy"). This file used to wrap
// sentry_flutter; it's kept as a local no-op with the same call sites'
// signatures so main.dart/server_manager.dart/feedback_screen.dart don't
// each need their own conditional, but nothing here leaves the device --
// captureException just goes through the existing redacted app log
// (lib/app/utils/log.dart), which is the "local sanitized logs" this
// project's privacy posture calls for instead of invisible telemetry.
library;

import 'package:flutter/widgets.dart';
import 'package:karing/app/utils/log.dart';

class SentryUtils {
  SentryUtils._();

  static void captureException(
    String context,
    List<dynamic> extra,
    dynamic err,
    StackTrace? stacktrace, {
    Map<String, String>? attachments,
  }) {
    Log.e('$context: $err');
  }

  static void feedback(String message) {
    // No remote feedback channel is wired up (see the note above); logged
    // locally only so the call site doesn't need special-casing.
    Log.i('feedback: $message');
  }

  static NavigatorObserver getOvserver() {
    return NavigatorObserver();
  }
}
