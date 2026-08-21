// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:typed_data';

import 'package:android_package_manager/android_package_manager.dart';

/// One installed Android package plus its resolved display name/icon,
/// cached together since both require extra platform calls beyond
/// `getInstalledPackages`.
class PackageInfoEx {
  PackageInfoEx({PackageInfo? info, this.name = '', this.icon})
    : info = info ?? const PackageInfoImpl();

  PackageInfo info;
  String name;
  Uint8List? icon;
}

/// Minimal, real (not fabricated) `PackageInfo` for a placeholder entry --
/// used when a previously-selected package is no longer installed (see
/// perapp_android_screen.dart/packageid_multi_select_android_screen.dart's
/// "removed app" placeholder row). `android_package_manager`'s own
/// `PackageInfoImpl` is internal to that package (not exported), so this
/// is this app's own minimal implementation of the same public
/// `PackageInfo` contract.
class PackageInfoImpl extends PackageInfo {
  const PackageInfoImpl({String? packageName})
    : super(installLocation: AndroidInstallLocation.auto, packageName: packageName);
}

class PackageManagerAndroid {
  PackageManagerAndroid._();

  static const int kAndroidFlagSystem = 0x00000001;
  static const String kRemoved = '';

  static final AndroidPackageManager _manager = AndroidPackageManager();

  static Future<List<PackageInfoEx>> getInstalledPackages({
    bool Function(PackageInfo info)? onValid,
  }) async {
    final packages = await _manager.getInstalledPackages() ?? [];
    final result = <PackageInfoEx>[];
    for (final info in packages) {
      if (info.packageName == null) {
        continue;
      }
      if (onValid != null && !onValid(info)) {
        continue;
      }
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
