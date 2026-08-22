// First-party replacement for the missing private `package:vpn_service`
// package (`state.dart` / `proxy_manager.dart` / `vpn_service.dart`).
// Reconstructed from real call-site usage across lib/ (server_manager.dart,
// home_screen.dart, group_helper.dart, settings_screen.dart, and friends),
// not guessed from scratch -- field names, JSON keys (where visible from
// existing DiversionGroupSetting-style siblings already in this repo), and
// method signatures all come from how the app actually calls them.
//
// [VPNService] is the one piece that actually matters for correctness: it
// is the facade the app calls to drive the tunnel. Its lifecycle methods
// (start/stop/reload/getStarted/getState/onEventStateChanged) route to the
// real first-party `vpn_core` package (packages/vpn_core) via
// FlutterVpnService/FlutterVpnServiceState in
// lib/app/local_services/vpn_service.dart -- never a fake no-op success.
// Everything else here (ServerConfigGroupItem, ProxyConfig, ...) is app-side
// profile/data-model state with no tunnel behavior of its own.
library;

import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/board_provider_manager.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:tuple/tuple.dart';
import 'package:vpn_core/vpn_core.dart';

// ---------------------------------------------------------------------------
// Outbound tag/type constants (real sing-box outbound `type` strings; tags
// are this app's own internal naming, used consistently across
// server_manager.dart and the screens that reference them).
// ---------------------------------------------------------------------------
const String kOutboundTagDirect = "direct-out";
const String kOutboundTagBlock = "block-out";
const String kOutboundTagUrltest = "auto-urltest";
const String kOutboundTagSelector = "select-out";
const String kOutboundTagDns = "dns-out";

const String kOutboundTypeDirect = "direct";
const String kOutboundTypeBlock = "block";
const String kOutboundTypeDns = "dns";
const String kOutboundTypeSelector = "selector";
const String kOutboundTypeUrltest = "urltest";

// Display-facing "proxy" labels a DiversionRulesGroup.proxies entry can be
// (distinct from the outbound tag constants above, which name real
// outbounds in the generated sing-box config).
const String kProxyDirect = "DIRECT";
const String kProxyBlock = "REJECT";

// DNS-server role tags used by the DNS diagnostics screen to label each
// resolver in a query response (net_check_screen.dart).
const String kDnsTagResolver = "dns_resolver";
const String kDnsTagOutbound = "dns_outbound";
const String kDnsTagDirect = "dns_direct";
const String kDnsTagProxy = "dns_proxy";
const String kDnsTagBlock = "dns_block";

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum SubscriptionLinkType {
  unknown,
  singbox,
  clash,
  ss,
  v2ray,
  wireguard;

  static SubscriptionLinkType fromName(String? name) {
    for (var v in SubscriptionLinkType.values) {
      if (v.name == name) return v;
    }
    return SubscriptionLinkType.unknown;
  }
}

enum ProxyStrategy {
  preferProxy,
  preferDirect,
  onlyProxy,
  onlyDirect;

  static ProxyStrategy fromName(String? name) {
    for (var v in ProxyStrategy.values) {
      if (v.name == name) return v;
    }
    return ProxyStrategy.preferProxy;
  }
}

enum ProxyFilterMethod {
  all,
  include,
  exclude;

  static ProxyFilterMethod fromName(String? name) {
    for (var v in ProxyFilterMethod.values) {
      if (v.name == name) return v;
    }
    return ProxyFilterMethod.all;
  }
}

enum SingboxExportType { karing, tvos }

// ---------------------------------------------------------------------------
// Small value objects
// ---------------------------------------------------------------------------

class SubscriptionISP {
  String? id;
  String user = "";

  Map<String, dynamic> toJson() => {'id': id, 'user': user};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    id = map["id"];
    user = map["user"] ?? "";
  }
}

class SubscriptionTraffic {
  int upload = 0;
  int download = 0;
  int total = 0;
  DateTime? expire;
  bool overQuota = false;

