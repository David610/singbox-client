import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/vpn_service_state.dart';
import 'package:vpn_core/vpn_core.dart';

void main() {
  group('ProxyConfig', () {
    test('JSON round-trip preserves all fields', () {
      final original = ProxyConfig()
        ..index = 3
        ..groupid = 'g1'
        ..tag = 'srv-1'
        ..remark = 'My Server'
        ..type = 'vless'
        ..server = 'example.com'
        ..serverport = 443
        ..latency = '120ms'
        ..outletip = '1.2.3.4'
        ..outletregion = 'US'
        ..attach = 'extra'
        ..raw = {'uuid': 'abc-123', 'flow': 'xtls-rprx-vision'};

      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored = ProxyConfig()..fromJson(decoded);

      expect(restored.groupid, 'g1');
      expect(restored.tag, 'srv-1');
      expect(restored.remark, 'My Server');
      expect(restored.type, 'vless');
      expect(restored.server, 'example.com');
      expect(restored.serverport, 443);
      expect(restored.outletip, '1.2.3.4');
      expect(restored.outletregion, 'US');
      expect(restored.attach, 'extra');
      expect(restored.raw, {'uuid': 'abc-123', 'flow': 'xtls-rprx-vision'});
    });

    test('fromJson applies safe defaults for missing old-schema fields', () {
      final restored = ProxyConfig()..fromJson({'tag': 'legacy'});

      expect(restored.tag, 'legacy');
      expect(restored.groupid, '');
      expect(restored.remark, '');
      expect(restored.type, '');
      expect(restored.server, '');
      expect(restored.serverport, 0);
      expect(restored.outletip, '');
      expect(restored.outletregion, '');
      expect(restored.attach, '');
      expect(restored.raw, isNull);
    });

    test('clone produces an equal but independent copy', () {
      final original = ProxyConfig()
        ..tag = 'srv-1'
        ..server = 'example.com'
        ..raw = {'k': 'v'};

      final cloned = original.clone();

      expect(cloned.tag, original.tag);
      expect(cloned.server, original.server);
      expect(cloned.raw, original.raw);

      cloned.tag = 'srv-2';
      cloned.raw!['k'] = 'changed';

      expect(original.tag, 'srv-1');
      expect(original.raw!['k'], 'v');
    });
  });

  group('ServerConfigGroupItem', () {
    test('JSON round-trip preserves servers, urltests and metadata', () {
      final group = ServerConfigGroupItem()
        ..groupid = 'group-1'
        ..remark = 'My Group'
        ..enable = true
        ..type = SubscriptionLinkType.v2ray
        ..urlOrPath = 'https://example.com/sub'
        ..site = 'https://example.com'
        ..userAgentAppend = true
        ..userAgentCompatibles = ['clash', 'shadowrocket']
        ..xhwid = true
        ..proxyFilterRemove = ['tag-a']
        ..keepDiversionRules = false
        ..proxyStrategy = ProxyStrategy.onlyDirect
        ..isp = (SubscriptionISP()
          ..id = 'isp-1'
          ..user = 'user-1')
        ..traffic = (SubscriptionTraffic()
          ..upload = 100
          ..download = 200
          ..total = 1000)
        ..updateTime = '2026-01-01T00:00:00Z';

      group.servers.add(ProxyConfig()
        ..tag = 'srv-1'
        ..type = 'vless'
        ..server = 'example.com'
        ..serverport = 443);
      group.urltests.add(ProxyUrltest()
        ..remark = 'auto'
        ..tag = 'urltest-1'
        ..tags = ['srv-1']);

      final decoded = jsonDecode(jsonEncode(group.toJson()));
      final restored = ServerConfigGroupItem()..fromJson(decoded);

      expect(restored.groupid, 'group-1');
      expect(restored.remark, 'My Group');
      expect(restored.type, SubscriptionLinkType.v2ray);
      expect(restored.userAgentAppend, true);
      expect(restored.userAgentCompatibles, ['clash', 'shadowrocket']);
      expect(restored.xhwid, true);
      expect(restored.proxyFilterRemove, ['tag-a']);
      expect(restored.keepDiversionRules, false);
      expect(restored.proxyStrategy, ProxyStrategy.onlyDirect);
      expect(restored.isp?.id, 'isp-1');
      expect(restored.traffic?.upload, 100);

      expect(restored.servers, hasLength(1));
      expect(restored.servers.single.tag, 'srv-1');
      expect(restored.servers.single.server, 'example.com');

      expect(restored.urltests, hasLength(1));
      expect(restored.urltests.single.tag, 'urltest-1');
      expect(restored.urltests.single.tags, ['srv-1']);
    });

    test('fromJson applies safe defaults for missing old-schema fields', () {
      final restored = ServerConfigGroupItem()..fromJson({'groupid': 'g'});

      expect(restored.groupid, 'g');
      expect(restored.enable, true);
      expect(restored.servers, isEmpty);
      expect(restored.urltests, isEmpty);
      expect(restored.userAgentAppend, false);
      expect(restored.xhwid, false);
      expect(restored.isp, isNull);
      expect(restored.traffic, isNull);
      expect(restored.type, SubscriptionLinkType.unknown);
    });

    test('clone (used by ServerManager) deep-copies servers by default', () {
      final group = ServerConfigGroupItem()..groupid = 'g1';
      group.servers.add(ProxyConfig()..tag = 'srv-1');

      final cloned = group.clone();
      cloned.servers.single.tag = 'changed';
      cloned.groupid = 'g2';

      expect(group.servers.single.tag, 'srv-1');
      expect(group.groupid, 'g1');
      expect(cloned.servers.single.tag, 'changed');
    });

    test('clone(includeServers: false) drops servers, keeps metadata', () {
      final group = ServerConfigGroupItem()..groupid = 'g1';
      group.servers.add(ProxyConfig()..tag = 'srv-1');

      final cloned = group.clone(includeServers: false);

      expect(cloned.groupid, 'g1');
      expect(cloned.servers, isEmpty);
      expect(group.servers, hasLength(1));
    });
  });

  group('FlutterVpnServiceState.fromCore', () {
    test('maps every VpnCoreState value to its matching Flutter state', () {
      expect(FlutterVpnServiceState.fromCore(VpnCoreState.invalid),
          FlutterVpnServiceState.invalid);
      expect(FlutterVpnServiceState.fromCore(VpnCoreState.disconnected),
          FlutterVpnServiceState.disconnected);
      expect(FlutterVpnServiceState.fromCore(VpnCoreState.connecting),
          FlutterVpnServiceState.connecting);
      expect(FlutterVpnServiceState.fromCore(VpnCoreState.connected),
          FlutterVpnServiceState.connected);
      expect(FlutterVpnServiceState.fromCore(VpnCoreState.reasserting),
          FlutterVpnServiceState.reasserting);
      expect(FlutterVpnServiceState.fromCore(VpnCoreState.disconnecting),
          FlutterVpnServiceState.disconnecting);
    });
  });
}
