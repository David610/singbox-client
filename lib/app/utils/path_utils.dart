// Reconstructed: this file did not exist in this fork (see
// docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md). File/directory
// names below are chosen fresh for this fork (not recovered from upstream,
// which is unavailable) but are internally consistent: every call site in
// lib/ that reads or writes one of these paths goes through this file, so
// there is no cross-module name mismatch.
library;

import 'dart:io';

import 'package:karing/app/utils/platform_utils.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PathUtils {
  PathUtils._();

  static bool _portableMode = false;

  static bool portableMode() => _portableMode;

  static void setPortableMode(bool value) {
    _portableMode = value;
  }

  static String getExeName([String name = 'karing']) {
    if (PlatformUtils.windows) {
      return '$name.exe';
    }
    return name;
  }

  static Future<String> _supportDir() async {
    if (_portableMode && !PlatformUtils.isMobile()) {
      return profileDirForPortableMode();
    }
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  static String profileDirForPortableMode() {
    return path.join(path.dirname(Platform.resolvedExecutable), 'profile');
  }

  static Future<String> profileDir() async {
    final dir = await _supportDir();
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> profileDataDir() async {
    final dir = path.join(await profileDir(), 'data');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> cacheDir() async {
    final dir = (await getTemporaryDirectory()).path;
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> backupDir() async {
    final dir = path.join(await profileDir(), 'backup');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> webviewCacheDir() async {
    final dir = path.join(await cacheDir(), 'webview');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static String flutterAssetsDir() {
    return path.join(path.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets');
  }

  static String logFileName() => 'app.log';
  static Future<String> logFilePath() async =>
      path.join(await profileDir(), logFileName());

  static String serviceLogFileName() => 'service.log';
  static String serviceCoreConfigFileName() => 'service_core.json';
  static Future<String> serviceCoreConfigFilePath() async =>
      path.join(await profileDir(), serviceCoreConfigFileName());

  static String serviceStdErrorFileName() => 'service_stderr.log';
  static Future<String> serviceStdErrorFilePath() async =>
      path.join(await profileDir(), serviceStdErrorFileName());

  static String serviceConfigFileName() => 'service.json';
  static Future<String> serviceConfigFilePath() async =>
      path.join(await profileDir(), serviceConfigFileName());

  static String serviceExeName() => getExeName('karing_service');
  static String serviceExePath() =>
      path.join(path.dirname(Platform.resolvedExecutable), serviceExeName());

  static String settingFileName() => 'setting.json';
  static Future<String> settingFilePath() async =>
      path.join(await profileDir(), settingFileName());

  static String subscribeFileName() => 'subscribe.json';
  static Future<String> subscribeFilePath() async =>
      path.join(await profileDir(), subscribeFileName());

  static String subscribeUseFileName() => 'subscribe_use.json';
  static Future<String> subscribeUseFilePath() async =>
      path.join(await profileDir(), subscribeUseFileName());

  static String diversionGroupFileName() => 'diversion_group.json';
  static Future<String> diversionGroupFilePath() async =>
      path.join(await profileDir(), diversionGroupFileName());

  static String remoteConfigFileName() => 'remote_config.json';
  static Future<String> remoteConfigFilePath() async =>
      path.join(await profileDir(), remoteConfigFileName());

  static String remoteISPConfigFileName() => 'remote_isp_config.json';
  static Future<String> remoteISPConfigFilePath() async =>
      path.join(await profileDir(), remoteISPConfigFileName());

  static String noticeFileName() => 'notice.json';
  static Future<String> noticeFilePath() async =>
      path.join(await profileDir(), noticeFileName());

  static String ispNoticeFileName() => 'isp_notice.json';
  static Future<String> ispNoticeFilePath() async =>
      path.join(await profileDir(), ispNoticeFileName());

  static Future<String> providerNoticeFilePath() async =>
      path.join(await profileDir(), 'provider_notice.json');

  static Future<String> providersConfigFilePath() async =>
      path.join(await profileDir(), 'providers_config.json');

  static String autoUpdateFileName() => getExeName('karing_update');
  static Future<String> autoUpdateFilePath() async =>
      path.join(await cacheDir(), autoUpdateFileName());

  static String cloudflareWarpFileName() => 'cloudflare_warp.json';

  static String statisticsDBFileName() => 'statistics.db';
  static Future<String> statisticsDBFilePath() async =>
      path.join(await profileDir(), statisticsDBFileName());

  static String cacheDBFileName() => 'cache.db';
  static Future<String> cacheDBFilePath() async =>
      path.join(await cacheDir(), cacheDBFileName());

  static String storageFileName() => 'storage.db';
  static Future<String> storageFilePath() async =>
      path.join(await profileDir(), storageFileName());
}
