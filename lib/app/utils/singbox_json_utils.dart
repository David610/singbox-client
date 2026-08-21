// Real replacement for the missing private `SingboxJsonUtils` helper --
// parses a raw sing-box config JSON file (opened directly via
// about_screen.dart's "import local sing-box config" action) into a
// [ServerConfigGroupItem], the same real outbound-JSON parsing
// [AutoConfUtils.tryConvert] already does for sing-box-type subscriptions.
import 'dart:convert';

import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/runtime/return_result.dart';

/// Accumulates non-fatal exceptions/unsupported-feature notes surfaced
/// while parsing (about_screen.dart constructs one and passes it through;
/// nothing here currently populates it, but it must exist for callers to
/// hold onto).
class TransExceptionAndUnsupport {
  final List<String> exceptions = [];
  final List<String> unsupported = [];
}

class SingboxJsonUtils {
  static ReturnResult<bool> tryConvert(
    String content,
    ServerConfigGroupItem item,
    List<ServerDiversionGroupRuleSetItem> rulesetItems,
    String? groupid,
    TransExceptionAndUnsupport eu,
  ) {
    Map<String, dynamic> config;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return ReturnResult(error: ReturnResultError("invalid sing-box config JSON", report: false));
      }
      config = Map<String, dynamic>.from(decoded);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString(), report: false));
    }

    final outbounds = config["outbounds"];
    if (outbounds is! List || outbounds.isEmpty) {
      return ReturnResult(error: ReturnResultError("no outbounds in config", report: false));
    }

    final servers = <ProxyConfig>[];
    for (final o in outbounds) {
      if (o is! Map) continue;
      final type = o["type"]?.toString() ?? "";
      if (type == kOutboundTypeDirect ||
          type == kOutboundTypeBlock ||
          type == kOutboundTypeDns ||
          type == kOutboundTypeSelector ||
          type == kOutboundTypeUrltest) {
        continue;
      }
      final server = ProxyConfig();
      server.groupid = groupid ?? item.groupid;
      server.type = type;
      server.tag = o["tag"]?.toString() ?? "";
      server.server = o["server"]?.toString() ?? "";
      server.serverport = (o["server_port"] is int) ? o["server_port"] as int : 0;
      server.remark = server.tag;
      server.raw = Map<String, dynamic>.from(o);
      servers.add(server);
    }

    if (servers.isEmpty) {
      return ReturnResult(error: ReturnResultError("no usable proxy outbounds found", report: false));
    }
    item.servers = servers;
    item.type = SubscriptionLinkType.singbox;
    return ReturnResult(data: true);
  }
}