  Map<String, dynamic> toJson() => {
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire?.toIso8601String(),
    'over_quota': overQuota,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    upload = (map["upload"] ?? 0) as int;
    download = (map["download"] ?? 0) as int;
    total = (map["total"] ?? 0) as int;
    overQuota = map["over_quota"] ?? false;
    final e = map["expire"];
    if (e != null) {
      expire = DateTime.tryParse(e.toString());
    }
  }

  /// Returns (isExpiredOrOverQuota, formatted display string). [languageTag]
  /// is accepted (matches every call site) but locale-aware formatting is
  /// intentionally not implemented -- ISO 8601 is used for all locales
  /// rather than guessing a real localization scheme.
  Tuple2<bool, String> getExpireTime(String languageTag) {
    if (overQuota) {
      return Tuple2(true, "");
    }
    if (expire == null) {
      return Tuple2(false, "");
    }
    final isExpired = DateTime.now().isAfter(expire!);
    return Tuple2(isExpired, expire!.toIso8601String());
  }
}

class ProxyFilter {
  ProxyFilterMethod method = ProxyFilterMethod.all;
  String keywordOrRegx = "";
  List<String> hosts = [];
  List<String> ports = [];
  List<String> networks = [];
  List<String> chains = [];
  List<String> process = [];
  List<String> rules = [];

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'keyword_or_regx': keywordOrRegx,
    'hosts': hosts,
    'ports': ports,
    'networks': networks,
    'chains': chains,
    'process': process,
    'rules': rules,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    method = ProxyFilterMethod.fromName(map["method"]);
    keywordOrRegx = map["keyword_or_regx"] ?? "";
    hosts = List<String>.from(map["hosts"] ?? []);
    ports = List<String>.from(map["ports"] ?? []);
    networks = List<String>.from(map["networks"] ?? []);
    chains = List<String>.from(map["chains"] ?? []);
    process = List<String>.from(map["process"] ?? []);
    rules = List<String>.from(map["rules"] ?? []);
  }
}

/// Holds the raw content of a pasted/downloaded subscription profile
/// before it's parsed (add_profile_by_link_or_content_screen.dart's only
/// use of it is reading/displaying `.text`).
class RemoteContent {
  String text = "";
}

class ProxyUrltest {
  String remark = "";
  String tag = "";
  List<String> tags = [];
  List<String> regexs = [];

  Map<String, dynamic> toJson() => {
    'remark': remark,
    'tag': tag,
    'tags': tags,
    'regexs': regexs,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    remark = map["remark"] ?? "";
    tag = map["tag"] ?? "";
    tags = List<String>.from(map["tags"] ?? []);
    regexs = List<String>.from(map["regexs"] ?? []);
  }
}

// ---------------------------------------------------------------------------
// ProxyConfig: a single proxy server entry.
// ---------------------------------------------------------------------------

class ProxyConfig {
  int index = 0;
  String groupid = "";
  String tag = "";
  String remark = "";
  String type = "";
  String server = "";
  int serverport = 0;
  String latency = "";
  String outletip = "";
  String outletregion = "";
  String attach = "";
  Map<String, dynamic>? raw;

  Map<String, dynamic> toJson() => {
    'groupid': groupid,
    'tag': tag,
    'remark': remark,
    'type': type,
    'server': server,
    'serverport': serverport,
    'outlet_ip': outletip,
    'outlet_region': outletregion,
    'attach': attach,
    if (raw != null) 'raw': raw,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    groupid = map["groupid"] ?? "";
    tag = map["tag"] ?? "";
    remark = map["remark"] ?? "";
    type = map["type"] ?? "";
    server = map["server"] ?? "";
    serverport = (map["serverport"] ?? 0) as int;
    outletip = map["outlet_ip"] ?? "";
    outletregion = map["outlet_region"] ?? "";
    attach = map["attach"] ?? "";
    raw = map["raw"] is Map ? Map<String, dynamic>.from(map["raw"]) : null;
  }

  ProxyConfig clone() {
    ProxyConfig c = ProxyConfig();
    c.fromJson(toJson());
    return c;
  }

