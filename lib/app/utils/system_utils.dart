// Real replacement for the missing private `SystemUtils` helper --
// reconstructed from its sole call site (net_check_screen.dart's route-
// table diagnostic), which just needs a human-readable dump of the
// system's routing table. Runs the real platform command rather than
// fabricate output.
import 'dart:io';

import 'package:karing/app/utils/platform_utils.dart';

class SystemUtils {
  SystemUtils._();

  static Future<String> getRouteTable() async {
    try {
      ProcessResult result;
      if (PlatformUtils.windows) {
        result = await Process.run('route', ['print']);
      } else if (PlatformUtils.macos || PlatformUtils.linux) {
        result = await Process.run('netstat', ['-rn']);
      } else {
        return "not supported on this platform";
      }
      if (result.exitCode != 0) {
        return result.stderr.toString();
      }
      return result.stdout.toString();
    } catch (err) {
      return err.toString();
    }
  }
}
