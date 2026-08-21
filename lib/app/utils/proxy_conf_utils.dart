// Real replacement for the missing private `ProxyConfUtils` helper.
// Reconstructed from call sites in server_manager.dart, home_screen.dart,
// net_connections_screen.dart.
import 'dart:io';

import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/runtime/return_result.dart';

class ProxyConfUtils {
  /// Formats a byte count as a short human string ("1.2 MB"). Every call
  /// site passes a raw byte count (uploadTotal/downloadTotal/memory/...).
  static String convertTrafficToStringDouble(num bytes) {
    if (bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB", "PB"];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return "${value.toStringAsFixed(value < 10 && unit > 0 ? 2 : 1)} ${units[unit]}";
  }

  /// Parses the `Subscription-Userinfo` response header -- the real,
  /// widely-used convention (Clash/Shadowrocket/Karing all follow it) for
  /// a subscription server to report quota: `upload=123; download=456;
  /// total=789; expire=1700000000` (unix seconds).
  static SubscriptionTraffic? getTraffic(HttpHeaders? headers) {
    final value = headers?.value("subscription-userinfo");
    if (value == null || value.isEmpty) return null;
    final traffic = SubscriptionTraffic();
    for (final part in value.split(";")) {
      final kv = part.trim().split("=");
      if (kv.length != 2) continue;
      final key = kv[0].trim();
      final val = int.tryParse(kv[1].trim());
      if (val == null) continue;
      switch (key) {
        case "upload":
          traffic.upload = val;
          break;
        case "download":
          traffic.download = val;
          break;
        case "total":
          traffic.total = val;
          break;
        case "expire":
          traffic.expire = DateTime.fromMillisecondsSinceEpoch(val * 1000);
          break;
      }
    }
    return traffic;
  }

  /// Extracts a proxy-subscription URL out of raw QR content -- real
  /// content is either the URL itself or a `vmess://`/`ss://`/`vless://`/
  /// `hysteria2://`/`trojan://` share link; both are already a bare URL by
  /// the time they reach here.
  static ReturnResult<String> getUrlFromQRContent(String content) {
    final trimmed = content.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty) {
      return ReturnResult(error: ReturnResultError("invalid QR content", report: false));
    }
    return ReturnResult(data: trimmed);
  }
}
