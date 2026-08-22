// ignore_for_file: empty_catches, unused_catch_stack

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/file_saver.dart';
import 'package:karing/app/utils/path_utils.dart';

class NoticeItem {
  bool readed = true;
  String updateTime = "";
  String expireTime = "";
  String title = "";
  String content = "";
  String url = "";

  Map<String, dynamic> toJson() => {
    "readed": readed,
    'update_time': updateTime,
    'expire_time': expireTime,
    "title": title,
    "content": content,
    "url": url,
  };
  void fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }
    readed = map["readed"] ?? true;
    updateTime = map["update_time"] ?? "";
    expireTime = map["expire_time"] ?? "";
    title = map["title"] ?? "";
    content = map["content"] ?? "";
    url = map["url"] ?? "";
  }

  static NoticeItem fromJsonStatic(Map<String, dynamic>? map) {
    NoticeItem config = NoticeItem();
    config.fromJson(map);
    return config;
  }
}

class Notice {
  String latestCheck = "";
  List<NoticeItem> items = [];

  Map<String, dynamic> toJson() => {
    'latest_check': latestCheck,
    "items": items,
  };
  void fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }

    latestCheck = map["latest_check"] ?? "";
    var its = map["items"];
    var now = DateTime.now();
    for (var i in its) {
      NoticeItem item = NoticeItem.fromJsonStatic(i);
      DateTime? et = DateTime.tryParse(item.expireTime);
      DateTime? ut = DateTime.tryParse(item.updateTime);
      if (et != null && now.isAfter(et)) {
        continue;
      }
      if (ut != null && now.difference(ut).inDays > 30) {
        continue;
      }

      items.add(item);
    }
    items.sort(sort);
  }

  static Notice fromJsonStatic(Map<String, dynamic>? map) {
    Notice config = Notice();
    config.fromJson(map);
    return config;
  }

  NoticeItem? getByUpdateTime(String updateTime) {
    for (var i in items) {
      if (i.updateTime == updateTime) {
        return i;
      }
    }
    return null;
  }

  NoticeItem? getFirstUnread() {
    for (var i in items) {
      if (i.readed == false) {
        return i;
      }
    }
    return null;
  }

  int sort(NoticeItem a, NoticeItem b) {
    DateTime ua = DateTime.parse(a.updateTime);
    DateTime ub = DateTime.parse(b.updateTime);

    return ub.compareTo(ua);
  }
}

// This used to also poll `https://dot.karing.app/notice2.json` (via
// KaringUtils.getNotice/HttpUtils) on startup, VPN connect, app resume,
// and every 3 hours after that -- a silent third-party control-plane
// fetch that could push arbitrary "notice" content/links into the app.
// That network check has been deleted, not repointed: this class is now
// a pure local cache (load/save the last notices this app ever saw, if
// any were cached from before this change) with no way to add new ones.
class NoticeLoadAndCheck {
  final FileSaver _fileSaver = FileSaver();
  Notice _notice = Notice();

  String name = "";
  String filePath = "";

  Notice get notice => _notice;

  Future<Notice> _loadConfig(String filePath) async {
    var file = File(filePath);
    bool exists = await file.exists();
    if (!exists) {
      return Notice();
    }
    try {
      String content = await file.readAsString();
      if (content.isNotEmpty) {
        var config = jsonDecode(content);
        Notice notice = Notice();
        notice.fromJson(config);
        return notice;
      }
    } catch (err, stacktrace) {}
    return Notice();
  }

  Future<void> load() async {
    if (filePath.isEmpty) {
      return;
    }
    _notice = await _loadConfig(filePath);
  }

  void clear() {
    _notice.latestCheck = "";
    _notice.items.clear();
  }

  Future<void> save() async {
    if (filePath.isEmpty) {
      return;
    }
    _fileSaver.setSavePath(filePath);
    await _fileSaver.saveAsJson(_notice);
  }
}

class NoticeManager {
  // Kept as a no-op event list so existing screens that subscribe to
  // "a new notice arrived" continue to compile; it is never fired since
  // nothing populates new notices anymore.
  static final List<void Function()> onEventCheck = [];

  static final NoticeLoadAndCheck _selfNotice = NoticeLoadAndCheck();

  static Future<void> init() async {
    _selfNotice.filePath = await PathUtils.noticeFilePath();
    await _selfNotice.load();
  }

  static Future<void> uninit() async {}

  static List<Notice> getNotices() {
    return [_selfNotice.notice];
  }

  static Future<void> save() async {
    await _selfNotice.save();
  }
}
