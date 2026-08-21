// Shared helpers for the real protocol interop tests
// (reality_interop_test.dart, hysteria2_interop_test.dart). Mirrors the
// approach of singbox-vpn's own `crates/compat-config/tests/common/mod.rs`:
// a real pinned sing-box binary as both client and server over loopback,
// a LOCAL TLS 1.3 decoy (never a third-party host, to avoid the exact CI
// flake singbox-vpn's own comments describe), and raw-socket SOCKS5
// TCP/UDP drivers so proving "bytes actually flow" needs no extra
// dependency.
//
// IMPORTANT SCOPE NOTE (see docs/SINGBOX_VPN_COMPATIBILITY.md): this
// exercises the sing-box CORE and the exact JSON vpn_core's config
// builder generates, via a `mixed` (SOCKS5) inbound instead of a real
// `tun` device. It does NOT exercise android.net.VpnService or
// NEPacketTunnelProvider, and a pass here must never be reported as
// "the mobile app works" -- only "the generated config + pinned core
// interoperate with a real singbox-vpn-shaped server."
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Locates a real sing-box binary: `SING_BOX_BIN` env var if set, else
/// `sing-box` on PATH. Returns null (never throws) if neither resolves,
/// so a machine without the binary skips these tests instead of failing
/// them -- matching singbox-vpn's own documented policy. CI is expected to
/// set `SING_BOX_BIN` (or otherwise ensure `sing-box` is on PATH) and,
/// per the same policy this project's server repo uses, treat a skip here
/// as a hard failure via its own required-interop gate.
Future<String?> findSingBoxBinary() async {
  final envPath = Platform.environment['SING_BOX_BIN'];
  if (envPath != null && await File(envPath).exists()) return envPath;
  try {
    final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
      'sing-box',
    ]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).split('\n').first.trim();
      if (path.isNotEmpty) return path;
    }
  } catch (_) {
    // `which`/`where` not available -- fall through to null.
  }
  return null;
}

/// Matching singbox-vpn's own `VPN1_REQUIRE_REAL_INTEROP=1` precedent
/// (see docs/SINGBOX_VPN_COMPATIBILITY.md): when
/// `VPN_CORE_REQUIRE_REAL_INTEROP=1` is set (as CI does -- see
/// .github/workflows/singbox-vpn-compat.yml), a missing sing-box binary
/// or openssl is a hard failure, not a silent skip. Call this from each
/// interop test file's `setUpAll` after resolving availability.
void requireRealInteropIfDemanded({
  required bool available,
  required String what,
}) {
  if (!available &&
      Platform.environment['VPN_CORE_REQUIRE_REAL_INTEROP'] == '1') {
    throw StateError(
      'VPN_CORE_REQUIRE_REAL_INTEROP=1 but $what is not available -- '
      'refusing to silently skip real protocol interop tests.',
    );
  }
}

bool opensslAvailable = false;

Future<bool> findOpenssl() async {
  try {
    final result = await Process.run('openssl', ['version']);
    opensslAvailable = result.exitCode == 0;
  } catch (_) {
    opensslAvailable = false;
  }
  return opensslAvailable;
}

class LocalDecoy {
  LocalDecoy(this.process, this.port, this.certPath, this.keyPath);
  final Process process;
  final int port;
  final String certPath;
  final String keyPath;

  /// Every current sing-box REALITY implementation requires the decoy's
  /// SNI to be a real hostname (not an IP literal) -- see
  /// singbox-vpn's own `tests/common/mod.rs` doc comment, which this
  /// mirrors.
  static const hostname = 'localhost';

  void stop() => process.kill();
}

