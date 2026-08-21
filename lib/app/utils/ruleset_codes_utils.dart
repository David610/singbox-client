// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Reads the real, already-committed ruleset code lists
// (assets/datas/geosite_codes.txt, assets/datas/geoip_codes.txt,
// assets/datas/acl_codes.txt) rather than fabricating a code list.
library;

import 'package:crypto/crypto.dart';
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

  static Future<String> siteCodesHashCode() async {
    return sha256.convert((await siteCodes()).join(',').codeUnits).toString();
  }

  static Future<String> ipCodesHashCode() async {
    return sha256.convert((await ipCodes()).join(',').codeUnits).toString();
  }

  static Future<String> aclCodesHashCode() async {
    return sha256.convert((await aclCodes()).join(',').codeUnits).toString();
  }
}
