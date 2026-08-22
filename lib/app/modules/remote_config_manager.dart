// ignore_for_file: empty_catches, unused_catch_stack

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/remote_config.dart';
import 'package:karing/app/utils/path_utils.dart';

// This used to be the app's Karing remote-config client: on every
// startup, VPN connect, app resume, and (on desktop) every 30 minutes it
// silently fetched `https://dot.karing.app/config.json`, a third-party
// control-plane endpoint that could remotely steer this app's donate
// links, "get traffic" URL, ruleset source hosts, etc. That entire
// automatic fetch has been removed rather than repointed at a
// placeholder -- it was not required for VPN start/import/connect, and
// nothing in this app should silently phone home to Karing's
// infrastructure. `getConfig()` now only ever returns this app's own
// hardcoded first-party defaults (`RemoteConfig`'s field initializers),
// optionally overlaid with whatever was cached on disk from a previous
// install of this app before this change (never fetched over the
// network by this build).
class RemoteConfigManager {
  static RemoteConfig _config = RemoteConfig();

  static Future<void> init() async {
    await _loadConfig();
  }

  static Future<void> uninit() async {}

  static RemoteConfig getConfig() {
    return _config;
  }

  static Future<void> _loadConfig() async {
    String filePath = await PathUtils.remoteConfigFilePath();
    var file = File(filePath);
    bool exists = await file.exists();
    if (!exists) {
      return;
    }
    try {
      String content = await file.readAsString();
      if (content.isNotEmpty) {
        var config = jsonDecode(content);
        _config.fromJson(config);
      }
    } catch (err, stacktrace) {}
  }
}
