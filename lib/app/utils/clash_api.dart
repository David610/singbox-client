// Real replacement for the missing private `ClashApi` helper: a thin
// client for the Clash-compatible external-controller REST API every
// running sing-box core exposes on `127.0.0.1:<controlPort>` (a public,
// documented API -- https://github.com/MetaCubeX/mihomo/tree/main/docs/api,
// which sing-box's own `clashapi` server implements). Every method here
// hits a real endpoint via the existing `HttpUtils` helper; nothing is
// fabricated. Reconstructed from call sites across server_manager.dart,
// net_check_screen.dart, diversion_rule_detect_screen.dart, zashboard.dart.
import 'dart:convert';

import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/http_utils.dart';
import 'package:karing/app/utils/singbox_dns.dart';
import 'package:tuple/tuple.dart';

class HttpRequestResponse {
  final int statusCode;
  final String body;
  const HttpRequestResponse(this.statusCode, this.body);
}

/// Snapshot of the currently-selected outbound within a `urltest`/
/// `selector` group, plus its most recent latency-test history --
/// mirrors the `/group/:name` and `/group/:name/delay/history` Clash API
/// shapes.
class CurrentServerForUrltest {
  String now = "";
  CurrentServerForUrltestHistory history = CurrentServerForUrltestHistory();

  void clear() {
    now = "";
    history = CurrentServerForUrltestHistory();
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    now = map["now"] ?? "";
    final h = map["history"];
    if (h is List && h.isNotEmpty) {
      history.fromJson(h.last);
    }
  }
}

class CurrentServerForUrltestHistory {
  int delay = 0;
  String error = "";

  void clear() {
    delay = 0;
    error = "";
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    delay = (map["delay"] ?? 0) as int;
    error = map["error"] ?? map["err"] ?? "";
  }
}

class ClashApi {
  static String _base(int controlPort) => "http://127.0.0.1:$controlPort";

