// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class EmojiUtils {
  EmojiUtils._();

  /// Converts an ISO 3166-1 alpha-2 country code (e.g. "US") to its
  /// regional-indicator flag emoji (e.g. "🇺🇸").
  static String countryCodeToEmoji(String countryCode) {
    if (countryCode.length != 2) {
      return '';
    }
    final code = countryCode.toUpperCase();
    const base = 0x1F1E6;
    final chars = code.codeUnits.map((c) {
      if (c < 0x41 || c > 0x5A) {
        return null;
      }
      return base + (c - 0x41);
    }).toList();
    if (chars.contains(null)) {
      return '';
    }
    return String.fromCharCodes(chars.cast<int>());
  }
}