/// Spawns a local TLS 1.3 server (`openssl s_server`) on `localhost` to
/// serve as the REALITY handshake decoy. Self-signed; `openssl` chooses
/// TLS 1.3 + an X25519 key share + a compliant middlebox-compat
/// ChangeCipherSpec by default, which is exactly what a real REALITY
/// client's handshake with the decoy needs to see.
Future<LocalDecoy> spawnLocalTls13Decoy(Directory workDir) async {
  final certPath = '${workDir.path}/decoy.crt';
  final keyPath = '${workDir.path}/decoy.key';
  final keygen = await Process.run('openssl', [
    'req',
    '-x509',
    '-newkey',
    'ec',
    '-pkeyopt',
    'ec_paramgen_curve:prime256v1',
    '-keyout',
    keyPath,
    '-out',
    certPath,
    '-days',
    '3',
    '-nodes',
    '-subj',
    '/CN=localhost',
    '-addext',
    'subjectAltName=DNS:localhost',
  ]);
  if (keygen.exitCode != 0) {
    throw StateError('openssl req failed: ${keygen.stderr}');
  }
  final port = await _freePort();
  final process = await Process.start('openssl', [
    's_server',
    '-tls1_3',
    '-accept',
    '$port',
    '-cert',
    certPath,
    '-key',
    keyPath,
    '-www',
    '-naccept',
    '100000',
  ]);
  await _waitForPortOpen(port);
  return LocalDecoy(process, port, certPath, keyPath);
}

class LocalHttpTarget {
  LocalHttpTarget(this.server, this.port);
  final HttpServer server;
  final int port;
  static const responseBody = 'hello from vpn_core interop test target';

  Future<void> stop() => server.close(force: true);
}

Future<LocalHttpTarget> spawnLocalHttpTarget() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) {
    request.response.write(LocalHttpTarget.responseBody);
    request.response.close();
  });
  return LocalHttpTarget(server, server.port);
}

class LocalUdpEcho {
  LocalUdpEcho(this.socket);
  final RawDatagramSocket socket;
  int get port => socket.port;

  void start() {
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) socket.send(dg.data, dg.address, dg.port);
      }
    });
  }

  void stop() => socket.close();
}

Future<LocalUdpEcho> spawnLocalUdpEcho() async {
  final socket = await RawDatagramSocket.bind('127.0.0.1', 0);
  final echo = LocalUdpEcho(socket);
  echo.start();
  return echo;
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForPortOpen(int port, {int retries = 50}) async {
  for (var i = 0; i < retries; i++) {
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 200),
      );
      s.destroy();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('port $port never opened');
}

/// Runs `sing-box run -c configPath`, waits briefly for it to either start
/// listening or exit, and returns the process. Caller is responsible for
/// killing it.
Future<Process> runSingBox(String binary, String configPath) async {
  final process = await Process.start(binary, ['run', '-c', configPath]);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return process;
}

/// Runs `sing-box check -c configPath`; throws with stderr on failure.
Future<void> checkSingBoxConfig(String binary, String configPath) async {
  final result = await Process.run(binary, ['check', '-c', configPath]);
  if (result.exitCode != 0) {
    throw StateError('sing-box check failed: ${result.stderr}');
  }
}

/// Performs a SOCKS5 (no-auth) CONNECT to (host, port) through
/// 127.0.0.1:socksPort, sends a plain HTTP GET, and returns the full
/// response text, or null on any failure (connection refused, SOCKS
/// rejection, timeout) -- a null return from a *_interop_test.dart test is
/// what a rejected/broken tunnel looks like, used directly in the
/// negative-control tests.
Future<String?> socks5HttpGet(
  int socksPort,
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  Socket socket;
  try {
    socket = await Socket.connect('127.0.0.1', socksPort, timeout: timeout);
  } catch (_) {
    return null;
  }
  try {
    final responses = StreamController<Uint8List>();
    socket.listen(
      (data) => responses.add(Uint8List.fromList(data)),
      onError: (_) {},
      cancelOnError: true,
    );
    final reader = _ByteReader(responses.stream);

    socket.add([0x05, 0x01, 0x00]);
    final greet = await reader.readExact(2, timeout);
    if (greet == null || greet[0] != 0x05 || greet[1] != 0x00) return null;

    final hostBytes = utf8.encode(host);
    socket.add([
      0x05,
      0x01,
      0x00,
      0x03,
      hostBytes.length,
      ...hostBytes,
      (port >> 8) & 0xff,
      port & 0xff,
    ]);
    final replyHead = await reader.readExact(4, timeout);
    if (replyHead == null || replyHead[1] != 0x00) return null;
    final atyp = replyHead[3];
    final addrLen = switch (atyp) {
      1 => 4,
      4 => 16,
      3 => (await reader.readExact(1, timeout))?[0] ?? -1,
      _ => -1,
    };
    if (addrLen < 0) return null;
    if (await reader.readExact(addrLen + 2, timeout) == null) return null;

    socket.add(
      utf8.encode('GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n'),
    );
    final body = await reader.readUntilClose(timeout);
    return body == null ? null : utf8.decode(body, allowMalformed: true);
  } finally {
    socket.destroy();
  }
}

