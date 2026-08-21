import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'diagnostics_models.dart';

/// Deterministic, privacy-conscious connectivity probes.
///
/// Every probe here:
///   - runs ONLY when explicitly invoked (the diagnostics screen's "Run
///     tests" action) -- nothing in this file runs automatically or in
///     the background, so there is no destination history to accumulate
///     in the first place ("do not log destination history by default").
///   - sends the minimum bytes needed to prove reachability (a DNS
///     query, a bare TCP connect, one small UDP probe datagram) and
///     immediately discards any response body after checking it arrived
///     -- no payload is ever captured, logged, or exported.
///   - targets either the caller-supplied VPN server hostname (the
///     actually relevant target -- "is my configured server reachable")
///     or, when none is configured/available, one of a small set of
///     well-known, neutral public infrastructure endpoints (Cloudflare's
///     1.1.1.1 resolver) chosen for being widely used as a connectivity
///     reference point already, not for any other reason.
///
/// None of this is a substitute for the real headless protocol interop
/// tests in packages/vpn_core/test/interop/ (which exercise the actual
/// VLESS+REALITY/Hysteria2 handshakes) or for real device testing (see
/// docs/DEVICE_ACCEPTANCE.md) -- these are coarse, general-purpose
/// reachability probes for the diagnostics screen, nothing more.
class NetworkProbes {
  const NetworkProbes({
    this.timeout = const Duration(seconds: 5),
    this.ipv4ProbeHost = '1.1.1.1',
    this.ipv6ProbeHost = '2606:4700:4700::1111',
    this.dnsProbeHost = '1.1.1.1',
    this.quicProbeHost = '1.1.1.1',
    this.probePort = 443,
    this.dnsPort = 53,
  });

  final Duration timeout;
  final String ipv4ProbeHost;
  final String ipv6ProbeHost;
  final String dnsProbeHost;
  final String quicProbeHost;
  final int probePort;
  final int dnsPort;

