// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:io';

import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/http_utils.dart';

class DownloadUtils {
  DownloadUtils._();

  static Future<ReturnResult<HttpHeaders>> downloadWithPort(
    Uri url,
    String savePath,
    String? userAgent,
    bool overwrite,
    int? proxyPort,
  ) async {
    return HttpUtils.httpDownload(
      url,
      savePath,
      proxyPort,
      userAgent,
      overwrite,
      const Duration(minutes: 5),
    );
  }
}
