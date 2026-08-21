// Tests NetworkProbes against LOCAL servers this test spins up itself --
// deterministic and offline, no dependency on real internet
// reachability. A separate, explicitly network-tagged test
// (network_probes_live_test.dart) exercises the real default targets.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_core/vpn_core.dart';

void main() {
  group('tcp/ipv4/ipv6 probes', () {
    late ServerSocket server;
    late NetworkProbes probes;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      probes = NetworkProbes(
        timeout: const Duration(seconds: 2),
        ipv4ProbeHost: '127.0.0.1',
        probePort: server.port,
      );
    });

    tearDown(() => server.close());

    test('ipv4() passes against a real local listener', () async {
      server.listen((s) => s.destroy());
      final result = await probes.ipv4();
      expect(result.status, ProbeStatus.pass);
      expect(result.latency, isNotNull);
    });

    test('tcp() passes when given an explicit host/port', () async {
      server.listen((s) => s.destroy());
      final result = await probes.tcp(host: '127.0.0.1', port: server.port);
      expect(result.status, ProbeStatus.pass);
    });

    test('tcp()/ipv4() fail fast against a closed port', () async {
      final closedPortProbes = NetworkProbes(
        timeout: const Duration(milliseconds: 300),
        ipv4ProbeHost: '127.0.0.1',
        probePort: 1, // nothing listens here
      );
      final result = await closedPortProbes.ipv4();
      expect(result.status, ProbeStatus.fail);
      expect(result.detail, isNotNull);
    });

    test('never captures or exposes response payload content', () async {
      // The probe only proves connect succeeded -- it doesn't read/return
      // anything the "server" might send.
      server.listen((s) {
        s.add('unexpected payload the probe must never surface'.codeUnits);
        s.destroy();
      });
      final result = await probes.tcp(host: '127.0.0.1', port: server.port);
      expect(result.detail, isNot(contains('unexpected payload')));
    });
  });

  group('udp probe (DNS round trip)', () {
    test('passes against a minimal local UDP responder', () async {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) {
            // Echo back a plausible-length "DNS response".
            socket.send(List<int>.filled(20, 0), dg.address, dg.port);
          }
        }
      });
      addTearDown(socket.close);

      final probes = NetworkProbes(
        timeout: const Duration(seconds: 2),
        dnsProbeHost: '127.0.0.1',
        dnsPort: socket.port,
      );
      final result = await probes.udp();
      expect(result.status, ProbeStatus.pass);
    });

    test('fails (times out) when nothing responds', () async {
      final probes = NetworkProbes(
        timeout: const Duration(milliseconds: 300),
        dnsProbeHost: '127.0.0.1',
        dnsPort: 1, // nothing listens here
      );
      final result = await probes.udp();
      expect(result.status, ProbeStatus.fail);
    });
  });

  group('dns probe', () {
    test(
      'passes resolving a literal IP address (no real DNS needed)',
      () async {
        const probes = NetworkProbes();
        final result = await probes.dns(hostname: '127.0.0.1');
        expect(result.status, ProbeStatus.pass);
      },
    );
  });

  group('quicHeuristic probe', () {
    test(
      'reports pass with an explicit "heuristic only" detail, not a confirmed handshake',
      () async {
        final probes = NetworkProbes(
          timeout: const Duration(milliseconds: 200),
          quicProbeHost: '127.0.0.1',
          probePort: 40125,
        );
        final result = await probes.quicHeuristic();
        // A UDP send with nothing actively refusing it (no ICMP handling in
        // this sandbox) is expected to report pass -- the important
        // assertion is that it is labeled a heuristic, never claimed as a
        // confirmed QUIC handshake.
        expect(result.detail, contains('heuristic only'));
      },
    );
  });
}
