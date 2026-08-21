import 'dart:async';

import '../models.dart';
import '../vpn_core.dart';
import 'diagnostics_models.dart';
import 'network_probes.dart';
import 'redaction.dart';

/// App-supplied context the collector cannot know on its own (it lives in
/// vpn_core, which has no dependency on package_info_plus/device_info_plus
/// or any Flutter widget). The diagnostics screen is responsible for
/// gathering these from the app layer and passing them in -- see
/// lib/screens/diagnostics_screen.dart.
class AppContext {
  const AppContext({
    required this.appVersion,
    required this.appBuildSha,
    required this.platform,
    required this.osVersion,
    this.serverHostname,
    this.selectedTransport,
    this.vlessUuidForCorrelation,
  });

  final String appVersion;

  /// Short SHA (<=12 chars) -- see [DiagnosticsSnapshot.appBuildSha]'s
  /// doc comment for why. Longer values are truncated by
  /// [DiagnosticsCollector], never rejected outright.
  final String appBuildSha;

  final String platform;
  final String osVersion;

  /// Hostname only -- see [DiagnosticsSnapshot.serverHostname]. The
  /// caller is responsible for stripping any scheme/credentials/port/
  /// query string before passing this in; [DiagnosticsCollector] does
  /// not attempt to parse a full share-link URI here (that parsing, and
  /// what's safe to keep, already lives in
  /// SingBoxConfigBuilder/VlessRealityParams/Hysteria2Params -- reuse
  /// those rather than duplicating URI handling in the diagnostics
  /// layer).
  final String? serverHostname;

  final String? selectedTransport;

  /// The real VLESS UUID, ONLY for computing
  /// [DiagnosticsSnapshot.profileIdentifierRedacted] via
  /// [redactKeepingSuffix] -- never stored, logged, or placed on the
  /// snapshot itself. Pass null when there's no active VLESS profile
  /// (e.g. a Hysteria2-only profile).
  final String? vlessUuidForCorrelation;
}

/// Orchestrates a [DiagnosticsSnapshot]: reads current VPN core state,
/// tracks uptime/reconnects by observing [VpnCore.statusStream] over the
/// collector's lifetime (nothing is persisted across app restarts --
/// "reconnect count" here means "since this collector was created", by
/// design, matching "do not log destination/connection history by
/// default"), and runs the connectivity probes in [NetworkProbes] on
/// request.
class DiagnosticsCollector {
  DiagnosticsCollector({
    VpnCore? vpnCore,
    NetworkProbes? probes,
    IpEchoService? ipEcho,
  }) : _vpnCore = vpnCore ?? VpnCore.instance,
       _probes = probes ?? const NetworkProbes(),
       _ipEcho = ipEcho ?? const HttpsIpEchoService() {
    _statusSub = _vpnCore.statusStream().listen(_onStatus);
  }

  final VpnCore _vpnCore;
  final NetworkProbes _probes;
  final IpEchoService _ipEcho;
  late final StreamSubscription<VpnCoreStatus> _statusSub;

  DateTime? _connectedSince;
  int _reconnectCount = 0;
  VpnCoreState? _lastObservedState;
  String? _publicIpBaseline;

  /// Captures "public IP before" -- call this explicitly BEFORE
  /// connecting the VPN (e.g. from a "capture baseline" action on the
  /// diagnostics screen, or automatically right before the app calls
  /// `VpnCore.start`). Every later [captureWithProbes] call with
  /// `includePublicIp: true` reports this value as `publicIpBefore`
  /// alongside its freshly-measured `publicIpAfter`, so the pair is
  /// comparable. Like [currentPublicIp]/`includePublicIp`, this makes an
  /// explicit external network call -- never invoked automatically by
  /// this class itself.
  Future<String?> capturePublicIpBaseline() async {
    _publicIpBaseline = await _ipEcho.currentPublicIp();
    return _publicIpBaseline;
  }

