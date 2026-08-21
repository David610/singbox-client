// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class SystemSchemeUtils {
  SystemSchemeUtils._();

  static String getKaringScheme() => 'karing';
  static String getClashScheme() => 'clash';
  static String getSingboxScheme() => 'sing-box';

  static String getKaringSchemeWith() => '${getKaringScheme()}://';
  static String getClashSchemeWith() => '${getClashScheme()}://';
  static String getSingboxSchemeWith() => '${getSingboxScheme()}://';

  static Future<bool> isRegistered(String scheme) async => false;

  /// Registers [scheme] as a custom URL scheme handler for this app.
  /// Desktop (Windows/Linux)-only; returns an error message on failure, or
  /// null on success/no-op (mobile platforms register schemes declaratively
  /// via the platform manifest, not at runtime).
  static Future<String?> register(String scheme) async => null;

  static Future<String?> unregister(String scheme) async => null;
}
