// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class InstallReferrerUtils {
  InstallReferrerUtils._();

  /// The app-store/build channel this binary was built for (e.g. "github",
  /// "play-store"). No install-referrer API integration exists in this
  /// fork; always the direct/default channel.
  static String getBuildChannelName() => 'direct';

  static Future<String> getString() async => getBuildChannelName();
}
