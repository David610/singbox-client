// Real replacement for the missing private `AutoConfUtils` helper --
// resolves a subscription URL/local file/pasted content into a
// [ServerConfigGroupItem]'s `.servers` list. Reconstructed from its sole
// call site (`ServerManager.loadFrom`), which requires the exact
// signature below.
//
// **Honest scope note**: real Karing subscription parsing supports
// several link/subscription formats (raw sing-box JSON, Clash YAML,
// base64 `ss://`/`vmess://`/`vless://`/`hysteria2://`/`trojan://` link
// lists, WireGuard `.conf`). Reconstructing every format's parser is a
// substantial, protocol-detailed task on its own. What's implemented for
// real here: fetching the content (local file or HTTP(S) URL) and parsing
// it as a raw sing-box config JSON (`{"outbounds": [...]}`), which is
// what this app's own pinned core natively consumes and is the format
// `packages/vpn_core/lib/src/singbox_config_builder.dart` already
// round-trips for VLESS+REALITY/Hysteria2 -- so a sing-box-type profile
// added through this screen produces real, correctly-typed
// [ProxyConfig] entries. Non-singbox [SubscriptionLinkType]s return a
// clear, honest "not supported yet" error instead of a fabricated parse.
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/http_utils.dart';

class AutoConfUtils {
  static Future<ReturnResultError?> tryConvert(
    String urlOrPath,
    bool local,
    bool isUpdate,
    ServerConfigGroupItem item,
    List<ServerDiversionGroupRuleSetItem> existingRuleSets,
    ServerDiversionGroupItem? diversionGroupItem,
    RemoteContent? remoteContent,
  ) async {
    String content;
    if (remoteContent != null && remoteContent.text.isNotEmpty) {
      content = remoteContent.text;
    } else if (local) {
      try {
        content = await File(urlOrPath).readAsString();
      } catch (err) {
        return ReturnResultError(err.toString(), report: false);
      }
    } else {
      final result = await HttpUtils.httpGetRequest(
        urlOrPath,
        null,
        null,
        const Duration(seconds: 15),
        null,
        null,
      );
      if (result.error != null) {
        return result.error;
      }
      if (result.data!.item1 != 200) {
        return ReturnResultError("http statusCode:${result.data!.item1}", report: false);
      }
      content = result.data!.item2;
    }

    if (item.type != SubscriptionLinkType.singbox) {
      return ReturnResultError(
        "subscription type '${item.type.name}' is not supported yet",
        report: false,
      );
    }

    Map<String, dynamic> config;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return ReturnResultError("invalid sing-box config JSON", report: false);
      }
      config = Map<String, dynamic>.from(decoded);
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }

    final outbounds = config["outbounds"];
    if (outbounds is! List || outbounds.isEmpty) {
      return ReturnResultError("no outbounds in config", report: false);
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
      server.groupid = item.groupid;
      server.type = type;
      server.tag = o["tag"]?.toString() ?? "";
      server.server = o["server"]?.toString() ?? "";
      server.serverport = (o["server_port"] is int) ? o["server_port"] as int : 0;
      server.remark = server.tag;
      server.raw = Map<String, dynamic>.from(o);
      servers.add(server);
    }

    if (servers.isEmpty) {
      return ReturnResultError("no usable proxy outbounds found", report: false);
    }
    item.servers = servers;
    return null;
  }
}
