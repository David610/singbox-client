// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:typed_data';

import 'package:android_package_manager/android_package_manager.dart';

/// One installed Android package plus its resolved display name/icon,
/// cached together since both require extra platform calls beyond
/// `getInstalledPackages`.
class PackageInfoEx {
  PackageInfoEx({required this.info, this.name = '', this.icon});

  PackageInfo info;
  String name;
  Uint8List? icon;
}

class PackageManagerAndroid {
  PackageManagerAndroid._();

  static const int kAndroidFlagSystem = 0x00000001;
  static const String kRemoved = '';

  static final AndroidPackageManager _manager = AndroidPackageManager();

  static Future<List<PackageInfoEx>> getInstalledPackages({
    void Function(PackageInfo info)? onValid,
  }) async {
    final packages = await _manager.getInstalledPackages() ?? [];
    final result = <PackageInfoEx>[];
    for (final info in packages) {
      if (info.packageName == null) {
        continue;
      }
      onValid?.call(info);
      String name = info.packageName!;
      try {
        name =
            await _manager.getApplicationLabel(
              packageName: info.packageName!,
            ) ??
            info.packageName!;
      } catch (_) {}
      result.add(PackageInfoEx(info: info, name: name));
    }
    return result;
  }

  static Future<Uint8List?> getInstalledPackageIcon(
    List<PackageInfoEx> list,
    String packageName,
  ) async {
    for (final item in list) {
      if (item.info.packageName == packageName) {
        if (item.icon != null) {
          return item.icon;
        }
        try {
          item.icon = await _manager.getApplicationIcon(
            packageName: packageName,
          );
        } catch (_) {}
        return item.icon;
      }
    }
    return null;
  }

  static int sortByName(PackageInfoEx a, PackageInfoEx b) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
