// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// iCloud backup/sync requires an iCloud-storage plugin and container
// entitlement not present in this fork (no such dependency in
// pubspec.yaml, no iCloud container configured in ios/Runner). Rather
// than fabricate a fake "upload succeeded" against a container that
// doesn't exist, every operation here reports a clear, real error so the
// UI's own error-handling path (already exercised for network errors)
// surfaces it instead of silently pretending to succeed.
library;

import 'package:karing/app/runtime/return_result.dart';

class ICloudUtils {
  ICloudUtils._();

  static ReturnResultError get _unavailable => ReturnResultError(
    'iCloud backup is not available in this build.',
    report: false,
  );

  static Future<ReturnResult<List<String>>> list() async =>
      ReturnResult(error: _unavailable);

  static Future<ReturnResultError?> upload({
    required String relativePath,
    required String localPath,
  }) async => _unavailable;

  static Future<ReturnResultError?> download({
    required String relativePath,
    required String localPath,
  }) async => _unavailable;

  static Future<ReturnResultError?> delete(String relativePath) async =>
      _unavailable;
}
