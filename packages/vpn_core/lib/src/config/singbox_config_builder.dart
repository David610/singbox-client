import 'dart:convert';

/// Builds sing-box outbound JSON objects for the protocols this client
/// supports, and parses the corresponding share-link URI formats.
///
/// This module does NOT implement any cryptography or wire protocol — it
/// only assembles/parses JSON and URIs to the exact shape documented by
/// upstream sing-box (github.com/sagernet/sing-box, package `option`,
/// pinned version — see packages/vpn_core/UPSTREAM_VERSION.md). All actual
/// TLS/REALITY/VLESS/Hysteria2 protocol work happens inside the pinned
/// sing-box core at runtime.
///
/// Field names below are taken directly from sing-box `option.VLESSOutboundOptions`,
/// `option.OutboundTLSOptions`, `option.OutboundRealityOptions`,
/// `option.OutboundUTLSOptions`, and `option.Hysteria2OutboundOptions`
/// (verified against sing-box v1.13.19 source).
class VlessRealityParams {
  const VlessRealityParams({
    required this.tag,
    required this.server,
    required this.serverPort,
    required this.uuid,
    this.flow = 'xtls-rprx-vision',
    required this.sni,
    required this.publicKey,
    required this.shortId,
    this.fingerprint = 'chrome',
  });

  final String tag;
  final String server;
  final int serverPort;

  /// VLESS user UUID. Treated as a credential: never logged, never included
  /// in a `toString()`.
  final String uuid;

  /// XTLS flow control, e.g. "xtls-rprx-vision". Empty string disables flow.
  final String flow;

  final String sni;

  /// REALITY public key (base64url, no padding). Credential-adjacent but
  /// public by protocol design; still excluded from logs for consistency.
  final String publicKey;

  final String shortId;
  final String fingerprint;

  Map<String, Object?> toOutboundJson() => {
    'type': 'vless',
    'tag': tag,
    'server': server,
    'server_port': serverPort,
    'uuid': uuid,
    if (flow.isNotEmpty) 'flow': flow,
    'tls': {
      'enabled': true,
      'server_name': sni,
      'utls': {'enabled': true, 'fingerprint': fingerprint},
      'reality': {
        'enabled': true,
        'public_key': publicKey,
        'short_id': shortId,
      },
    },
  };

  @override
  String toString() =>
      'VlessRealityParams(tag: $tag, server: $server:$serverPort, '
      'flow: $flow, sni: $sni) [uuid/public_key/short_id redacted]';
}

class Hysteria2Params {
  const Hysteria2Params({
    required this.tag,
    required this.server,
    required this.serverPort,
    required this.password,
    this.salamanderPassword,
    this.sni,
    this.insecure = false,
  });

  final String tag;
  final String server;
  final int serverPort;

  /// Hysteria2 auth password. Credential: never logged.
  final String password;

  /// Salamander obfuscation password, if the profile enables obfs. Also a
  /// credential.
  final String? salamanderPassword;

  final String? sni;
  final bool insecure;

  Map<String, Object?> toOutboundJson() => {
    'type': 'hysteria2',
    'tag': tag,
    'server': server,
    'server_port': serverPort,
    'password': password,
    if (salamanderPassword != null && salamanderPassword!.isNotEmpty)
      'obfs': {'type': 'salamander', 'password': salamanderPassword},
    'tls': {
      'enabled': true,
      if (sni != null) 'server_name': sni,
      if (insecure) 'insecure': true,
    },
  };

  @override
  String toString() =>
      'Hysteria2Params(tag: $tag, server: $server:$serverPort, '
      'obfs: ${salamanderPassword != null ? "salamander" : "none"}) '
      '[password/salamanderPassword redacted]';
}

class SingBoxUriParseException implements Exception {
  const SingBoxUriParseException(this.message);
  final String message;
  @override
  String toString() => 'SingBoxUriParseException: $message';
}

class SingBoxConfigBuilder {
  const SingBoxConfigBuilder._();

