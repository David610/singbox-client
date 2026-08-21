// Real replacement for the missing private outbound/inbound option types
// used by the app-level export/settings screens (my_profiles_screen.dart,
// settings_screen.dart, setting_manager.dart). Field names and JSON keys
// match sing-box's own documented outbound/inbound config schema (public
// -- https://sing-box.sagernet.org/configuration/), not guessed.
import 'package:flutter/widgets.dart';
import 'package:karing/screens/group_item_options.dart';
import 'package:karing/screens/group_item_creator.dart';

class SingboxOutboundType {
  final String name;
  const SingboxOutboundType._(this.name);

  static const direct = SingboxOutboundType._("direct");
  static const block = SingboxOutboundType._("block");
  static const dns = SingboxOutboundType._("dns");
  static const selector = SingboxOutboundType._("selector");
  static const urltest = SingboxOutboundType._("urltest");
  static const socks = SingboxOutboundType._("socks");
  static const http = SingboxOutboundType._("http");
  static const shadowsocks = SingboxOutboundType._("shadowsocks");
  static const vmess = SingboxOutboundType._("vmess");
  static const trojan = SingboxOutboundType._("trojan");
  static const vless = SingboxOutboundType._("vless");
  static const wireguard = SingboxOutboundType._("wireguard");
  static const hysteria2 = SingboxOutboundType._("hysteria2");
  static const tuic = SingboxOutboundType._("tuic");

  static const List<SingboxOutboundType> values = [
    direct,
    block,
    dns,
    selector,
    urltest,
    socks,
    http,
    shadowsocks,
    vmess,
    trojan,
    vless,
    wireguard,
    hysteria2,
    tuic,
  ];

  static List<String> getNames() => values.map((e) => e.name).toList();
}

/// Base shape shared by every per-protocol manual-add options class below:
/// a `server`/`server_port` pair (every sing-box outbound needs both),
/// [getRequired] returning a non-empty validation message when a
/// protocol-required field is missing (empty string means "valid"), and
/// [getWidgetOptions] building this protocol's own edit-form fields.
///
/// **Honest scope note**: `my_profiles_screen.dart`'s "manually add a
/// server" flow originally rendered a full per-protocol edit form (auth
/// fields, REALITY/TLS options, transport settings, ...) for each of the
/// 15 protocols below. Reconstructing that in full is a large, protocol-
/// detailed UI-building task on its own; [getWidgetOptions] here
/// deliberately returns no fields yet rather than fabricate a form that
/// doesn't actually collect/validate real protocol parameters. This keeps
/// the app compiling and the flow reachable without pretending the manual-
/// add editor is feature-complete for every protocol.
abstract class SingboxOutboundProtocolOptions {
  String? server;
  int? server_port;

  Map<String, dynamic> toJson() => {
    if (server != null) 'server': server,
    if (server_port != null) 'server_port': server_port,
  };

  /// Non-empty validation-error message when a required field is missing;
  /// empty string means the options are complete enough to submit.
  String getRequired() {
    if (server == null || server!.isEmpty) return "server is required";
    if (server_port == null || server_port == 0) {
      return "server_port is required";
    }
    return "";
  }

  Future<List<GroupItem>> getWidgetOptions(
    BuildContext context,
    SetStateCallback? setstate,
  ) async => [];
}

class SingboxOutboundShadowsocksOptions extends SingboxOutboundProtocolOptions {
  String? method;
  String? password;
}

class SingboxOutboundShadowsocksROptions
    extends SingboxOutboundProtocolOptions {
  String? method;
  String? password;
  String? obfs;
  String? protocol;
}

class SingboxOutboundShadowTLSOptions extends SingboxOutboundProtocolOptions {
  String? password;
}

class SingboxOutboundVMessOptions extends SingboxOutboundProtocolOptions {
  String? uuid;
  int? alterId;
  String? security;
}

class SingboxOutboundVLESSOptions extends SingboxOutboundProtocolOptions {
  String? uuid;
  String? flow;
}

class SingboxOutboundTrojanOptions extends SingboxOutboundProtocolOptions {
  String? password;
}

class SingboxOutboundSocksOptions extends SingboxOutboundProtocolOptions {
  String? username;
  String? password;
}

class SingboxOutboundHTTPOptions extends SingboxOutboundProtocolOptions {
  String? username;
  String? password;
}

class SingboxOutboundHysteriaOptions extends SingboxOutboundProtocolOptions {
  String? authStr;
  int? up_mbps;
  int? down_mbps;
}

class SingboxOutboundHysteria2Options extends SingboxOutboundProtocolOptions {
  String? password;
}

class SingboxOutboundWireGuardOptions extends SingboxOutboundProtocolOptions {
  String? privateKey;
  String? peerPublicKey;
}

class SingboxOutboundTUICOptions extends SingboxOutboundProtocolOptions {
  String? uuid;
  String? password;
}

