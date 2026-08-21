// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class ConvertUtils {
  ConvertUtils._();

  static List<String>? getListStringFromDynamic(
    dynamic value,
    bool allowNull,
    List<String> defaultValue,
  ) {
    if (value == null) {
      return allowNull ? defaultValue : null;
    }
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) {
      return value.isEmpty ? [] : [value];
    }
    return defaultValue;
  }
}