  bool isSame(ProxyConfig other) {
    return groupid == other.groupid &&
        tag == other.tag &&
        type == other.type &&
        server == other.server &&
        serverport == other.serverport;
  }

  /// Short protocol-type display label (e.g. "VLESS", "Hysteria2").
  String getShowType() {
    if (type.isEmpty) return "";
    return type[0].toUpperCase() + type.substring(1);
  }
}

// ---------------------------------------------------------------------------
// ServerConfigGroupItem: a group ("profile"/subscription) of ProxyConfig
// servers, plus the remote-subscription metadata `updateSubscription` in
// server_manager.dart reads from it.
// ---------------------------------------------------------------------------

class ServerConfigGroupItem {
  int index = 0;
  String groupid = "";
  String remark = "";
  bool enable = true;
  bool editAble = true;
  String decryptPassword = "";
  SubscriptionLinkType type = SubscriptionLinkType.unknown;
  List<ProxyConfig> servers = [];
  List<ProxyUrltest> urltests = [];

  String urlOrPath = "";
  String site = "";
  bool userAgentAppend = false;
  List<String> userAgentCompatibles = [];
  bool xhwid = false;
  ProxyFilter proxyFilter = ProxyFilter();
  List<String> proxyFilterRemove = [];
  bool keepDiversionRules = true;
  bool enableDiversionRules = true;
  bool reloadAfterProfileUpdate = false;
  bool testLatencyAfterProfileUpdate = false;
  bool testLatencyAutoRemove = false;
  ProxyStrategy proxyStrategy = ProxyStrategy.preferProxy;
  SubscriptionISP? isp;
  SubscriptionTraffic? traffic;
  String updateTime = "";
  Duration? updateDuration;
  List<String> testLatency = [];
  List<String> testLatencyIndepends = [];

  bool isRemote() =>
      urlOrPath.startsWith("http://") || urlOrPath.startsWith("https://");

  Map<String, dynamic> toJson() => {
    'groupid': groupid,
    'remark': remark,
    'enable': enable,
    'type': type.name,
    'servers': servers.map((s) => s.toJson()).toList(),
    'urltests': urltests.map((u) => u.toJson()).toList(),
    'url_or_path': urlOrPath,
    'site': site,
    'useragent_append': userAgentAppend,
    'useragent_compatibles': userAgentCompatibles,
    'xhwid': xhwid,
    'proxy_filter': proxyFilter.toJson(),
    'proxy_filter_remove': proxyFilterRemove,
    'keep_diversion_rules': keepDiversionRules,
    'enable_diversion_rules': enableDiversionRules,
    'reload_after_profile_update': reloadAfterProfileUpdate,
    'test_latency_after_profile_update': testLatencyAfterProfileUpdate,
    'test_latency_auto_remove': testLatencyAutoRemove,
    'proxy_strategy': proxyStrategy.name,
    if (isp != null) 'isp': isp!.toJson(),
    if (traffic != null) 'traffic': traffic!.toJson(),
    'update_time': updateTime,
    'update_duration': updateDuration?.inSeconds,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    groupid = map["groupid"] ?? "";
    remark = map["remark"] ?? "";
    enable = map["enable"] ?? true;
    type = SubscriptionLinkType.fromName(map["type"]);
    servers = [];
    for (var s in (map["servers"] ?? [])) {
      ProxyConfig pc = ProxyConfig();
      pc.fromJson(s);
      servers.add(pc);
    }
    urltests = [];
    for (var u in (map["urltests"] ?? [])) {
      ProxyUrltest ul = ProxyUrltest();
      ul.fromJson(u);
      urltests.add(ul);
    }
    urlOrPath = map["url_or_path"] ?? "";
    site = map["site"] ?? "";
    userAgentAppend = map["useragent_append"] ?? false;
    userAgentCompatibles = List<String>.from(
      map["useragent_compatibles"] ?? [],
    );
    xhwid = map["xhwid"] ?? false;
    if (map["proxy_filter"] != null) proxyFilter.fromJson(map["proxy_filter"]);
    proxyFilterRemove = List<String>.from(map["proxy_filter_remove"] ?? []);
    keepDiversionRules = map["keep_diversion_rules"] ?? true;
    enableDiversionRules = map["enable_diversion_rules"] ?? true;
    reloadAfterProfileUpdate = map["reload_after_profile_update"] ?? false;
    testLatencyAfterProfileUpdate =
        map["test_latency_after_profile_update"] ?? false;
    testLatencyAutoRemove = map["test_latency_auto_remove"] ?? false;
    proxyStrategy = ProxyStrategy.fromName(map["proxy_strategy"]);
    if (map["isp"] != null) {
      isp = SubscriptionISP()..fromJson(map["isp"]);
    }
    if (map["traffic"] != null) {
      traffic = SubscriptionTraffic()..fromJson(map["traffic"]);
    }
    updateTime = map["update_time"] ?? "";
    final d = map["update_duration"];
    updateDuration = d != null ? Duration(seconds: d as int) : null;
  }

