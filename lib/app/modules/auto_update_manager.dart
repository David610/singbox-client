// ignore_for_file: unused_catch_stack, empty_catches

import 'dart:io';

import 'package:karing/app/utils/app_utils.dart';
import 'package:karing/app/utils/install_referrer_utils.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:path/path.dart' as path;

class AutoUpdateCheckVersion {
  String latestCheck = "";
  bool newVersion = false;
  String version = "";
  String url = "";

  String sha256 = "";
  Map<String, dynamic> toJson() => {
    'latest_check': latestCheck,
    'new_version': newVersion,
    "version": version,
    "url": url,
    "sha256": sha256,
  };
  void fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }
    latestCheck = map["latest_check"] ?? "";
    newVersion = map["new_version"] ?? "";
    version = map["version"] ?? "";
    url = map["url"] ?? "";
    sha256 = map["sha256"] ?? "";
  }

  static AutoUpdateCheckVersion fromJsonStatic(Map<String, dynamic>? map) {
    AutoUpdateCheckVersion config = AutoUpdateCheckVersion();
    config.fromJson(map);
    return config;
  }

  String getExtension() {
    String ext = "";
    final channelName = InstallReferrerUtils.getBuildChannelName();
    // Android intentionally never returns an extension here (same "no
    // download candidate" convention the Linux AppImage case below already
    // uses): Play Store distribution should update itself through Play,
    // not an in-app APK download + REQUEST_INSTALL_PACKAGES installer flow
    // -- see docs/CLIENT_PRODUCTION_BASELINE.md "Self-update removal".
    // getDownloadPath() above already short-circuits to "" for any empty
    // extension, so this alone disables the whole download/install path.
    if (Platform.isWindows) {
      ext = ".exe";
    } else if (Platform.isMacOS) {
      ext = ".dmg";
    } else if (Platform.isLinux) {
      if (channelName.toLowerCase().contains("deb")) {
        ext = ".deb";
      } else if (channelName.toLowerCase().contains("rpm")) {
        ext = ".rpm";
      } else if (channelName.toLowerCase().contains("appimage")) {
        return "";
      }
    }
    return ext;
  }

  Future<String> getDownloadPath() async {
    String ext = getExtension();
    if (ext.isEmpty) {
      return "";
    }
    final newPath = path.join(await PathUtils.cacheDir(), version);
    return "$newPath$ext";
  }

  void clear() {
    latestCheck = "";
    newVersion = false;
    version = "";
    url = "";
    sha256 = "";
  }
}

// This used to be the app's Karing self-updater: on every startup, VPN
// connect, app resume, and (on desktop) every 30 minutes, it silently
// fetched `https://dot.karing.app/autoupdate.json`, and on finding a
// "newer" entry it would auto-download an installer from an
// attacker-or-Karing-controlled URL and (via VersionUpdateScreen) run it
// with `sudo dpkg -i` / `sudo rpm -i` on Linux or launch it directly on
// Windows/macOS -- a full silent third-party supply-chain / code-execution
// path with no relation to VPN start/import/connect. That entire fetch,
// download, and install flow has been deleted rather than repointed at a
// placeholder host. What remains is inert plumbing (`isSupport()`,
// `updateChannels()`, `getVersionCheck()`, `checkReplace()`,
// `updateChannelChanged()`) so the handful of existing settings/about
// screens that reference this class keep compiling; `checkReplace()` now
// always returns null (no update is ever discovered) and no installer is
// ever downloaded or executed.
class AutoUpdateManager {
  // Kept as a no-op event list so existing screens that subscribe to
  // "a new version was found" continue to compile; it is never fired.
  static final List<void Function()> onEventCheck = [];
  static final AutoUpdateCheckVersion _versionCheck = AutoUpdateCheckVersion();

  static bool isSupport() {
    return Platform.isWindows ||
        Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  static List<String> updateChannels() {
    return ["beta", "stable"];
  }

  static Future<void> init() async {
    // Deliberately does not load any autoupdate.json cache left over from
    // a previous install of this app -- doing so could resurrect a stale
    // version/url/sha256 record (and, on disk, an already-downloaded
    // installer) from before this network path was removed. Starting
    // from a clean, empty `_versionCheck` every time means
    // `checkReplace()` can never find anything to run.
    try {
      final filePath = await PathUtils.autoUpdateFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (err, stacktrace) {}
  }

  static Future<void> uninit() async {}

  static void updateChannelChanged() {
    _versionCheck.clear();
  }

  static AutoUpdateCheckVersion getVersionCheck() {
    return _versionCheck;
  }

  static Future<String?> checkReplace() async {
    if (!isSupport()) {
      return null;
    }
    if (_versionCheck.version.isEmpty) {
      return null;
    }
    String version = AppUtils.getBuildinVersion();
    String downloadPath = await _versionCheck.getDownloadPath();
    if (downloadPath.isEmpty) {
      return null;
    }
    if (_compareVersion(version, _versionCheck.version) < 0) {
      var file = File(downloadPath);
      bool exist = await file.exists();
      if (exist) {
        return downloadPath;
      }
    }

    return null;
  }

  // Minimal same-format ("x.y.z") numeric version comparison, kept local
  // now that the real `VersionCompareUtils` dependency this file used to
  // pull in for the deleted update-checking logic is no longer needed
  // elsewhere in this class.
  static int _compareVersion(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final na = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final nb = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (na != nb) {
        return na < nb ? -1 : 1;
      }
    }
    return 0;
  }
}
