// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/http_utils.dart';
import 'package:karing/app/utils/notice_utils.dart';

class KaringUtils {
  KaringUtils._();

  static Future<ReturnResult<RawNoticeItem>> getNotice(
    String url,
    bool onlyWhenConnected,
  ) async {
    final result = await HttpUtils.httpGetRequest(
      url,
      null,
      await HttpUtils.getUserAgent(),
      const Duration(seconds: 10),
      null,
      null,
      checkStatuscode: false,
    );
    if (result.error != null || result.data == null) {
      return ReturnResult(error: result.error);
    }
    final notice = await NoticeUtils.parseNotice(result.data!.item2);
    if (notice == null) {
      return ReturnResult(
        error: ReturnResultError('invalid notice content', report: false),
      );
    }
    return ReturnResult(data: notice);
  }
}
