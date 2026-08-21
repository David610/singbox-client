// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Sentry DSN/org configuration itself lives in lib/app/private/ (also
// reconstructed, deliberately blank -- see that file), so this reports
// nowhere until a real DSN is supplied there; the calls below are real
// sentry_flutter API usage, not fabricated.
library;

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class SentryUtils {
  SentryUtils._();

  static void captureException(
    String context,
    List<dynamic> extra,
    dynamic err,
    StackTrace? stacktrace, {
    Map<String, String>? attachments,
  }) {
    Sentry.captureException(
      err,
      stackTrace: stacktrace,
      withScope: (scope) {
        scope.setTag('context', context);
        for (var i = 0; i < extra.length; i++) {
          scope.setExtra('extra_$i', extra[i]);
        }
      },
    );
  }

  static void feedback(String message) {
    Sentry.captureFeedback(SentryFeedback(message: message));
  }

  static NavigatorObserver getOvserver() {
    return SentryNavigatorObserver();
  }
}
