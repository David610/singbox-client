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

    test('secretRef round-trips through JSON as plain metadata', () {
      final original = ProxyConfig()
        ..tag = 'srv-1'
        ..secretRef = 'ref-abc-123';
      // No `raw` set here -- this is the post-migration on-disk shape:
      // only `secret_ref` persisted, the credential itself lives in
      // CredentialStore (see ServerManager._buildSecureServerConfigJson).

      final json = original.toJson();
      expect(json['secret_ref'], 'ref-abc-123');
      expect(json.containsKey('raw'), isFalse);

      final decoded = jsonDecode(jsonEncode(json));
      final restored = ProxyConfig()..fromJson(decoded);
      expect(restored.secretRef, 'ref-abc-123');
      expect(restored.raw, isNull);
    });

    test('toJson omits secret_ref when empty (no stale key on legacy '
        'plaintext profiles)', () {
      final original = ProxyConfig()
        ..tag = 'srv-1'
        ..raw = {'uuid': 'abc'};

      expect(original.toJson().containsKey('secret_ref'), isFalse);
    });

    test('clone carries secretRef so a migrated profile stays migrated '
        'after an in-app edit/duplicate', () {
      final original = ProxyConfig()
        ..tag = 'srv-1'
        ..secretRef = 'ref-1';

      final cloned = original.clone();
      expect(cloned.secretRef, 'ref-1');
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

      group.servers.add(
        ProxyConfig()
          ..tag = 'srv-1'
          ..type = 'vless'
          ..server = 'example.com'
          ..serverport = 443,
      );
      group.urltests.add(
        ProxyUrltest()
          ..remark = 'auto'
          ..tag = 'urltest-1'
          ..tags = ['srv-1'],
      );

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

    test('urlSecretRef round-trips through JSON as plain metadata, and '
        'a migrated group clears url_or_path from the on-disk shape', () {
      final original = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..urlOrPath = ''
        ..urlSecretRef = 'sub-ref-1';
      // Post-migration on-disk shape: the subscription URL/token lives in
      // CredentialStore, only the ref is in plain JSON.

      final json = original.toJson();
      expect(json['url_secret_ref'], 'sub-ref-1');
      expect(json['url_or_path'], '');

      final decoded = jsonDecode(jsonEncode(json));
      final restored = ServerConfigGroupItem()..fromJson(decoded);
      expect(restored.urlSecretRef, 'sub-ref-1');
      expect(restored.urlOrPath, '');
    });

    test('toJson omits url_secret_ref when empty (local file import, or '
        'not yet migrated)', () {
      final local = ServerConfigGroupItem()
        ..groupid = 'g1'
        ..urlOrPath = '/data/user/0/app/files/imported.json';
      expect(local.toJson().containsKey('url_secret_ref'), isFalse);
      expect(local.isRemote(), isFalse);
    });
  });

  group('FlutterVpnServiceState.fromCore', () {
    test('maps every VpnCoreState value to its matching Flutter state', () {
      expect(
        FlutterVpnServiceState.fromCore(VpnCoreState.invalid),
        FlutterVpnServiceState.invalid,
      );
      expect(
        FlutterVpnServiceState.fromCore(VpnCoreState.disconnected),
        FlutterVpnServiceState.disconnected,
      );
      expect(
        FlutterVpnServiceState.fromCore(VpnCoreState.connecting),
        FlutterVpnServiceState.connecting,
      );
      expect(
        FlutterVpnServiceState.fromCore(VpnCoreState.connected),
        FlutterVpnServiceState.connected,
      );
      expect(
        FlutterVpnServiceState.fromCore(VpnCoreState.reasserting),
        FlutterVpnServiceState.reasserting,
      );
      expect(
        FlutterVpnServiceState.fromCore(VpnCoreState.disconnecting),
        FlutterVpnServiceState.disconnecting,
      );
    });
  });
}
