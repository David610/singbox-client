// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:karing/app/runtime/return_result.dart';
import 'package:tuple/tuple.dart';

class NetInterfacesInfo {
  NetInterfacesInfo({
    required this.name,
    required this.address,
    required this.type,
  });

  String name;
  String address;
  InternetAddressType type;
}

class OutletIpInfo {
  OutletIpInfo({required this.ip, this.countryCode = ''});
  String ip;
  String countryCode;
}

class NetworkUtils {
  NetworkUtils._();

  static final RegExp _ipv4Reg = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  static final RegExp _ipv4WithMaskReg = RegExp(
    r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$',
  );

  static bool isIpv4(String value) => _ipv4Reg.hasMatch(value);
  static bool isIpv4WithMask(String value) => _ipv4WithMaskReg.hasMatch(value);

  static bool isIpv6(String value) {
    try {
      Uri.parseIPv6Address(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool isIpv6WithMask(String value) {
    final parts = value.split('/');
    if (parts.length != 2) {
      return false;
    }
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 128) {
      return false;
    }
    return isIpv6(parts[0]);
  }

  static bool isDomain(String value) {
    if (isIpv4(value) || isIpv6(value)) {
      return false;
    }
    return RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$',
    ).hasMatch(value);
  }

  static String? getRealDomain(String domain) {
    final trimmed = domain.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    var host = trimmed;
    if (host.contains('://')) {
      host = Uri.tryParse(host)?.host ?? host;
    }
    return host.isEmpty ? null : host;
  }

  static Future<List<String>> dnsLookup(String domain, bool preferIPv4) async {
    try {
      final result = await InternetAddress.lookup(
        domain,
        type: preferIPv4 ? InternetAddressType.IPv4 : InternetAddressType.any,
      );
      return result.map((e) => e.address).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<ReturnResult<int>> testConnectLatency(
    String host,
    int port,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      socket.destroy();
      return ReturnResult(data: stopwatch.elapsedMilliseconds);
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<int> getAvaliablePort(List<int> preferred) async {
    for (final p in preferred) {
      if (p <= 0) {
        continue;
      }
      try {
        final socket = await ServerSocket.bind(InternetAddress.anyIPv4, p);
        final port = socket.port;
        await socket.close();
        return port;
      } catch (_) {
        continue;
      }
    }
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> getAvaliablePortNotCloseSocket(List<int> preferred) async {
    return getAvaliablePort(preferred);
  }

  static Future<List<NetInterfacesInfo>> getInterfaces() async {
    final result = <NetInterfacesInfo>[];
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          result.add(
            NetInterfacesInfo(
              name: iface.name,
              address: addr.address,
              type: addr.type,
            ),
          );
        }
      }
    } catch (_) {}
    return result;
  }

  static Future<Tuple2<OutletIpInfo?, String?>> getOutletIp(
    int localPort,
  ) async {
    return const Tuple2(null, null);
  }
}
