// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Upstream Karing's Sentry DSN/org/project values lived here and were
// never present in this fork -- they are this project's own operator's
// secret to supply, not something to fabricate. Left blank: sentry_flutter
// no-ops (does not initialize/report) when given an empty DSN, which is
// the correct, honest behavior until a real DSN is configured, rather
// than silently reporting to nowhere while claiming success.
library;

import 'package:sentry_flutter/sentry_flutter.dart';

class SentryUtilsPrivate {
  SentryUtilsPrivate._();

  static const String dsn = '';

  static Future<void> init() async {
    if (dsn.isEmpty) {
      return;
    }
    await SentryFlutter.init((options) {
      options.dsn = dsn;
    });
  }
}
