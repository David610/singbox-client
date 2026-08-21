// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Cloudflare's WARP client-registration API (https://api.cloudflareclient.com)
// is a separate, undocumented-by-Cloudflare protocol unrelated to the
// sing-box/vpn_core VPN engine this milestone covers. Rather than guess at
// its request/response shape, every call here reports a clear error.
library;

import 'package:karing/app/runtime/return_result.dart';

class WarpDevice {
  WarpDevice({required this.id, this.name = ''});
  String id;
  String name;
}

class CloudflareWarpApi {
  CloudflareWarpApi._();

  static const int licenseLength = 26;

  static ReturnResultError get _unavailable => ReturnResultError(
    'Cloudflare WARP account integration is not available in this build.',
    report: false,
  );

  static Future<ReturnResult<WarpDevice>> getDevice(
    String deviceId,
    String token,
  ) async => ReturnResult(error: _unavailable);

  static Future<ReturnResult<List<WarpDevice>>> getDevices(
    String deviceId,
    String token,
  ) async => ReturnResult(error: _unavailable);
}