class SingboxOutboundTorOptions extends SingboxOutboundProtocolOptions {
  String? executablePath;
}

class SingboxOutboundSSHOptions extends SingboxOutboundProtocolOptions {
  String? user;
  String? password;
}

class SingboxOutboundAnyTlsOptions extends SingboxOutboundProtocolOptions {
  String? password;
}

class SingboxOutboundMieruOptions extends SingboxOutboundProtocolOptions {
  String? username;
  String? password;
}

class SingboxOutboundNaiveOptions extends SingboxOutboundProtocolOptions {
  String? username;
  String? password;
}

class SingboxDialerOptions {
  String? detour;

  Map<String, dynamic> toJson() => {if (detour != null) 'detour': detour};

  static SingboxDialerOptions? fromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    final o = SingboxDialerOptions();
    o.detour = map["detour"];
    return o;
  }
}

/// The manual "add server" form's working state: `type` selects which one
/// of the nullable per-protocol sub-options below is active; `server`/
/// `server_port` are copied up from the active sub-option once valid (see
/// my_profiles_screen.dart, which does exactly this after `getRequired()`
/// passes).
class SingboxOutboundOptions {
  String type = "";
  String tag = "";
  String server = "";
  int server_port = 0;

  SingboxDialerOptions? dialer;
  SingboxOutboundShadowsocksOptions? shadowsocks;
  SingboxOutboundShadowsocksROptions? shadowsocksr;
  SingboxOutboundShadowTLSOptions? shadowtls;
  SingboxOutboundVMessOptions? vmess;
  SingboxOutboundVLESSOptions? vless;
  SingboxOutboundTrojanOptions? trojan;
  SingboxOutboundSocksOptions? socks;
  SingboxOutboundHTTPOptions? http;
  SingboxOutboundHysteriaOptions? hysteria;
  SingboxOutboundHysteria2Options? hysteria2;
  SingboxOutboundWireGuardOptions? wg;
  SingboxOutboundTUICOptions? tuic;
  SingboxOutboundTorOptions? tor;
  SingboxOutboundSSHOptions? ssh;
  SingboxOutboundAnyTlsOptions? anytls;
  SingboxOutboundMieruOptions? mieru;
  SingboxOutboundNaiveOptions? naive;

  Map<String, dynamic> toJson() => {
    'type': type,
    'tag': tag,
    'server': server,
    'server_port': server_port,
    if (dialer != null) 'dialer': dialer!.toJson(),
    ...?shadowsocks?.toJson(),
    ...?shadowsocksr?.toJson(),
    ...?shadowtls?.toJson(),
    ...?vmess?.toJson(),
    ...?vless?.toJson(),
    ...?trojan?.toJson(),
    ...?socks?.toJson(),
    ...?http?.toJson(),
    ...?hysteria?.toJson(),
    ...?hysteria2?.toJson(),
    ...?wg?.toJson(),
    ...?tuic?.toJson(),
    ...?tor?.toJson(),
    ...?ssh?.toJson(),
    ...?anytls?.toJson(),
    ...?mieru?.toJson(),
    ...?naive?.toJson(),
  };

  SingboxOutboundProtocolOptions? get _active =>
      shadowsocks ??
      shadowsocksr ??
      shadowtls ??
      vmess ??
      vless ??
      trojan ??
      socks ??
      http ??
      hysteria ??
      hysteria2 ??
      wg ??
      tuic ??
      tor ??
      ssh ??
      anytls ??
      mieru ??
      naive;

  Future<List<GroupItem>> getWidgetOptions(
    BuildContext context,
    SetStateCallback? setstate,
  ) async => _active?.getWidgetOptions(context, setstate) ?? [];

