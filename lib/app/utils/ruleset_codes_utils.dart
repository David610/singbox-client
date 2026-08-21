// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Reads the real, already-committed ruleset code lists
// (assets/datas/geosite_codes.txt, assets/datas/geoip_codes.txt,
// assets/datas/acl_codes.txt) rather than fabricating a code list.
library;

import 'package:flutter/services.dart';

class RulesetCodesUtils {
  RulesetCodesUtils._();

  static List<String>? _siteCodes;
  static List<String>? _ipCodes;
  static List<String>? _aclCodes;

  static Future<List<String>> _load(String asset) async {
    final content = await rootBundle.loadString(asset);
    return content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static Future<List<String>> siteCodes() async {
    return _siteCodes ??= await _load('assets/datas/geosite_codes.txt');
  }

  static Future<List<String>> ipCodes() async {
    return _ipCodes ??= await _load('assets/datas/geoip_codes.txt');
  }

  static Future<List<String>> aclCodes() async {
    return _aclCodes ??= await _load('assets/datas/acl_codes.txt');
  }

  static Future<Set<int>> siteCodesHashCode() async {
    return (await siteCodes()).map((e) => e.hashCode).toSet();
  }

  static Future<Set<int>> ipCodesHashCode() async {
    return (await ipCodes()).map((e) => e.hashCode).toSet();
  }

  static Future<Set<int>> aclCodesHashCode() async {
    return (await aclCodes()).map((e) => e.hashCode).toSet();
  }
}