  /// Parses a `vless://uuid@host:port?params#tag` share link.
  ///
  /// Recognized query parameters: `security` (must be "reality" for this
  /// parser — plain-TLS/none VLESS is out of scope for this helper), `flow`,
  /// `sni`, `pbk` (REALITY public key), `sid` (REALITY short id), `fp`
  /// (uTLS fingerprint).
  static VlessRealityParams parseVlessRealityUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'vless') {
      throw const SingBoxUriParseException('not a vless:// URI');
    }
    // Uri.userInfo returns the RAW, still-percent-encoded component --
    // Uri does not auto-decode it the way it does queryParameters. Must
    // decode explicitly or a credential containing a reserved character
    // (e.g. '@', found by a real hysteria2:// password in this parser's
    // sibling case below) comes out wrong. See
    // singbox_config_builder_test.dart's percent-encoded-password case.
    final uuid = Uri.decodeComponent(parsed.userInfo);
    if (uuid.isEmpty) {
      throw const SingBoxUriParseException('missing uuid');
    }
    if (parsed.host.isEmpty || parsed.port == 0) {
      throw const SingBoxUriParseException('missing host/port');
    }
    final q = parsed.queryParameters;
    final security = q['security'];
    if (security != 'reality') {
      throw SingBoxUriParseException(
        'unsupported security=$security (only "reality" is handled by '
        'this parser)',
      );
    }
    final publicKey = q['pbk'];
    if (publicKey == null || publicKey.isEmpty) {
      throw const SingBoxUriParseException('missing pbk (REALITY public key)');
    }
    return VlessRealityParams(
      tag: Uri.decodeComponent(
        parsed.fragment.isNotEmpty ? parsed.fragment : parsed.host,
      ),
      server: parsed.host,
      serverPort: parsed.port,
      uuid: uuid,
      // An absent `flow` parameter means "no flow", NOT "assume Vision" --
      // see the "xtls-rprx-vision where supplied" compatibility target and
      // singbox_vpn_compat_test.dart's `vision_off` case, traced against
      // singbox-vpn's own `render_vless_reality_uri_vision_off` (which
      // omits `flow` entirely on purpose, for a real per-user server-side
      // opt-out -- see that function's doc comment). An earlier version of
      // this parser defaulted a missing `flow` back to
      // 'xtls-rprx-vision', which silently re-added Vision for exactly the
      // profile designed to omit it.
      flow: q['flow'] ?? '',
      sni: q['sni'] ?? parsed.host,
      publicKey: publicKey,
      shortId: q['sid'] ?? '',
      fingerprint: q['fp'] ?? 'chrome',
    );
  }

  /// Parses a `hysteria2://password@host:port?params#tag` (a.k.a. `hy2://`)
  /// share link.
  ///
  /// Recognized query parameters: `obfs` (must be "salamander" when
  /// present), `obfs-password`, `sni`, `insecure` ("1"/"true").
  static Hysteria2Params parseHysteria2Uri(String uri) {
    var parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.scheme == 'hy2') {
      parsed = Uri.tryParse(uri.replaceFirst('hy2://', 'hysteria2://'));
    }
    if (parsed == null || parsed.scheme != 'hysteria2') {
      throw const SingBoxUriParseException('not a hysteria2:// or hy2:// URI');
    }
    // Same decoding note as parseVlessRealityUri's uuid above -- Uri
    // does not auto-decode userInfo. Found by a real CI run: a password
    // containing '@' (percent-encoded to '%40' in the URI, as any real
    // password generator would produce) was coming out of this parser
    // still percent-encoded, silently wrong rather than throwing.
    final password = Uri.decodeComponent(parsed.userInfo);
    if (password.isEmpty) {
      throw const SingBoxUriParseException('missing password');
    }
    if (parsed.host.isEmpty || parsed.port == 0) {
      throw const SingBoxUriParseException('missing host/port');
    }
    final q = parsed.queryParameters;
    final obfsType = q['obfs'];
    if (obfsType != null && obfsType.isNotEmpty && obfsType != 'salamander') {
      throw SingBoxUriParseException('unsupported obfs type: $obfsType');
    }
    final insecureRaw = q['insecure'];
    return Hysteria2Params(
      tag: Uri.decodeComponent(
        parsed.fragment.isNotEmpty ? parsed.fragment : parsed.host,
      ),
      server: parsed.host,
      serverPort: parsed.port,
      password: password,
      salamanderPassword: obfsType == 'salamander' ? q['obfs-password'] : null,
      sni: q['sni'],
      insecure: insecureRaw == '1' || insecureRaw == 'true',
    );
  }

  /// Wraps a single outbound object in a minimal, valid sing-box document:
  /// the outbound itself plus a `tun` inbound with sane defaults and
  /// `auto`/`direct`/`block` outbounds selectable by tag. Callers that need
  /// custom routing/DNS should build on top of this rather than modify it
  /// in place, so this method stays a single well-tested source of the
  /// "minimum viable tunnel config" shape.
  ///
  /// TUN addressing uses `option.TunInboundOptions.Address` (the unified
  /// `address` field), NOT the legacy `inet4_address`/`inet6_address`
  /// fields -- those are marked `// Deprecated: merged to Address` in
  /// sing-box's own `option/tun.go` and are a HARD ERROR (not just a
  /// warning) as of the pinned v1.13.19: `protocol/tun/inbound.go`
  /// rejects any config carrying them with "legacy tun address fields are
  /// deprecated in sing-box 1.10.0 and removed in sing-box 1.12.0". This
  /// was verified against the pinned tag's actual source (see
  /// packages/vpn_core/UPSTREAM_VERSION.md), not assumed from the
  /// migration docs alone. The DNS server below similarly uses the
  /// current `type`/`server` schema rather than the legacy
  /// `tag`/`address` shorthand -- that one is only *deprecated* (not yet
  /// removed) at v1.13.19, but avoiding it here means one fewer thing to
  /// revisit when the pin eventually moves past v1.14.0.
  static String buildSingleOutboundDocument({
    required Map<String, Object?> outbound,
    bool udpEnabled = true,
    String tunInterfaceName = 'sbx-tun',
    List<String> tunInet4Address = const ['172.19.0.1/28'],
    List<String> tunInet6Address = const ['fdfe:dcba:9876::1/126'],
  }) {
    final tag = outbound['tag'] as String;
    final doc = {
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {'type': 'tls', 'tag': 'remote', 'server': '8.8.8.8'},
        ],
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': tunInterfaceName,
          'address': [...tunInet4Address, ...tunInet6Address],
          'mtu': 9000,
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'udp_timeout': udpEnabled ? '5m' : null,
        },
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {'final': tag, 'auto_detect_interface': true},
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Parses a full sing-box client subscription document — the exact shape
  /// `GET /sub/{token}` (default `format=singbox`) returns, e.g. from
  /// `render_singbox_client_subscription_with_options` in singbox-vpn's
  /// `crates/compat-config/src/render.rs` — and returns its `outbounds`
  /// array as a list of maps, in document order. This is the entry point
  /// for "subscription URL import": callers fetch the URL themselves
  /// (a plain HTTPS GET, out of scope for this parser) and hand the
  /// response body here.
  static List<Map<String, Object?>> extractOutboundsFromSubscription(
    String subscriptionJson,
  ) {
    final doc = jsonDecode(subscriptionJson) as Map<String, Object?>;
    final outbounds = doc['outbounds'];
    if (outbounds is! List) {
      throw const SingBoxUriParseException(
        'subscription document has no "outbounds" array',
      );
    }
    return outbounds.cast<Map<String, Object?>>();
  }

  /// Finds the first outbound of a given `type` (e.g. "vless", "hysteria2")
  /// in a parsed outbound list, or null if none is present.
  static Map<String, Object?>? findOutboundByType(
    List<Map<String, Object?>> outbounds,
    String type,
  ) {
    for (final ob in outbounds) {
      if (ob['type'] == type) return ob;
    }
    return null;
  }
}
