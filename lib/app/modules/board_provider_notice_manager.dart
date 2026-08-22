// ignore_for_file: empty_catches, unused_catch_stack

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/file_saver.dart';
import 'package:karing/app/utils/path_utils.dart';

class BoardProviderNoticeItem {
  String providerId = "";
  bool readed = true;
  String updateTime = "";
  String expireTime = "";
  String title = "";
  String content = "";
  String url = "";

  Map<String, dynamic> toJson() => {
    "provider_id": providerId,
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
    providerId = map["provider_id"] ?? "";
    readed = map["readed"] ?? true;
    updateTime = map["update_time"] ?? "";
    expireTime = map["expire_time"] ?? "";
    title = map["title"] ?? "";
    content = map["content"] ?? "";
    url = map["url"] ?? "";
  }

  static BoardProviderNoticeItem fromJsonStatic(Map<String, dynamic>? map) {
    BoardProviderNoticeItem config = BoardProviderNoticeItem();
    config.fromJson(map);
    return config;
  }
}

class BoardProviderNotice {
  String latestCheck = "";
  List<BoardProviderNoticeItem> items = [];

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
      BoardProviderNoticeItem item = BoardProviderNoticeItem.fromJsonStatic(i);
      if (item.providerId.isEmpty) {
        continue;
      }
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

  static BoardProviderNotice fromJsonStatic(Map<String, dynamic>? map) {
    BoardProviderNotice config = BoardProviderNotice();
    config.fromJson(map);
    return config;
  }

  BoardProviderNoticeItem? getByUpdateTime(
    String providerId,
    String updateTime,
  ) {
    for (var i in items) {
      if (i.providerId == providerId && i.updateTime == updateTime) {
        return i;
      }
    }
    return null;
  }

  BoardProviderNoticeItem? getFirstUnread(String providerId) {
    for (var i in items) {
      if (i.providerId == providerId && i.readed == false) {
        return i;
      }
    }
    return null;
  }

  int sort(BoardProviderNoticeItem a, BoardProviderNoticeItem b) {
    DateTime ua = DateTime.parse(a.updateTime);
    DateTime ub = DateTime.parse(b.updateTime);

    return ub.compareTo(ua);
  }
}

// This used to silently POST this device's `did` (device id), app name,
// and version to a per-provider "notice push" URL (from Karing's
// `BoardProviderPrivate.getNoticePushUrlAndBody`, always empty in this
// fork already) on startup/connect/resume/every 3h, then render whatever
// notice content came back. That entire outbound check has been deleted
// -- it was never required for the VPN to start/import/connect, and a
// per-install device id has no business being sent anywhere
// automatically. This is now a pure local cache with no way to add new
// entries.
class BoardProviderNoticeLoadAndCheck {
  final FileSaver _fileSaver = FileSaver();
  BoardProviderNotice _notice = BoardProviderNotice();

  String name = "";
  String filePath = "";
  BoardProviderNotice get notice => _notice;

  Future<BoardProviderNotice> _loadConfig(String filePath) async {
    var file = File(filePath);
    bool exists = await file.exists();
    if (!exists) {
      return BoardProviderNotice();
    }
    try {
      String content = await file.readAsString();
      if (content.isNotEmpty) {
        var config = jsonDecode(content);
        BoardProviderNotice notice = BoardProviderNotice();
        notice.fromJson(config);
        return notice;
      }
    } catch (err, stacktrace) {}
    return BoardProviderNotice();
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

class BoardProviderNoticeManager {
  // Kept as a no-op event list so existing screens that subscribe to
  // "a new provider notice arrived" continue to compile; it is never
  // fired since nothing populates new notices anymore.
  static final List<void Function()> onEventCheck = [];
  static final BoardProviderNoticeLoadAndCheck _selfNotice =
      BoardProviderNoticeLoadAndCheck();

  static Future<void> init() async {
    _selfNotice.filePath = await PathUtils.providerNoticeFilePath();
    await _selfNotice.load();
  }

  static Future<void> uninit() async {}

  static List<BoardProviderNotice> getNotices() {
    return [_selfNotice.notice];
  }

  static Future<void> save() async {
    await _selfNotice.save();
  }
}