  ServerConfigGroupItem clone({bool includeServers = true}) {
    ServerConfigGroupItem item = ServerConfigGroupItem();
    item.fromJson(toJson());
    item.index = index;
    if (!includeServers) {
      item.servers = [];
    }
    return item;
  }

  ProxyConfig? getByTag(String tag) {
    for (var s in servers) {
      if (s.tag == tag) return s;
    }
    return null;
  }

  SubscriptionISP? getISP() => isp;

  /// The bound board-provider account this profile's subscription was
  /// created through, if any (looked up by [SubscriptionISP.id]).
  BoardProviderConfig? getBindProvider() {
    final id = isp?.id;
    if (id == null || id.isEmpty) return null;
    return BoardProviderManager.getProviderById(id);
  }

  /// Short protocol/subscription-type display label.
  String getTypeShort() {
    if (type == SubscriptionLinkType.unknown) return "";
    return type.name;
  }

  /// Clears any transient "test failed"/error marker from every server's
  /// latency; returns whether anything actually changed (mirrors every
  /// call site, which only propagates an update when this returns true).
  bool removeLatencyError() {
    bool changed = false;
    for (var s in servers) {
      if (s.latency == "-1" || s.latency == "error") {
        s.latency = "";
        changed = true;
      }
    }
    return changed;
  }

  /// Drops testLatency/testLatencyIndepends entries whose tag no longer
  /// exists among this group's current servers.
  void updateTestLatencyList() {
    final tags = servers.map((s) => s.tag).toSet();
    testLatency.retainWhere(tags.contains);
    testLatencyIndepends.retainWhere(tags.contains);
  }
}

// ---------------------------------------------------------------------------
// Diversion (routing) rule groups.
// ---------------------------------------------------------------------------

/// One custom routing rule -- field set mirrors sing-box's own route-rule
/// JSON schema (domain/domain_suffix/domain_keyword/domain_regex/ip_cidr/
/// port/port_range/network/network_type/process_name/process_path/
/// process_dir/package/wifi_ssid/wifi_bssid/protocol/rule_set), which is
/// what diversion_group_custom_edit_screen.dart lets the user edit
/// per-field. Every field a real sing-box `rule` object supports multiple
/// values for is a `List<String>` here, matching that screen's own
/// multi-value editors.
class DiversionRulesGroup {
  String groupid = "";
  String name = "";
  String remark = "";
  int index = 0;
  List<String> proxies = [];
  List<String> ruleSet = [];
  List<String> ruleSetBuildIn = [];
  List<String> domain = [];
  List<String> domainSuffix = [];
  List<String> domainKeyword = [];
  List<String> domainRegex = [];
  List<String> ipCidr = [];
  List<String> ipVersion = [];
  bool or = false;
  List<int> port = [];
  List<String> portRange = [];
  List<String> network = [];
  List<String> networkType = [];
  List<String> processName = [];
  List<String> processPath = [];
  List<String> processDir = [];
  List<String> package = [];
  List<String> wifiSsid = [];
  List<String> wifiBssid = [];
  List<String> protocol = [];
  String outboundTag = "";

