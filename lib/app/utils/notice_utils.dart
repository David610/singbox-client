// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:convert';

/// Parsed shape of a remote notice/announcement JSON document, shared by
/// [package:karing/app/utils/karing_utils.dart]'s and this file's notice
/// fetchers, and consumed by `NoticeManager`/`BoardProviderNoticeManager`.
class RawNoticeItem {
  RawNoticeItem({
    required this.updateTime,
    required this.expireTime,
    required this.title,
    required this.content,
    required this.url,
  });

  int updateTime;
  int expireTime;
  String title;
  String content;
  String url;

  static RawNoticeItem? tryParse(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final map = json;
    return RawNoticeItem(
      updateTime: (map['update_time'] as num?)?.toInt() ?? 0,
      expireTime: (map['expire_time'] as num?)?.toInt() ?? 0,
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
    );
  }
}

class NoticeUtils {
  NoticeUtils._();

  static Future<RawNoticeItem?> parseNotice(String content) async {
    try {
      return RawNoticeItem.tryParse(jsonDecode(content));
    } catch (_) {
      return null;
    }
  }
}
