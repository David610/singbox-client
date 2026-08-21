// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

class VersionCompareUtils {
  VersionCompareUtils._();

  static List<int> _parts(String version, int? padLength) {
    final parts = version
        .split(RegExp(r'[+\-].*$'))
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    if (padLength != null) {
      while (parts.length < padLength) {
        parts.add(0);
      }
      if (parts.length > padLength) {
        parts.removeRange(padLength, parts.length);
      }
    }
    return parts;
  }

  static int compareVersion(String a, String b) {
    return compareVersionWithLength(a, b, null);
  }

  static int compareVersionWithLength(String a, String b, int? length) {
    final pa = _parts(a, length);
    final pb = _parts(b, length);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) {
        return va.compareTo(vb);
      }
    }
    return 0;
  }
}