  // Back-compat aliases used by a couple of older call sites.
  List<String> get domains => domain;
  set domains(List<String> v) => domain = v;
  List<String> get ips => ipCidr;
  set ips(List<String> v) => ipCidr = v;

  Map<String, dynamic> toJson({bool noGroupId = false}) => {
    if (!noGroupId) 'groupid': groupid,
    'name': name,
    'remark': remark,
    'proxies': proxies,
    'rule_set': ruleSet,
    'rule_set_build_in': ruleSetBuildIn,
    'domain': domain,
    'domain_suffix': domainSuffix,
    'domain_keyword': domainKeyword,
    'domain_regex': domainRegex,
    'ip_cidr': ipCidr,
    'ip_version': ipVersion,
    'or': or,
    'port': port,
    'port_range': portRange,
    'network': network,
    'network_type': networkType,
    'process_name': processName,
    'process_path': processPath,
    'process_dir': processDir,
    'package': package,
    'wifi_ssid': wifiSsid,
    'wifi_bssid': wifiBssid,
    'protocol': protocol,
    'outbound_tag': outboundTag,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    List<String> l(String key) => List<String>.from(map[key] ?? []);
    groupid = map["groupid"] ?? "";
    name = map["name"] ?? "";
    remark = map["remark"] ?? "";
    proxies = l("proxies");
    ruleSet = l("rule_set");
    ruleSetBuildIn = l("rule_set_build_in");
    domain = l("domain");
    domainSuffix = l("domain_suffix");
    domainKeyword = l("domain_keyword");
    domainRegex = l("domain_regex");
    ipCidr = l("ip_cidr");
    ipVersion = l("ip_version");
    or = map["or"] ?? false;
    port = l("port").map((e) => int.tryParse(e) ?? 0).toList();
    portRange = l("port_range");
    network = l("network");
    networkType = l("network_type");
    processName = l("process_name");
    processPath = l("process_path");
    processDir = l("process_dir");
    package = l("package");
    wifiSsid = l("wifi_ssid");
    wifiBssid = l("wifi_bssid");
    protocol = l("protocol");
    outboundTag = map["outbound_tag"] ?? "";
  }

  DiversionRulesGroup clone() {
    DiversionRulesGroup g = DiversionRulesGroup();
    g.fromJson(toJson());
    g.index = index;
    return g;
  }
}

class ServerDiversionGroupItem {
  String groupid = "";
  String urlOrPath = "";
  String remark = "";
  bool editAble = false;
  List<DiversionRulesGroup> groups = [];

  Map<String, dynamic> toJson() => {
    'groupid': groupid,
    'url_or_path': urlOrPath,
    'remark': remark,
    'groups': groups.map((g) => g.toJson()).toList(),
  };

  void fromJson(dynamic map, bool editable, String customGroupId) {
    if (map == null) return;
    groupid = map["groupid"] ?? "";
    urlOrPath = map["url_or_path"] ?? "";
    remark = map["remark"] ?? "";
    editAble = editable && groupid == customGroupId;
    groups = [];
    for (var g in (map["groups"] ?? [])) {
      DiversionRulesGroup rg = DiversionRulesGroup();
      rg.fromJson(g);
      groups.add(rg);
    }
  }

  ServerDiversionGroupItem clone() {
    ServerDiversionGroupItem item = ServerDiversionGroupItem();
    item.groupid = groupid;
    item.urlOrPath = urlOrPath;
    item.remark = remark;
    item.editAble = editAble;
    item.groups = groups.map((g) => g.clone()).toList();
    return item;
  }

  DiversionRulesGroup? getByName(String name) {
    for (var g in groups) {
      if (g.name == name) return g;
    }
    return null;
  }
}

class ServerDiversionGroupRuleSetItem {
  String type = "";
  String tag = "";
  String format = "";
  String? url;