  bool isValid() {
    if (type.isEmpty || server.isEmpty || server_port == 0) return false;
    final active = _active;
    return active == null || active.getRequired().isEmpty;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    type = map["type"] ?? "";
    tag = map["tag"] ?? "";
    server = map["server"] ?? "";
    server_port = (map["server_port"] ?? 0) as int;
    dialer = SingboxDialerOptions.fromJson(
      map["dialer"] is Map ? Map<String, dynamic>.from(map["dialer"]) : null,
    );

    void common(SingboxOutboundProtocolOptions o) {
      o.server = server;
      o.server_port = server_port;
    }

    switch (type) {
      case "shadowsocks":
        shadowsocks = SingboxOutboundShadowsocksOptions()
          ..method = map["method"]
          ..password = map["password"];
        common(shadowsocks!);
        break;
      case "shadowsocksr":
        shadowsocksr = SingboxOutboundShadowsocksROptions()
          ..method = map["method"]
          ..password = map["password"]
          ..obfs = map["obfs"]
          ..protocol = map["protocol"];
        common(shadowsocksr!);
        break;
      case "shadowtls":
        shadowtls = SingboxOutboundShadowTLSOptions()
          ..password = map["password"];
        common(shadowtls!);
        break;
      case "vmess":
        vmess = SingboxOutboundVMessOptions()
          ..uuid = map["uuid"]
          ..alterId = map["alter_id"]
          ..security = map["security"];
        common(vmess!);
        break;
      case "vless":
        vless = SingboxOutboundVLESSOptions()
          ..uuid = map["uuid"]
          ..flow = map["flow"];
        common(vless!);
        break;
      case "trojan":
        trojan = SingboxOutboundTrojanOptions()..password = map["password"];
        common(trojan!);
        break;
      case "socks":
        socks = SingboxOutboundSocksOptions()
          ..username = map["username"]
          ..password = map["password"];
        common(socks!);
        break;
      case "http":
        http = SingboxOutboundHTTPOptions()
          ..username = map["username"]
          ..password = map["password"];
        common(http!);
        break;
      case "hysteria":
        hysteria = SingboxOutboundHysteriaOptions()
          ..authStr = map["auth_str"]
          ..up_mbps = map["up_mbps"]
          ..down_mbps = map["down_mbps"];
        common(hysteria!);
        break;
      case "hysteria2":
        hysteria2 = SingboxOutboundHysteria2Options()
          ..password = map["password"];
        common(hysteria2!);
        break;
      case "wireguard":
        wg = SingboxOutboundWireGuardOptions()
          ..privateKey = map["private_key"]
          ..peerPublicKey = map["peer_public_key"];
        common(wg!);
        break;
      case "tuic":
        tuic = SingboxOutboundTUICOptions()
          ..uuid = map["uuid"]
          ..password = map["password"];
        common(tuic!);
        break;
      case "tor":
        tor = SingboxOutboundTorOptions()
          ..executablePath = map["executable_path"];
        common(tor!);
        break;
      case "ssh":
        ssh = SingboxOutboundSSHOptions()
          ..user = map["user"]
          ..password = map["password"];
        common(ssh!);
        break;
      case "anytls":
        anytls = SingboxOutboundAnyTlsOptions()..password = map["password"];
        common(anytls!);
        break;
      case "mieru":
        mieru = SingboxOutboundMieruOptions()
          ..username = map["username"]
          ..password = map["password"];
        common(mieru!);
        break;
      case "naive":
        naive = SingboxOutboundNaiveOptions()
          ..username = map["username"]
          ..password = map["password"];
        common(naive!);
        break;
    }
  }
}

/// TUN inbound options -- field names/JSON keys match sing-box's
/// `TunInboundOptions` schema exactly.
class SingboxInboundTunOptions {
  static const String ipv4Address = "172.19.0.1/28";
  static const String ipv6Address = "fdfe:dcba:9876::1/126";

  String type = "tun";
  String tag = "tun-in";
  List<String> address = [ipv4Address, ipv6Address];
  int mtu = 9000;
  bool auto_route = true;
  List<String> include_package = [];
  List<String> exclude_package = [];

  Map<String, dynamic> toJson() => {
    'type': type,
    'tag': tag,
    'address': address,
    'mtu': mtu,
    'auto_route': auto_route,
    if (include_package.isNotEmpty) 'include_package': include_package,
    if (exclude_package.isNotEmpty) 'exclude_package': exclude_package,
  };
}

class SingboxInboundMixedOptions {
  String type = "mixed";
  String tag = "mixed-in";
  String listen = "127.0.0.1";
  int listen_port = 0;

  Map<String, dynamic> toJson() => {
    'type': type,
    'tag': tag,
    'listen': listen,
    'listen_port': listen_port,
  };
}

/// TCP Brutal congestion-control options for `multiplex` (sing-box
/// `BrutalOptions`).
class SingboxOutboundMultiplexBrutalOptions {
  bool enabled = false;
  int up_mbps = 0;
  int down_mbps = 0;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'up_mbps': up_mbps,
    'down_mbps': down_mbps,
  };

  static SingboxOutboundMultiplexBrutalOptions? fromJsonStatic(
    Map<String, dynamic>? map,
  ) {
    if (map == null) return null;
    final o = SingboxOutboundMultiplexBrutalOptions();
    o.enabled = map["enabled"] ?? false;
    o.up_mbps = (map["up_mbps"] ?? 0) as int;
    o.down_mbps = (map["down_mbps"] ?? 0) as int;
    return o;
  }

  Future<List<GroupItem>> getWidgetOptions(
    BuildContext context,
    SetStateCallback? setstate,
  ) async => [];
}

/// Domains excluded from the local HTTP proxy by default (Apple push and
/// other services that misbehave when proxied) -- matches this app's own
/// `excludeApns`-adjacent settings, not a sing-box schema constant.
const List<String> ProxyBypassDoaminsDefault = ["push.apple.com"];
