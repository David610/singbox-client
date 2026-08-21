import '../models.dart';
import 'redaction.dart';

/// Pass/fail/unknown for a single connectivity probe, with an optional
/// latency and NEVER a payload -- every probe in this module sends the
/// minimum bytes needed to prove reachability (a DNS query, a bare TCP
/// SYN/handshake) and discards the response body immediately after
/// checking it arrived; nothing about what was sent or received is
/// logged beyond pass/fail/latency.
enum ProbeStatus { pass, fail, unknown }

class ProbeResult {
  const ProbeResult({required this.status, this.latency, this.detail});

  final ProbeStatus status;
  final Duration? latency;

  /// Short, sanitized human-readable detail (e.g. "connection refused").
  /// Always passed through [redactText] before being stored -- see
  /// [ProbeResult.sanitized].
  final String? detail;

  factory ProbeResult.pass({Duration? latency, String? detail}) =>
      ProbeResult(status: ProbeStatus.pass, latency: latency, detail: detail);

  factory ProbeResult.fail({String? detail}) =>
      ProbeResult(status: ProbeStatus.fail, detail: detail);

  static const unknown = ProbeResult(status: ProbeStatus.unknown);

  ProbeResult sanitized() => ProbeResult(
    status: status,
    latency: latency,
    detail: detail == null ? null : redactText(detail!),
  );

  Map<String, Object?> toJson() => {
    'status': status.name,
    'latencyMs': latency?.inMilliseconds,
    'detail': detail,
  };
}

/// A fully-assembled, already-safe-to-display-and-export diagnostics
/// snapshot. There is deliberately no field on this class that can hold a
/// raw credential -- see the doc comment on each field for what it
/// contains instead. [DiagnosticsExporter] applies [redactText] over the
/// whole rendered bundle as defense in depth on top of that, but the
/// primary guarantee is architectural: this type cannot represent a
/// credential in the first place.
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.capturedAt,
    required this.appVersion,
    required this.appBuildSha,
    required this.platform,
    required this.osVersion,
    required this.vpnState,
    this.selectedProfileLabel,
    this.selectedTransport,
    this.vpnCoreVersion,
    this.serverHostname,
    this.publicIpBefore,
    this.publicIpAfter,
    required this.ipv4,
    required this.ipv6,
    required this.dns,
    required this.tcp,
    required this.udp,
    required this.quicHeuristic,
    this.approximateLatency,
    this.tunnelUptime,
    required this.reconnectCount,
    this.lastEngineError,
    this.profileIdentifierRedacted,
  });

  final DateTime capturedAt;

  final String appVersion;

  /// Short git SHA (<=12 chars, e.g. `git rev-parse --short HEAD`'s
  /// output) -- see redaction.dart's `_longTokenPattern` doc comment for
  /// why a SHORT sha is required: a full 40-char SHA would be masked by
  /// this module's own defense-in-depth redaction pass. Truncated
  /// defensively if a longer value is ever passed in -- see
  /// [DiagnosticsCollector].
  final String appBuildSha;

  /// e.g. "android", "ios" (Platform.operatingSystem).
  final String platform;

  final String osVersion;

  final VpnCoreState vpnState;

  /// User-assigned profile name/tag ("Reality", "Hysteria2", ...) --
  /// never the profile's credentials.
  final String? selectedProfileLabel;

  /// e.g. "vless-reality", "hysteria2".
  final String? selectedTransport;

  final String? vpnCoreVersion;

  /// Hostname ONLY (no port, no query string, no credentials) -- e.g.
  /// "vpn.example.com", never "vless://uuid@vpn.example.com:443?...".
  final String? serverHostname;

  final String? publicIpBefore;
  final String? publicIpAfter;

  final ProbeResult ipv4;
  final ProbeResult ipv6;
  final ProbeResult dns;
  final ProbeResult tcp;
  final ProbeResult udp;

  /// "Appears available" is deliberate hedging, not vagueness: this is a
  /// UDP/443 reachability heuristic (see network_probes.dart), not a real
  /// QUIC/HTTP3 handshake -- it can't distinguish "QUIC is blocked" from
  /// "this specific heuristic target doesn't answer the way expected."
  final ProbeResult quicHeuristic;

  final Duration? approximateLatency;
  final Duration? tunnelUptime;
  final int reconnectCount;

  /// The single most recent sanitized engine log line that looked like
  /// an error, already passed through [redactText] -- see
  /// [DiagnosticsCollector]. Never the raw log, never more than one line
  /// (this is a snapshot field, not a log export -- exporting the full
  /// sanitized log is a separate, explicit action; see
  /// [DiagnosticsExporter.exportFull]).
  final String? lastEngineError;

  /// e.g. "****d8d9" -- see [redactKeepingSuffix]. Never the real VLESS
  /// UUID. Null when there is no active profile to identify.
  final String? profileIdentifierRedacted;

  Map<String, Object?> toJson() => {
    'capturedAt': capturedAt.toIso8601String(),
    'appVersion': appVersion,
    'appBuildSha': appBuildSha,
    'platform': platform,
    'osVersion': osVersion,
    'vpnState': vpnState.name,
    'selectedProfileLabel': selectedProfileLabel,
    'selectedTransport': selectedTransport,
    'vpnCoreVersion': vpnCoreVersion,
    'serverHostname': serverHostname,
    'publicIpBefore': publicIpBefore,
    'publicIpAfter': publicIpAfter,
    'ipv4': ipv4.sanitized().toJson(),
    'ipv6': ipv6.sanitized().toJson(),
    'dns': dns.sanitized().toJson(),
    'tcp': tcp.sanitized().toJson(),
    'udp': udp.sanitized().toJson(),
    'quicHeuristic': quicHeuristic.sanitized().toJson(),
    'approximateLatencyMs': approximateLatency?.inMilliseconds,
    'tunnelUptimeSeconds': tunnelUptime?.inSeconds,
    'reconnectCount': reconnectCount,
    'lastEngineError': lastEngineError == null
        ? null
        : redactText(lastEngineError!),
    'profileIdentifierRedacted': profileIdentifierRedacted,
  };
}