/// Performs a SOCKS5 UDP ASSOCIATE through 127.0.0.1:socksPort, sends
/// `payload` to (targetHost, targetPort) via the relay, and returns
/// whatever comes back (expected: an echo of `payload`, when driven
/// against [spawnLocalUdpEcho]), or null on any failure.
Future<Uint8List?> socks5UdpEcho(
  int socksPort,
  String targetHost,
  int targetPort,
  Uint8List payload, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  Socket tcp;
  try {
    tcp = await Socket.connect('127.0.0.1', socksPort, timeout: timeout);
  } catch (_) {
    return null;
  }
  RawDatagramSocket? udp;
  try {
    final responses = StreamController<Uint8List>();
    tcp.listen(
      (d) => responses.add(Uint8List.fromList(d)),
      onError: (_) {},
      cancelOnError: true,
    );
    final reader = _ByteReader(responses.stream);

    tcp.add([0x05, 0x01, 0x00]);
    final greet = await reader.readExact(2, timeout);
    if (greet == null || greet[0] != 0x05 || greet[1] != 0x00) return null;

    // UDP ASSOCIATE, bind addr/port 0.0.0.0:0.
    tcp.add([0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    final reply = await reader.readExact(10, timeout);
    if (reply == null || reply[1] != 0x00) return null;
    var relayIp = '${reply[4]}.${reply[5]}.${reply[6]}.${reply[7]}';
    if (relayIp == '0.0.0.0') relayIp = '127.0.0.1';
    final relayPort = (reply[8] << 8) | reply[9];

    udp = await RawDatagramSocket.bind('127.0.0.1', 0);
    final targetBytes = targetHost.split('.').map(int.parse).toList();
    final header = <int>[
      0,
      0,
      0,
      0x01,
      ...targetBytes,
      (targetPort >> 8) & 0xff,
      targetPort & 0xff,
      ...payload,
    ];
    udp.send(header, InternetAddress(relayIp), relayPort);

    final completer = Completer<Uint8List?>();
    late final StreamSubscription sub;
    sub = udp.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = udp!.receive();
        if (dg != null && !completer.isCompleted) {
          completer.complete(dg.data.sublist(10));
        }
      }
    });
    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  } catch (_) {
    return null;
  } finally {
    udp?.close();
    tcp.destroy();
  }
}

class _ByteReader {
  _ByteReader(Stream<Uint8List> stream) {
    _sub = stream.listen(
      (d) {
        _buffer.addAll(d);
        _tryDeliver();
      },
      onDone: () {
        _closed = true;
        _tryDeliver();
      },
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final List<int> _buffer = [];
  bool _closed = false;
  Completer<void>? _waiter;

  void _tryDeliver() {
    _waiter?.complete();
    _waiter = null;
  }

  Future<Uint8List?> readExact(int n, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < n) {
      if (_closed) return null;
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) return null;
      _waiter = Completer<void>();
      await _waiter!.future.timeout(remaining, onTimeout: () {});
    }
    final out = Uint8List.fromList(_buffer.take(n).toList());
    _buffer.removeRange(0, n);
    return out;
  }

  Future<Uint8List?> readUntilClose(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!_closed) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) break;
      _waiter = Completer<void>();
      await _waiter!.future.timeout(remaining, onTimeout: () {});
    }
    final out = Uint8List.fromList(_buffer);
    await _sub.cancel();
    return out;
  }
}
