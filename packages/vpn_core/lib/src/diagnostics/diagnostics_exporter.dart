import 'dart:convert';

import 'diagnostics_models.dart';
import 'redaction.dart';

/// Produces a paste-into-a-GitHub-issue bundle from a
/// [DiagnosticsSnapshot], in either JSON or a short human-readable text
/// form. Both formats pass through [redactText] as a final,
/// whole-bundle defense-in-depth sweep, on top of [DiagnosticsSnapshot]'s
/// own field-level redaction (see that class's doc comment) -- two
/// independent layers, so a bug in one doesn't mean a credential leak;
/// see redaction_test.dart's "export never contains a credential even if
/// a field is misused" style tests.
class DiagnosticsExporter {
  const DiagnosticsExporter();

  String exportJson(DiagnosticsSnapshot snapshot) {
    final raw = const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
    return redactText(raw);
  }

  String exportText(DiagnosticsSnapshot snapshot) {
    final json = snapshot.toJson();
    final buffer = StringBuffer()
      ..writeln('singbox-client diagnostics')
      ..writeln('captured: ${json['capturedAt']}')
      ..writeln()
      ..writeln('app: ${json['appVersion']} (${json['appBuildSha']})')
      ..writeln('platform: ${json['platform']} ${json['osVersion']}')
      ..writeln('vpn core: ${json['vpnCoreVersion'] ?? 'unknown'}')
      ..writeln()
      ..writeln('vpn state: ${json['vpnState']}')
      ..writeln(
        'profile: ${json['selectedProfileLabel'] ?? '(none)'} '
        '${json['profileIdentifierRedacted'] ?? ''}',
      )
      ..writeln('transport: ${json['selectedTransport'] ?? 'unknown'}')
      ..writeln('server hostname: ${json['serverHostname'] ?? 'unknown'}')
      ..writeln('tunnel uptime: ${_formatSeconds(json['tunnelUptimeSeconds'])}')
      ..writeln('reconnect count: ${json['reconnectCount']}')
      ..writeln()
      ..writeln('public ip before: ${json['publicIpBefore'] ?? 'not measured'}')
      ..writeln('public ip after: ${json['publicIpAfter'] ?? 'not measured'}')
      ..writeln()
      ..writeln('ipv4: ${_formatProbe(json['ipv4'])}')
      ..writeln('ipv6: ${_formatProbe(json['ipv6'])}')
      ..writeln('dns: ${_formatProbe(json['dns'])}')
      ..writeln('tcp: ${_formatProbe(json['tcp'])}')
      ..writeln('udp: ${_formatProbe(json['udp'])}')
      ..writeln('quic (heuristic): ${_formatProbe(json['quicHeuristic'])}')
      ..writeln('approx. latency: ${json['approximateLatencyMs'] ?? 'n/a'} ms')
      ..writeln();
    if (json['lastEngineError'] != null) {
      buffer
        ..writeln('last engine error (sanitized):')
        ..writeln(json['lastEngineError']);
    }
    return redactText(buffer.toString());
  }

  String _formatProbe(Object? probeJson) {
    if (probeJson is! Map) return 'unknown';
    final status = probeJson['status'];
    final latency = probeJson['latencyMs'];
    final detail = probeJson['detail'];
    final parts = <String>[
      '$status',
      if (latency != null) '${latency}ms',
      if (detail != null) '($detail)',
    ];
    return parts.join(' ');
  }

  /// Exports the full sanitized engine log (as opposed to
  /// [DiagnosticsSnapshot.lastEngineError], which is a single most-recent
  /// error line on the snapshot). A deliberately separate, explicit
  /// action -- see [VpnCore.getSanitizedLogs] -- not bundled into
  /// [exportJson]/[exportText] by default, so a user exporting a quick
  /// status bundle doesn't unexpectedly attach a much larger log blob.
  String exportFullLog(List<String> sanitizedLogLines) {
    final joined = sanitizedLogLines.join('\n');
    return redactText(joined);
  }

  String _formatSeconds(Object? seconds) {
    if (seconds is! int) return 'not connected';
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h}h ${m}m ${s}s';
  }
}
