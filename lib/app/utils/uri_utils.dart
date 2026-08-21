// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class UriUtils {
  UriUtils._();

  /// Parses [value] as a [Uri], first bracketing a bare (unbracketed) IPv6
  /// host so `Uri.parse` doesn't misread its colons as a port separator.
  static Uri? parseUrlFixIPV6(String value) {
    var fixed = value.trim();
    if (fixed.isEmpty) {
      return null;
    }
    final schemeSep = fixed.indexOf('://');
    if (schemeSep >= 0) {
      final afterScheme = fixed.substring(schemeSep + 3);
      final hostEnd = RegExp(r'[/?#]').firstMatch(afterScheme)?.start ??
          afterScheme.length;
      var host = afterScheme.substring(0, hostEnd);
      final atIdx = host.lastIndexOf('@');
      final hostOnly = atIdx >= 0 ? host.substring(atIdx + 1) : host;
      if (hostOnly.contains(':') &&
          !hostOnly.startsWith('[') &&
          RegExp(r'^[0-9a-fA-F:]+$').hasMatch(hostOnly)) {
        final fixedHost = '[$hostOnly]';
        fixed = fixed.substring(0, schemeSep + 3) +
            (atIdx >= 0 ? host.substring(0, atIdx + 1) : '') +
            fixedHost +
            afterScheme.substring(hostEnd);
      }
    }
    try {
      return Uri.parse(fixed);
    } catch (_) {
      return null;
    }
  }
}