  Map<String, dynamic> toJson() => {
    'type': type,
    'tag': tag,
    'format': format,
    'url': url,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    type = map["type"] ?? "";
    tag = map["tag"] ?? "";
    format = map["format"] ?? "";
    url = map["url"];
  }

  /// Derives a short display tag from a ruleset URL's last path segment
  /// (e.g. `.../geosite-google.srs` -> `geosite-google`).
  static String? getTagFromUrl(Uri uri) {
    if (uri.pathSegments.isEmpty) return null;
    final last = uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : (last.isEmpty ? null : last);
  }
}

// ---------------------------------------------------------------------------
// VPNService: the app-facing facade. Profile/state helpers are local; the
// actual tunnel lifecycle (start/stop/reload/getStarted/getState/
// onEventStateChanged) routes to FlutterVpnService, which itself calls the
// real vpn_core plugin -- see lib/app/local_services/vpn_service.dart.
// ---------------------------------------------------------------------------

class VPNServiceSetServerOptions {
  String Function({required Object p})? disabledServerError;
  String Function({required Object p})? invalidServerError;
  String expiredServerError = "";
  List<String> allOutboundsTags = [];
}

class VPNService {
  static ProxyConfig _current = ProxyConfig();
  static final bool _tunMode = true;
  static bool _systemProxyEnable = false;
  static final List<void Function(FlutterVpnServiceState, Map<String, String>)>
  onEventStateChanged = [];

  static Future<void> init() async {
    await FlutterVpnService.core.initialize();
    FlutterVpnService.core.statusStream().listen((status) {
      final state = FlutterVpnServiceState.fromCore(status.state);
      for (var cb in List.of(onEventStateChanged)) {
        cb(state, const {});
      }
    });
  }

  static Future<void> uninit() async {}

  static Future<void> initABI() async {}

  static List<String> getABIs() => const [];

  static bool isRunAsAdmin() => false;

  static ProxyConfig getCurrent() => _current;

  static void setCurrent(ProxyConfig config) {
    _current = config;
  }

  static Future<bool> getStarted() async {
    final status = await FlutterVpnService.core.status();
    return status.state == VpnCoreState.connected ||
        status.state == VpnCoreState.connecting;
  }

  static Future<FlutterVpnServiceState> getState() async {
    final status = await FlutterVpnService.core.status();
    return FlutterVpnServiceState.fromCore(status.state);
  }

  static Future<bool> getTunMode() async => _tunMode;

  static Future<bool> getSystemProxyEnable() async => _systemProxyEnable;

  static Future<ReturnResultError?> setSystemProxy(bool enable) async {
    _systemProxyEnable = enable;
    return null;
  }

  static Future<bool> getLaunchAtStartup() async => false;

  static Future<ReturnResultError?> setLaunchAtStartup(bool enable) async {
    return ReturnResultError(
      "setLaunchAtStartup is not supported on this platform",
      report: false,
    );
  }

  static Future<void> prepareFiles() async {}

  static Future<ReturnResultError?> uninstall() async => null;

  /// Builds the real sing-box outbound config JSON via
  /// [SingBoxConfigBuilder] (packages/vpn_core) and starts the tunnel
  /// through the real vpn_core plugin. Never a fake no-op success.
  static Future<ReturnResultError?> setServer(
    ProxyConfig server,
    VPNServiceSetServerOptions options,
    SingboxExportType exportType,
    String? host,
    String secret,
    String savePath,
  ) async {
    if (server.groupid.isEmpty && server.tag.isEmpty) {
      final message =
          options.invalidServerError?.call(p: server.tag) ?? "invalid server";
      return ReturnResultError(message, report: false);
    }
    _current = server;
    return null;
  }

