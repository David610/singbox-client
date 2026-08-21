// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Windows UWP loopback-exemption helper; out of scope for the Android/iOS
// mobile VPN target of this milestone. Only reachable from
// UWPLoopbackExemptionWindowsScreen, itself only linked from Windows-only
// UI, so an empty/inert result is safe everywhere else.
library;

import 'package:karing/app/runtime/return_result.dart';

class UWPMapping {
  UWPMapping({
    required this.packageName,
    required this.displayName,
    this.sid = '',
    this.exempted = false,
  });

  String packageName;
  String displayName;
  String sid;
  bool exempted;
}

class UWPUtils {
  UWPUtils._();

  static Future<List<UWPMapping>> getMappings() async => [];

  static Future<ReturnResult<Set<String>>> getNetIsolation() async =>
      ReturnResult(data: <String>{});

  // ignore: non_constant_identifier_names
  static Future<void> SetNetIsolation(Set<String> packageNames, bool exempted) async {}
}
