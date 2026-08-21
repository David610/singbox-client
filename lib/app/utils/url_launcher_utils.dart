// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:karing/app/runtime/return_result.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlLauncherUtils {
  UrlLauncherUtils._();

  static Future<ReturnResultError?> loadUrl(
    String url, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return ReturnResultError('invalid url: $url', report: false);
    }
    try {
      final ok = await launchUrl(uri, mode: mode);
      if (!ok) {
        return ReturnResultError('failed to launch: $url', report: false);
      }
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }

  static String? reorganizationUrl(String url, String query) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    final params = Map<String, dynamic>.from(uri.queryParameters);
    for (final pair in query.split('&')) {
      final kv = pair.split('=');
      if (kv.length == 2) {
        params[kv[0]] = kv[1];
      }
    }
    return uri.replace(queryParameters: params).toString();
  }

  static Future<String> reorganizationUrlWithAnchor(
    String url, {
    String? anchor,
  }) async {
    if (anchor == null || anchor.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.replace(fragment: anchor).toString();
  }

  static Future<void> closeWebview() async {}
}