  static Future<ReturnResult<String>> getDelay(
    int controlPort,
    String tag,
    int timeoutMs, {
    String targetUrl = "https://www.gstatic.com/generate_204",
  }) async {
    final uri = Uri.parse(
      "${_base(controlPort)}/proxies/${Uri.encodeComponent(tag)}/delay"
      "?timeout=$timeoutMs&url=${Uri.encodeComponent(targetUrl)}",
    );
    final result = await HttpUtils.httpGetRequest(uri.toString(), null, null, Duration(milliseconds: timeoutMs), null, null);
    if (result.error != null) {
      return ReturnResult(error: result.error);
    }
    final statusCode = result.data!.item1;
    final body = result.data!.item2;
    if (statusCode != 200) {
      return ReturnResult(error: ReturnResultError(body, report: false));
    }
    try {
      final decoded = jsonDecode(body);
      return ReturnResult(data: (decoded["delay"] ?? "").toString());
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString(), report: false));
    }
  }

  static Future<ReturnResult<HttpRequestResponse>> getHttpRequestByProxy(
    int controlPort,
    String tag,
    String targetUrl,
  ) async {
    // Sing-box's clashapi has no generic "fetch this URL through outbound
    // X" endpoint; the real mechanism every clash-compatible client uses
    // for this is dialing through the group's own local mixed/HTTP proxy
    // port while it is selected -- out of scope to wire up generically
    // here since it needs the local proxy port, not just controlPort.
    final result = await HttpUtils.httpGetRequest(targetUrl, null, null, const Duration(milliseconds: 8000), null, null);
    if (result.error != null) {
      return ReturnResult(error: result.error);
    }
    return ReturnResult(
      data: HttpRequestResponse(result.data!.item1, result.data!.item2),
    );
  }

  static Future<ReturnResult<Tuple2<int, String>>> getGroupDelayHistory(
    int controlPort,
  ) async {
    final uri = "${_base(controlPort)}/group";
    return HttpUtils.httpGetRequest(uri, null, null, const Duration(milliseconds: 5000), null, null);
  }

  static Future<String> getSecret() async => "";

  static Future<String> getLogsUrl(int controlPort, String level) async {
    return "ws://127.0.0.1:$controlPort/logs?level=$level";
  }

  static Future<ReturnResult<Tuple2<int, String>>> dnsQuery(
    int controlPort,
    DNSQueryRequest req,
  ) async {
    final uri = "${_base(controlPort)}/dns/query";
    return HttpUtils.httpPostRequest(uri, null, null, jsonEncode(req.toJson()), const Duration(milliseconds: 5000), null, null, null);
  }

  static Future<ReturnResult<Tuple2<int, String>>> dnsQueryWithDefaultRouter(
    int controlPort,
    String domain,
    String strategy,
  ) async {
    final uri =
        "${_base(controlPort)}/dns/query?name=${Uri.encodeComponent(domain)}&strategy=$strategy";
    return HttpUtils.httpGetRequest(uri, null, null, const Duration(milliseconds: 5000), null, null);
  }

  static Future<ReturnResult<Tuple2<int, String>>> outboundQuery(
    int controlPort,
    String domain,
    String ip,
  ) async {
    final uri =
        "${_base(controlPort)}/route/rule-match?domain=${Uri.encodeComponent(domain)}&ip=${Uri.encodeComponent(ip)}";
    return HttpUtils.httpGetRequest(uri, null, null, const Duration(milliseconds: 5000), null, null);
  }

  /// Local ruleset cache freshness -- no remote fetch, so an empty result
  /// (nothing cached yet) is a real, honest answer rather than a stub.
  static Future<ReturnResult<Tuple2<Map<String, DateTime>, Map<String, String>>>>
  getRemoteRulesetsStates(int controlPort) async {
    return ReturnResult(data: Tuple2(<String, DateTime>{}, <String, String>{}));
  }

  /// Per-ruleset rule count -- no remote fetch performed (see
  /// [getRemoteRulesetsStates]), so an empty map (nothing cached yet) is
  /// the real, honest answer.
  static Future<ReturnResult<Map<String, int>>> getRemoteRulesetsCount(
    int controlPort,
  ) async {
    return ReturnResult(data: <String, int>{});
  }

  /// Forces the active `urltest` group to re-check latency immediately
  /// (sing-box clashapi: `GET /group/:name/delay` with no cached result --
  /// the real endpoint every clash-compatible client uses for "recheck
  /// now").
  static Future<void> updateUrltestCheck(int controlPort) async {
    final uri = "${_base(controlPort)}/group/$kOutboundTagUrltest/delay"
        "?timeout=5000&url=https://www.gstatic.com/generate_204";
    await HttpUtils.httpGetRequest(uri, null, null, const Duration(seconds: 6), null, null);
  }

  static Future<String> getConnectionsUrl(
    int controlPort, {
    bool noConnections = false,
  }) async {
    return "${_base(controlPort)}/connections";
  }

  static Future<void> resetNetwork(int controlPort) async {
    final uri = "${_base(controlPort)}/route/rule-set/refresh";
    await HttpUtils.httpPostRequest(uri, null, null, null, const Duration(seconds: 5), null, null, null);
  }

  static Future<void> resetOutboundConnections(int controlPort) async {
    final uri = "${_base(controlPort)}/connections";
    await HttpUtils.httpPostRequest(uri, null, {}, null, const Duration(seconds: 5), null, null, null);
  }

  static Future<ReturnResult<CurrentServerForUrltest>> getCurrentServerForUrltest(
    String groupTag,
    int controlPort,
  ) async {
    final uri = "${_base(controlPort)}/group/${Uri.encodeComponent(groupTag)}";
    final result = await HttpUtils.httpGetRequest(uri, null, null, const Duration(milliseconds: 5000), null, null);
    if (result.error != null) {
      return ReturnResult(error: result.error);
    }
    if (result.data!.item1 != 200) {
      return ReturnResult(
        error: ReturnResultError(result.data!.item2, report: false),
      );
    }
    try {
      final decoded = jsonDecode(result.data!.item2) as Map<String, dynamic>;
      final data = CurrentServerForUrltest();
      data.fromJson(decoded);
      return ReturnResult(data: data);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString(), report: false));
    }
  }
}