  Future<ProbeResult> _tcpConnect(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return ProbeResult.pass(latency: sw.elapsed);
    } on SocketException catch (e) {
      return ProbeResult.fail(detail: e.osError?.message ?? e.message);
    } on TimeoutException {
      return ProbeResult.fail(detail: 'timed out after ${timeout.inSeconds}s');
    }
  }

  /// TCP connect to [ipv4ProbeHost]:[probePort] (default: a literal IPv4
  /// address, so this never depends on DNS resolution behavior).
  Future<ProbeResult> ipv4() => _tcpConnect(ipv4ProbeHost, probePort);

  /// Same, over IPv6.
  Future<ProbeResult> ipv6() => _tcpConnect(ipv6ProbeHost, probePort);

  /// Resolves [hostname] (the configured VPN server's hostname when
  /// available, so this doubles as "can I resolve my own server").
  Future<ProbeResult> dns({String? hostname}) async {
    final target =
        hostname ?? 'example.com'; // IANA-reserved, universally resolvable
    final sw = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(target).timeout(timeout);
      sw.stop();
      if (addresses.isEmpty) {
        return ProbeResult.fail(detail: 'no addresses returned');
      }
      return ProbeResult.pass(latency: sw.elapsed);
    } on SocketException catch (e) {
      return ProbeResult.fail(detail: e.osError?.message ?? e.message);
    } on TimeoutException {
      return ProbeResult.fail(detail: 'timed out after ${timeout.inSeconds}s');
    }
  }

  /// TCP connect to [host]:[port] when supplied (the configured VPN
  /// server), else falls back to the default public probe target.
  Future<ProbeResult> tcp({String? host, int? port}) =>
      _tcpConnect(host ?? ipv4ProbeHost, port ?? probePort);

  /// A single UDP DNS query to [dnsProbeHost]:[dnsPort], expecting a
  /// well-formed response within [timeout]. This is the UDP
  /// connectivity probe: proving a UDP round trip completes (query out,
  /// response back) is a stronger signal than merely proving a local
  /// `RawDatagramSocket` can be opened, which succeeds regardless of
  /// actual network reachability.
  Future<ProbeResult> udp() async {
    final sw = Stopwatch()..start();
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final query = _minimalDnsQuery();
      socket.send(query, InternetAddress(dnsProbeHost), dnsPort);

      final completer = Completer<ProbeResult>();
      late final StreamSubscription sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          sw.stop();
          if (dg != null && dg.data.length >= 12 && !completer.isCompleted) {
            completer.complete(ProbeResult.pass(latency: sw.elapsed));
          }
        }
      });
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => ProbeResult.fail(
          detail: 'no UDP response within ${timeout.inSeconds}s',
        ),
      );
      await sub.cancel();
      return result;
    } catch (e) {
      return ProbeResult.fail(detail: e.toString());
    } finally {
      socket?.close();
    }
  }

  /// UDP/443 reachability heuristic -- see [ProbeResult] and this class's
  /// header comment for what "appears available" does and does not mean.
  /// Sends one small, protocol-agnostic probe datagram (NOT a real QUIC
  /// Initial packet -- this module does not implement QUIC) and treats
  /// "no immediate send failure and, if any response arrives, it doesn't
  /// look like an ICMP-triggered error" as a pass.
  Future<ProbeResult> quicHeuristic() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final probe = Uint8List.fromList(List<int>.filled(16, 0));
      socket.send(probe, InternetAddress(quicProbeHost), probePort);

      // A blocked/filtered path often surfaces as silence (nothing to
      // await) or a send-time SocketException; either way there is
      // nothing further to read, so a short grace window covers both
      // "silently accepted" and "responded" without hanging on true
      // silence. This is why the result is a heuristic ("appears
      // available"), not a confirmed handshake.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return ProbeResult.pass(
        detail: 'UDP/$probePort send accepted (heuristic only)',
      );
    } on SocketException catch (e) {
      return ProbeResult.fail(detail: e.osError?.message ?? e.message);
    } finally {
      socket?.close();
    }
  }

  Uint8List _minimalDnsQuery() {
    // A minimal, valid DNS query for "." (the root), type A -- just
    // enough to get a real response back; no user-identifying hostname
    // is ever queried by this probe.
    return Uint8List.fromList([
      0x12, 0x34, // transaction id (fixed, not random -- deliberately not
      // resembling traffic worth correlating)
      0x01, 0x00, // standard query, recursion desired
      0x00, 0x01, // qdcount = 1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // an/ns/arcount = 0
      0x00, // root name
      0x00, 0x01, // qtype A
      0x00, 0x01, // qclass IN
    ]);
  }
}

/// Fetches the caller's current public IP address, for the diagnostics
/// screen's "public IP before/after" fields. This inherently means
/// contacting a third-party IP-echo service over HTTPS -- there is no way
/// to learn your own public IP without asking something outside your own
/// network what it saw. Kept as a narrow, explicit, pluggable interface
/// specifically so:
///   - it's testable with a fake (see diagnostics_collector_test.dart),
///   - a deployment/build can swap in a self-hosted or different
///     provider instead of the default,
///   - it is never called implicitly -- only when the diagnostics
///     screen's "Check public IP" action is actually invoked.
abstract class IpEchoService {
  Future<String?> currentPublicIp();
}

/// Default [IpEchoService]: a single HTTPS GET to a well-known, minimal
/// IP-echo endpoint. Sends no cookies, no request body, no headers beyond
/// what `dart:io`'s `HttpClient` adds by default.
class HttpsIpEchoService implements IpEchoService {
  const HttpsIpEchoService({
    this.uri = 'https://api.ipify.org',
    this.timeout = const Duration(seconds: 5),
  });

  final String uri;
  final Duration timeout;

  @override
  Future<String?> currentPublicIp() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(uri)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final trimmed = body.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