  void _onStatus(VpnCoreStatus status) {
    if (status.state == VpnCoreState.connected) {
      if (_lastObservedState != null && _lastObservedState != VpnCoreState.connected) {
        _reconnectCount++;
      }
      _connectedSince ??= DateTime.now();
    } else {
      _connectedSince = null;
    }
    _lastObservedState = status.state;
  }

  void dispose() => _statusSub.cancel();

  /// Captures everything that doesn't require an active network probe:
  /// VPN state, version info, uptime, reconnect count, last engine
  /// error. Cheap and safe to call often (e.g. every time the
  /// diagnostics screen is opened).
  Future<DiagnosticsSnapshot> captureStatic(AppContext app) async {
    final status = await _vpnCore.status();
    final version = await _vpnCore.coreVersion();
    final logs = await _vpnCore.getSanitizedLogs(maxLines: 50);
    final lastError = _lastErrorLine(logs);

    return DiagnosticsSnapshot(
      capturedAt: DateTime.now(),
      appVersion: app.appVersion,
      appBuildSha: _shortSha(app.appBuildSha),
      platform: app.platform,
      osVersion: app.osVersion,
      vpnState: status.state,
      selectedProfileLabel: status.activeTag,
      selectedTransport: app.selectedTransport,
      vpnCoreVersion: version,
      serverHostname: app.serverHostname,
      publicIpBefore: _publicIpBaseline,
      ipv4: ProbeResult.unknown,
      ipv6: ProbeResult.unknown,
      dns: ProbeResult.unknown,
      tcp: ProbeResult.unknown,
      udp: ProbeResult.unknown,
      quicHeuristic: ProbeResult.unknown,
      tunnelUptime: _connectedSince == null ? null : DateTime.now().difference(_connectedSince!),
      reconnectCount: _reconnectCount,
      lastEngineError: lastError,
      profileIdentifierRedacted: app.vlessUuidForCorrelation == null
          ? null
          : redactKeepingSuffix(app.vlessUuidForCorrelation!),
    );
  }

  /// Runs the full probe suite (network calls) on top of [captureStatic].
  /// Only called from the diagnostics screen's explicit "Run tests"
  /// action -- never automatically.
  Future<DiagnosticsSnapshot> captureWithProbes(
    AppContext app, {
    bool includePublicIp = false,
  }) async {
    final base = await captureStatic(app);

    final results = await Future.wait([
      _probes.ipv4(),
      _probes.ipv6(),
      _probes.dns(hostname: app.serverHostname),
      _probes.tcp(host: app.serverHostname),
      _probes.udp(),
      _probes.quicHeuristic(),
    ]);

    String? publicIp;
    if (includePublicIp) {
      publicIp = await _ipEcho.currentPublicIp();
    }

    return DiagnosticsSnapshot(
      capturedAt: base.capturedAt,
      appVersion: base.appVersion,
      appBuildSha: base.appBuildSha,
      platform: base.platform,
      osVersion: base.osVersion,
      vpnState: base.vpnState,
      selectedProfileLabel: base.selectedProfileLabel,
      selectedTransport: base.selectedTransport,
      vpnCoreVersion: base.vpnCoreVersion,
      serverHostname: base.serverHostname,
      publicIpBefore: _publicIpBaseline,
      publicIpAfter: publicIp,
      ipv4: results[0],
      ipv6: results[1],
      dns: results[2],
      tcp: results[3],
      udp: results[4],
      quicHeuristic: results[5],
      approximateLatency: results[3].latency ?? results[0].latency,
      tunnelUptime: base.tunnelUptime,
      reconnectCount: base.reconnectCount,
      lastEngineError: base.lastEngineError,
      profileIdentifierRedacted: base.profileIdentifierRedacted,
    );
  }

  String? _lastErrorLine(List<String> logs) {
    for (final line in logs.reversed) {
      final lower = line.toLowerCase();
      if (lower.contains('error') || lower.contains('fatal') || lower.contains('panic')) {
        return redactText(line);
      }
    }
    return null;
  }

  String _shortSha(String sha) => sha.length <= 12 ? sha : sha.substring(0, 12);
}
