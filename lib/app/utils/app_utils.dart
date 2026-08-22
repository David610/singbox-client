// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:package_info_plus/package_info_plus.dart';

class AppUtils {
  AppUtils._();

  static const String _name = 'singbox-client';
  static const String _id = 'com.david610.singboxclient';
  static const String _groupId = 'group.com.david610.singboxclient';
  static const String _buildinVersion = '1.2.24';

  static PackageInfo? _packageInfo;

  static String getName() => _name;
  static String getId() => _id;
  static String getGroupId() => _groupId;
  static String getBuildinVersion() => _buildinVersion;

  static Future<String> getPackgetVersion() async {
    try {
      _packageInfo ??= await PackageInfo.fromPlatform();
      return '${_packageInfo!.version}+${_packageInfo!.buildNumber}';
    } catch (_) {
      return _buildinVersion;
    }
  }

  static String getTermsOfServiceUrl() => '';
}
