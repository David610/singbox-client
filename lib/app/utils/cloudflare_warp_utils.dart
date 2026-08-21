// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// See cloudflare_warp_api.dart: Cloudflare WARP account generation is a
// separate protocol this milestone doesn't cover; reports unavailable
// rather than fabricating a registration flow.
library;

import 'package:karing/app/runtime/return_result.dart';

class WarpAccount {
  WarpAccount({
    this.privateKey = "",
    this.publicKey = "",
    this.license = "",
    this.deviceId = "",
    this.token = "",
    this.accountType = "",
    this.id = "",
    this.warpPlus = false,
    this.premiumData = 0,
  });

  String privateKey;
  String publicKey;
  String license;
  String deviceId;
  String token;
  String accountType;
  String id;
  bool warpPlus;
  int premiumData;
}

class CloudflareWarpUtils {
  CloudflareWarpUtils._();

  static ReturnResultError get _unavailable => ReturnResultError(
    'Cloudflare WARP account generation is not available in this build.',
    report: false,
  );

  static Future<ReturnResult<Map<String, dynamic>>> genFreeWarpConfig() async =>
      ReturnResult(error: _unavailable);

  static Future<ReturnResult<WarpAccount>> gen25PBWarpAccount() async =>
      ReturnResult(error: _unavailable);
}
