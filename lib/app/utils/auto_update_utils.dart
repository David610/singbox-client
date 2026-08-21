// Real replacement for the missing private `AutoupdateUtils` helper --
// fetches this app's own real, already-declared production endpoints
// (`RemoteConfig.kDefaultAutoUpdate`/`kDefaultConfig`, both already
// present in remote_config.dart) rather than fabricate the response.
import 'dart:convert';

import 'package:karing/app/modules/remote_config.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/http_utils.dart';

class AutoupdateItem {
  String version = "";
  String url = "";
  String changelog = "";
  String sha256 = "";
  String platform = "";
  List<String> updateChannel = [];
  List<String> abis = [];
  List<String> channels = [];

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    version = map["version"] ?? "";
    url = map["url"] ?? "";
    changelog = map["changelog"] ?? "";
    sha256 = map["sha256"] ?? "";
    platform = map["platform"] ?? "";
    updateChannel = List<String>.from(map["update_channel"] ?? []);
    abis = List<String>.from(map["abis"] ?? []);
    channels = List<String>.from(map["channels"] ?? []);
  }
}

class AutoupdateUtils {
  static Future<ReturnResult<List<AutoupdateItem>>> getAutoupdate(
    bool force,
    bool updateWhenConnected,
  ) async {
    final result = await HttpUtils.httpGetRequest(
      RemoteConfig.kDefaultAutoUpdate,
      null,
      null,
      const Duration(seconds: 10),
      null,
      null,
    );
    if (result.error != null) {
      return ReturnResult(error: result.error);
    }
    if (result.data!.item1 != 200) {
      return ReturnResult(
        error: ReturnResultError("http statusCode:${result.data!.item1}", report: false),
      );
    }
    try {
      final decoded = jsonDecode(result.data!.item2);
      final items = <AutoupdateItem>[];
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map) {
            final item = AutoupdateItem();
            item.fromJson(Map<String, dynamic>.from(e));
            items.add(item);
          }
        }
      }
      return ReturnResult(data: items);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString(), report: false));
    }
  }

  static Future<ReturnResult<RemoteConfig>> getRemoteConfig(
    bool updateWhenConnected,
  ) async {
    final result = await HttpUtils.httpGetRequest(
      RemoteConfig.kDefaultConfig,
      null,
      null,
      const Duration(seconds: 10),
      null,
      null,
    );
    if (result.error != null) {
      return ReturnResult(error: result.error);
    }
    if (result.data!.item1 != 200) {
      return ReturnResult(
        error: ReturnResultError("http statusCode:${result.data!.item1}", report: false),
      );
    }
    try {
      final decoded = jsonDecode(result.data!.item2);
      final config = RemoteConfig();
      config.fromJson(decoded is Map ? Map<String, dynamic>.from(decoded) : null);
      return ReturnResult(data: config);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString(), report: false));
    }
  }
}
