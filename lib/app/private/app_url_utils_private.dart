// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Upstream Karing's `lib/app/private/` held org-internal endpoints (their
// own "board provider" integration backend) that were never present in
// this fork and aren't this fork's to invent -- there is no equivalent
// backend for this project. Every URL is deliberately blank; callers
// treat an empty URL as "no request to make" via their own existing
// error-handling path, so this never silently claims success against a
// backend that doesn't exist.
library;

import 'package:tuple/tuple.dart';

class BoardProviderPrivate {
  BoardProviderPrivate._();

  static Tuple3<String, String, String> getBycodeUrlAndBody({
    required String app,
    required String version,
    required String did,
    required String code,
  }) {
    return const Tuple3('', '', '');
  }

  static Tuple3<String, String, String> getNotifyIntegrationUrlAndBody({
    required String app,
    required String version,
    required String did,
    required String url,
    required String type,
  }) {
    return const Tuple3('', '', '');
  }

  static Tuple3<String, String, String> getNoticePushUrlAndBody({
    required String app,
    required String version,
    required String did,
    required String pid,
  }) {
    return const Tuple3('', '', '');
  }
}
