// Self-contained diagnostics screen. Deliberately depends only on
// package:vpn_core, package:flutter, and the two info plugins already in
// pubspec.yaml (package_info_plus, device_info_plus) -- NOT on any of the
// still-missing lib/app/utils/ modules or the unreconstructed
// VPNService/ProxyConfig/ServerConfig classes (see
// docs/ARCHITECTURE.md §9). This means it can be developed, tested, and
// reviewed independently of that larger reconstruction, and is wired into
// app navigation once that lands -- see this file's bottom note.
//
// Shows sanitized VPN/network diagnostics and never displays a raw
// credential -- see packages/vpn_core/lib/src/diagnostics/redaction.dart,
// which every value shown or exported here passes through.
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vpn_core/vpn_core.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    this.serverHostname,
    this.selectedTransport,
    this.vlessUuidForCorrelation,
  });

  /// Caller-supplied context this screen cannot discover on its own --
  /// see AppContext's own doc comment for why this boundary exists.
  final String? serverHostname;
  final String? selectedTransport;
  final String? vlessUuidForCorrelation;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final DiagnosticsCollector _collector;
  final _exporter = const DiagnosticsExporter();

  DiagnosticsSnapshot? _snapshot;
  bool _loading = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _collector = DiagnosticsCollector();
    _refreshStatic();
  }

  @override
  void dispose() {
    _collector.dispose();
    super.dispose();
  }

  Future<AppContext> _buildAppContext() async {
    final packageInfo = await PackageInfo.fromPlatform();
    var osVersion = Platform.operatingSystemVersion;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        osVersion = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        osVersion = '${info.systemName} ${info.systemVersion}';
      }
    } catch (_) {
      // Fall back to Platform.operatingSystemVersion above -- never let a
      // device-info failure block the rest of the diagnostics snapshot.
    }

    return AppContext(
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      // Full build identifiers (e.g. a package_info buildNumber that
      // happens to be a long CI-generated string) are truncated to a
      // short, safe form by DiagnosticsCollector itself -- see
      // AppContext.appBuildSha's doc comment for why a short value
      // matters here.
      appBuildSha: packageInfo.buildNumber,
      platform: Platform.operatingSystem,
      osVersion: osVersion,
      serverHostname: widget.serverHostname,
      selectedTransport: widget.selectedTransport,
      vlessUuidForCorrelation: widget.vlessUuidForCorrelation,
    );
  }

  Future<void> _refreshStatic() async {
    setState(() => _loading = true);
    final app = await _buildAppContext();
    final snap = await _collector.captureStatic(app);
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
  }

  Future<void> _captureIpBaseline() async {
    setState(() => _running = true);
    await _collector.capturePublicIpBaseline();
    final app = await _buildAppContext();
    final snap = await _collector.captureStatic(app);
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _running = false;
    });
  }

  Future<void> _runConnectivityTests({required bool includePublicIp}) async {
    setState(() => _running = true);
    final app = await _buildAppContext();
    final snap = await _collector.captureWithProbes(app, includePublicIp: includePublicIp);
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _running = false;
    });
  }

  Future<void> _exportDiagnostics() async {
    final snap = _snapshot;
    if (snap == null) return;
    final text = _exporter.exportText(snap);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export diagnostics'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Copy to clipboard'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export diagnostics',
            onPressed: snap == null ? null : _exportDiagnostics,
          ),
        ],
      ),
      body: _loading || snap == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStatic,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _section('App', [
                    _row('Version', snap.appVersion),
                    _row('Build', snap.appBuildSha),
                    _row('Platform', '${snap.platform} ${snap.osVersion}'),
                  ]),
                  _section('VPN', [
                    _row('State', snap.vpnState.name),
                    _row('Profile', snap.selectedProfileLabel ?? '(none)'),
                    _row('Transport', snap.selectedTransport ?? 'unknown'),
                    _row('Core version', snap.vpnCoreVersion ?? 'unknown'),
                    _row('Server hostname', snap.serverHostname ?? 'unknown'),
                    _row(
                      'Tunnel uptime',
                      snap.tunnelUptime == null ? 'not connected' : snap.tunnelUptime.toString(),
                    ),
                    _row('Reconnect count', '${snap.reconnectCount}'),
                    if (snap.lastEngineError != null)
                      _row('Last engine error', snap.lastEngineError!),
                  ]),
                  _section('Connectivity', [
                    _probeRow('IPv4', snap.ipv4),
                    _probeRow('IPv6', snap.ipv6),
                    _probeRow('DNS', snap.dns),
                    _probeRow('TCP', snap.tcp),
                    _probeRow('UDP', snap.udp),
                    _probeRow('QUIC/HTTP3 (heuristic)', snap.quicHeuristic),
                    _row(
                      'Approx. latency',
                      snap.approximateLatency == null ? 'n/a' : '${snap.approximateLatency!.inMilliseconds} ms',
                    ),
                  ]),
                  _section('Public IP', [
                    _row('Before', snap.publicIpBefore ?? 'not measured'),
                    _row('After', snap.publicIpAfter ?? 'not measured'),
                  ]),
                  const SizedBox(height: 16),
                  const Text(
                    'Running connectivity tests contacts a small set of fixed, '
                    'well-known infrastructure hosts (and, only if you tap '
                    '"Check public IP", a third-party IP-lookup service) to prove '
                    'reachability. Nothing about your browsing destinations is '
                    'recorded. See docs/DEVICE_ACCEPTANCE.md.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _running ? null : () => _runConnectivityTests(includePublicIp: false),
                        child: _running
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Run connectivity tests'),
                      ),
                      OutlinedButton(
                        onPressed: _running ? null : () => _runConnectivityTests(includePublicIp: true),
                        child: const Text('Run tests + check public IP'),
                      ),
                      OutlinedButton(
                        onPressed: _running ? null : _captureIpBaseline,
                        child: const Text('Capture IP baseline (before connecting)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.grey))),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );

  Widget _probeRow(String label, ProbeResult result) {
    final icon = switch (result.status) {
      ProbeStatus.pass => const Icon(Icons.check_circle, color: Colors.green, size: 18),
      ProbeStatus.fail => const Icon(Icons.cancel, color: Colors.red, size: 18),
      ProbeStatus.unknown => const Icon(Icons.help_outline, color: Colors.grey, size: 18),
    };
    final latency = result.latency == null ? '' : '  ${result.latency!.inMilliseconds}ms';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.grey))),
          icon,
          Text(latency),
        ],
      ),
    );
  }
}

// Integration note: not yet added to app navigation (the app's own
// routing lives in the still-unreconstructed lib/app/* modules -- see
// docs/ARCHITECTURE.md §9). Once that lands, push this screen the same
// way any other settings-adjacent screen is pushed, passing the active
// profile's hostname/transport/UUID (the UUID ONLY for
// vlessUuidForCorrelation -- see AppContext's doc comment; this screen
// never receives or stores the REALITY key, Hysteria2 password, or
// subscription token).
