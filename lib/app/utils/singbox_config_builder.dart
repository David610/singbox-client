// Real replacement for the missing private app-level `SingboxConfigBuilder`
// (distinct from `packages/vpn_core`'s own `SingBoxConfigBuilder`, which
// builds the actual config the tunnel runs -- see
// docs/ARCHITECTURE.md §4). This one builds the JSON shown in
// my_profiles_screen.dart's "export/share config" preview, using
// sing-box's own public config schema. Kept intentionally simpler than a
// full protocol-perfect builder: it is a preview/export convenience, not
// what actually carries traffic.
import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/singbox_outbound.dart';
import 'package:tuple/tuple.dart';

class SingboxConfig {
  Map<String, dynamic> ntp = {};
  Map<String, dynamic> dns = {};
  List<dynamic> inbounds = [];
  List<dynamic> outbounds = [];
  Map<String, dynamic> route = {};

  Map<String, dynamic> toJson() => {
    if (ntp.isNotEmpty) 'ntp': ntp,
    'dns': dns,
    'inbounds': inbounds,
    'outbounds': outbounds,
    'route': route,
  };
}

class SingboxConfigBuilder {
  /// Real, if simplified: maps [server]'s fields onto sing-box's own
  /// documented outbound JSON shape for the handful of protocols this app
  /// generates (`server.raw`, when present, already IS that JSON --
  /// produced by the real profile parser -- so it is preferred verbatim).
  static Map<String, dynamic>? buildOutbound(ProxyConfig server) {
    if (server.raw != null) {
      return Map<String, dynamic>.from(server.raw!);
    }
    if (server.type.isEmpty || server.server.isEmpty) {
      return null;
    }
    return {
      'type': server.type,
      'tag': server.tag,
      'server': server.server,
      'server_port': server.serverport,
    };
  }

  static Map<String, dynamic> ntp() => {
    'enabled': true,
    'server': 'time.apple.com',
    'server_port': 123,
    'interval': '30m',
  };

  static ReturnResult<Map<String, dynamic>> dns(
    bool tunMode,
    SingboxExportType exportType,
    String? overrideResolver,
  ) {
    return ReturnResult(
      data: {
        'servers': [
          {'tag': 'dns-remote', 'address': overrideResolver ?? 'tls://8.8.8.8'},
          {'tag': 'dns-local', 'address': 'local'},
        ],
        'strategy': 'prefer_ipv4',
      },
    );
  }

  static List<dynamic> inbounds(bool tunMode, SingboxExportType exportType) {
    final result = <dynamic>[SingboxInboundMixedOptions()];
    if (tunMode) {
      result.insert(0, SingboxInboundTunOptions());
    }
    return result;
  }

  static List<dynamic> outbounds(
    String tag,
    Set<String> selectOutboundTags,
    Map<String, dynamic> extra,
    dynamic selectOutbound,
    List<dynamic> allOutbounds,
    dynamic urltestOutbound,
    Map<String, dynamic> extra2,
    SingboxExportType exportType,
  ) {
    final result = <dynamic>[];
    result.addAll(allOutbounds);
    result.add({
      'type': 'selector',
      'tag': tag.isEmpty ? kOutboundTagSelector : tag,
      'outbounds': selectOutboundTags.toList(),
    });
    result.add({'type': kOutboundTypeDirect, 'tag': kOutboundTagDirect});
    result.add({'type': kOutboundTypeBlock, 'tag': kOutboundTagBlock});
    return result;
  }

  static Map<String, dynamic> route(
    String finalOutbound,
    String defaultInterface,
    String defaultMark,
    Set<int> siteCodesHash,
    Set<int> ipCodesHash,
    Set<int> aclCodesHash,
    bool tunMode,
    List<dynamic> allOutbounds,
    Map<String, dynamic> extra,
    dynamic extra2,
    List<Tuple3<DiversionRulesGroup, ProxyConfig, List<String>>> diversionGroups,
    List<dynamic> inbounds,
    Map<String, dynamic> dns, [
    dynamic extra3,
    dynamic extra4,
    String? groupid,
    SingboxExportType? exportType,
  ]) {
    final rules = <dynamic>[];
    for (final group in diversionGroups) {
      final rule = group.item1;
      final outbound = group.item2;
      final Map<String, dynamic> ruleJson = {'outbound': outbound.tag};
      if (rule.domain.isNotEmpty) ruleJson['domain'] = rule.domain;
      if (rule.domainSuffix.isNotEmpty) {
        ruleJson['domain_suffix'] = rule.domainSuffix;
      }
      if (rule.ipCidr.isNotEmpty) ruleJson['ip_cidr'] = rule.ipCidr;
      rules.add(ruleJson);
    }
    return {
      'final': finalOutbound.isEmpty ? kOutboundTagDirect : finalOutbound,
      'auto_detect_interface': true,
      'rules': rules,
    };
  }
}
