// Real replacement for the missing private `DiversionCustomRules` helper.
// Reconstructed from diversion_group_custom_screen.dart and
// diversion_rules_custom_set_screen.dart call sites: a JSON-persisted list
// of custom per-domain/IP routing rules, each mapped to one of a small set
// of well-known outbound targets.
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/runtime/return_result.dart';

class DiversionCustomRule {
  String name = "";
  String outbound = "";
  bool enable = true;
  List<String> domains = [];
  List<String> ips = [];

  Map<String, dynamic> toJson() => {
    'name': name,
    'outbound': outbound,
    'enable': enable,
    'domains': domains,
    'ips': ips,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    name = map["name"] ?? "";
    outbound = map["outbound"] ?? "";
    enable = map["enable"] ?? true;
    domains = List<String>.from(map["domains"] ?? []);
    ips = List<String>.from(map["ips"] ?? []);
  }
}

/// Region-specific starter rule presets. No preset data ships in this
/// repo (the private Karing source's presets were never available to
/// reconstruct from), so this honestly returns "no preset for this
/// region" rather than fabricate routing rules.
class DiversionCustomRulesPreset {
  static Future<DiversionCustomRules?> getPreset(String regionCode) async {
    return null;
  }
}

class DiversionCustomRules {
  static const String kDirect = kOutboundTypeDirect;
  static const String kBlock = kOutboundTypeBlock;
  static const String kUrltest = kOutboundTypeUrltest;
  static const String kCurrentSelected = "current-selected";
  static const String kNone = "";

  List<DiversionCustomRule> rules = [];

  Map<String, dynamic> toJson() => {'rules': rules};

  void fromJson(Map<String, dynamic>? map) {
    rules = [];
    if (map == null) return;
    for (var r in (map["rules"] ?? [])) {
      final rule = DiversionCustomRule();
      rule.fromJson(r);
      rules.add(rule);
    }
  }

  static DiversionCustomRules exportRules() {
    final result = DiversionCustomRules();
    final custom = ServerManager.getDiversionCustomGroup();
    for (var g in custom.groups) {
      final rule = DiversionCustomRule();
      rule.name = g.name;
      rule.domains = g.domains;
      rule.ips = g.ips;
      rule.outbound = g.outboundTag;
      result.rules.add(rule);
    }
    return result;
  }

  static Future<ReturnResult<DiversionCustomRules>> getFromFile(
    String filePath,
  ) async {
    try {
      final content = await File(filePath).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return ReturnResult(
          error: ReturnResultError("invalid rules file", report: false),
        );
      }
      final rules = DiversionCustomRules();
      rules.fromJson(Map<String, dynamic>.from(decoded));
      return ReturnResult(data: rules);
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<ReturnResultError?> importRules(
    DiversionCustomRules rules,
  ) async {
    try {
      final custom = ServerManager.getDiversionCustomGroup();
      custom.groups = rules.rules
          .map(
            (r) => DiversionRulesGroup()
              ..name = r.name
              ..domains = r.domains
              ..ips = r.ips
              ..outboundTag = r.outbound,
          )
          .toList();
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: true);
    }
  }
}