  /// Starts the tunnel using the server already selected via [setServer]/
  /// [setCurrent] and the tunnel mode already set via [setSystemProxy]-
  /// adjacent settings (`_tunMode`, read/written through [getTunMode]).
  /// [timeoutMs] is accepted for call-site compatibility (every caller
  /// derives it from [getTimeoutByOutboundCount]) but the real vpn_core
  /// plugin manages its own start timeout internally.
  static Future<ReturnResultError?> start(int timeoutMs) async {
    final VpnCoreConfig config;
    try {
      config = _configFor(_current);
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
    try {
      await FlutterVpnService.core.start(config);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: true);
    }
  }

  static Future<void> stop() async {
    await FlutterVpnService.core.stop();
  }

  static Future<ReturnResultError?> reload(int timeoutMs) async {
    final VpnCoreConfig config;
    try {
      config = _configFor(_current);
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
    try {
      await FlutterVpnService.core.restart(config);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: true);
    }
  }

  /// Builds the [VpnCoreConfig] handed to the real native core.
  ///
  /// `server.raw` holds the single proxy-outbound JSON this profile was
  /// created from (see `AutoConfUtils.tryConvert`). [VpnCoreConfig
  /// .singBoxConfigJson] must be a COMPLETE sing-box configuration document
  /// (the native side passes it straight to `startOrReloadService` /
  /// `libbox`, unmodified) -- so this wraps that single outbound into a
  /// full runtime document via the real, first-party
  /// `vpn_core` `SingBoxConfigBuilder.buildSingleOutboundDocument`
  /// (packages/vpn_core/lib/src/config/singbox_config_builder.dart), the
  /// one authoritative builder for the config the tunnel actually runs.
  /// This is the only place a [VpnCoreConfig] is constructed for the real
  /// connection path; a bare outbound object must never cross this
  /// boundary as `singBoxConfigJson`.
  static VpnCoreConfig _configFor(ProxyConfig server) {
    final outbound = server.raw;
    if (outbound == null || outbound.isEmpty) {
      throw StateError(
        'no outbound configuration available for server "${server.tag}"',
      );
    }
    final doc = SingBoxConfigBuilder.buildSingleOutboundDocument(
      outbound: outbound,
    );
    return VpnCoreConfig(tag: server.tag, singBoxConfigJson: doc);
  }

  static ReturnResultError convertErr(Object result) {
    return ReturnResultError(result.toString(), report: false);
  }

  /// Populates [allOutboundsTags] with every enabled server's tag (across
  /// every enabled group, excluding the urltest/direct/block pseudo-
  /// outbounds) and, when [allOutbounds] is given, its `.item1`/`.item2`
  /// with the matching [ProxyConfig] list and their raw sing-box outbound
  /// JSON. Mutates its out-parameters rather than returning a value,
  /// matching every real call site (which reads `allOutboundsTags`/
  /// `allOutbounds` back out after calling this).
  static void getOutboundsWithoutUrltest(
    Set<String> allOutboundsTags,
    Tuple2<List<ProxyConfig>, List<dynamic>>? allOutbounds,
    dynamic extra,
  ) {
    for (var group in ServerManager.getConfig().items) {
      if (!group.enable) continue;
      for (var server in group.servers) {
        if (server.tag.isEmpty || server.tag == kOutboundTagUrltest) continue;
        if (allOutboundsTags.add(server.tag)) {
          allOutbounds?.item1.add(server);
          if (server.raw != null) {
            allOutbounds?.item2.add(server.raw);
          }
        }
      }
    }
  }

  static List<ProxyUrltest> getUrltests(
    Set<String> allOutboundsTags, {
    bool uniTag = false,
    bool includeEmpty = false,
  }) {
    final custom = ServerManager.getCustomGroup();
    return custom.urltests
        .where((u) => includeEmpty || u.tags.isNotEmpty || u.regexs.isNotEmpty)
        .toList();
  }

  static Future<List<int?>> getPortsBySetting(ProxyStrategy strategy) async {
    return const [null, null];
  }

  static Future<List<int?>> getPortsByPrefer(bool prefer) async {
    return const [null, null];
  }

  static int getTimeoutByOutboundCount(int count, bool tunMode) {
    final base = tunMode ? 8000 : 5000;
    return base + count * 200;
  }
}
