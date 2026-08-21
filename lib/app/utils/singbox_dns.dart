// Real replacement for the missing private DNS-testing helpers used by
// `ServerManager.testDNSConnectLatency` (server_manager.dart) to build a
// sing-box DNS-server-batch query against the running core's Clash-style
// `/dns/query` endpoint (see clash_api.dart). Field/method shapes come
// from that one real call site.
import 'package:karing/app/runtime/return_result.dart';

class SingboxDNSDomainResolver {
  SingboxDNSDomainResolver({required this.server, required this.strategy});
  String server;
  String strategy;

  Map<String, dynamic> toJson() => {'server': server, 'strategy': strategy};
}

class SingboxDNSServerBatchOptions {
  SingboxDNSServerBatchOptions(this.tag, {required this.servers});
  String tag;
  List<String> servers;

  Map<String, dynamic> toJson() => {'tag': tag, 'servers': servers};
}

/// Parses each entry in [urls] into a `SingboxDNSServerBatchOptions`-
/// compatible server tag list, one server per URL, tagged
/// `dns_latency_test_<index>`, and optionally routed through [detour].
ReturnResult<List<SingboxDNSServerBatchOptions>> SingboxDNSTryParseList(
  List<String> urls,
  String? detour,
  SingboxDNSDomainResolver resolver,
) {
  if (urls.isEmpty) {
    return ReturnResult(data: []);
  }
  List<SingboxDNSServerBatchOptions> servers = [];
  for (int i = 0; i < urls.length; i++) {
    final uri = Uri.tryParse(urls[i]);
    if (uri == null) {
      return ReturnResult(
        error: ReturnResultError(
          "invalid DNS server url: ${urls[i]}",
          report: false,
        ),
      );
    }
    servers.add(
      SingboxDNSServerBatchOptions(
        "dns_latency_test_${i}_${uri.host}",
        servers: [urls[i]],
      ),
    );
  }
  return ReturnResult(data: servers);
}

class DNSQueryRequest {
  String tag = "";
  String domain = "";
  String strategy = "";
  List<SingboxDNSServerBatchOptions> servers = [];

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'domain': domain,
    'strategy': strategy,
    'servers': servers,
  };
}

class DNSQueryResponse {
  String? err;
  int latency = 0;
  List<String> addr = [];

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    err = map["err"];
    latency = (map["latency"] ?? 0) as int;
    addr = List<String>.from(map["addr"] ?? []);
  }
}
