// Tests for the P0 credential-storage migration in server_manager.dart:
// ServerManager.buildSecureServerConfigJsonFor (the save-time path that
// moves ProxyConfig.raw / a remote group's urlOrPath into CredentialStore)
// and ServerManager.hydrateSecureCredentialsFor (the load-time path that
// reads them back). These are `@visibleForTesting` wrappers around the
// exact same logic `saveServerConfig`/`loadServerConfig` use in production
// (parameterized on an explicit ServerConfig instead of the module's
// static `_serverConfig`), which keeps this test free of any dependency on
// PathUtils/path_provider/real file I/O while still exercising the real
// migration/hydration code, not a reimplementation of it.
//
// Covers the specific scenarios called out in the P0 work item: migration,
// restart-after-migration (save then a fresh load), missing secret,
// corrupted secure-store entry, profile deletion, profile replacement,
// credential rotation, multiple profiles, and "no secret written back to
// plaintext persistence."
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/utils/credential_store.dart';

class _FakeBackend implements SecureKeyValueBackend {
  final Map<String, String> store = {};
  bool throwOnWrite = false;
  final Set<String> corruptReadsFor = {};

  @override
  Future<void> write(String key, String value) async {
    if (throwOnWrite) throw StateError('secure storage write failed');
    store[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    if (corruptReadsFor.contains(key)) return 'CORRUPTED';
    return store[key];
  }

  @override
  Future<void> delete(String key) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(store);
}

ServerConfigGroupItem _remoteGroup({
  required String groupid,
  required String url,
  required List<ProxyConfig> servers,
}) {
  final group = ServerConfigGroupItem()
    ..groupid = groupid
    ..urlOrPath = url;
  group.servers.addAll(servers);
  return group;
}

ProxyConfig _server(String tag, Map<String, dynamic> raw) => ProxyConfig()
  ..tag = tag
  ..type = raw['type'] as String? ?? 'vless'
  ..raw = raw;

void main() {
  late _FakeBackend backend;

  setUp(() {
    backend = _FakeBackend();
    CredentialStore.debugOverrideBackend(backend);
  });

  tearDown(() {
    CredentialStore.debugResetBackend();
  });

  test('migration: raw and the remote URL are removed from the saved JSON '
      'and moved into secure storage', () async {
    final config = ServerConfig()
      ..items.add(
        _remoteGroup(
          groupid: 'g1',
          url: 'https://sub.example.com/link?token=SECRET_TOKEN_1',
          servers: [
            _server('srv-1', {
              'type': 'vless',
              'uuid': 'SECRET_UUID_1',
              'tls': {
                'reality': {'public_key': 'SECRET_PBK_1'},
              },
            }),
          ],
        ),
      );

    final json = await ServerManager.buildSecureServerConfigJsonFor(config);
    final encoded = jsonEncode(json);

    expect(encoded, isNot(contains('SECRET_UUID_1')));
    expect(encoded, isNot(contains('SECRET_PBK_1')));
    expect(encoded, isNot(contains('SECRET_TOKEN_1')));

    final groupJson = (json['items'] as List).single as Map<String, dynamic>;
    expect(groupJson['url_or_path'], '');
    expect(groupJson['url_secret_ref'], isNotEmpty);

    final serverJson =
        (groupJson['servers'] as List).single as Map<String, dynamic>;
    expect(serverJson.containsKey('raw'), isFalse);
    expect(serverJson['secret_ref'], isNotEmpty);

    // The live in-memory objects (not just the returned JSON) keep the
    // refs, and keep raw/urlOrPath populated for immediate use.
    expect(config.items.single.urlSecretRef, isNotEmpty);
    expect(config.items.single.urlOrPath, isNotEmpty);
    expect(config.items.single.servers.single.secretRef, isNotEmpty);
    expect(config.items.single.servers.single.raw, isNotNull);
  });

  test('restart after migration: hydrating a fresh ServerConfig built '
      'from the saved (secret-stripped) JSON restores raw/urlOrPath', () async {
    final original = ServerConfig()
      ..items.add(
        _remoteGroup(
          groupid: 'g1',
          url: 'https://sub.example.com/link?token=SECRET_TOKEN_1',
          servers: [
            _server('srv-1', {'type': 'vless', 'uuid': 'SECRET_UUID_1'}),
          ],
        ),
      );
    final json = await ServerManager.buildSecureServerConfigJsonFor(original);

    // Simulate "restart": decode the saved JSON (as loadServerConfig()
    // does from subscribe.json) into a brand-new ServerConfig, then
    // hydrate it the way loadServerConfig() does.
    // ServerConfig.fromJson always inserts an empty custom group when the
    // persisted document has none, so select the migrated group by id.
    final reloaded = ServerConfig()..fromJson(jsonDecode(jsonEncode(json)));
    final restored = reloaded.items
        .where((item) => item.groupid == 'g1')
        .single;
    expect(restored.servers.single.raw, isNull);
    expect(restored.urlOrPath, '');

    await ServerManager.hydrateSecureCredentialsFor(reloaded);

    expect(restored.servers.single.raw, {
      'type': 'vless',
      'uuid': 'SECRET_UUID_1',
    });
    expect(
      restored.urlOrPath,
      'https://sub.example.com/link?token=SECRET_TOKEN_1',
    );
  });

  test('migration is idempotent: saving twice reuses the same secret_ref '
      'instead of allocating a new one each time', () async {
    final config = ServerConfig()
      ..items.add(
        _remoteGroup(
          groupid: 'g1',
          url: 'https://sub.example.com/a',
          servers: [
            _server('srv-1', {'type': 'vless', 'uuid': 'u1'}),
          ],
        ),
      );

    await ServerManager.buildSecureServerConfigJsonFor(config);
    final firstServerRef = config.items.single.servers.single.secretRef;
    final firstUrlRef = config.items.single.urlSecretRef;

    await ServerManager.buildSecureServerConfigJsonFor(config);
    expect(config.items.single.servers.single.secretRef, firstServerRef);
    expect(config.items.single.urlSecretRef, firstUrlRef);
  });

  test(
    'missing secret: a ref with nothing in secure storage leaves raw '
    'null (fails closed) instead of throwing or fabricating a value',
    () async {
      final config = ServerConfig()
        ..items.add(
          ServerConfigGroupItem()
            ..groupid = 'g1'
            ..servers.add(
              ProxyConfig()
                ..tag = 'srv-1'
                ..secretRef = 'ghost-ref',
            ),
        );

      await ServerManager.hydrateSecureCredentialsFor(config);
      expect(config.items.single.servers.single.raw, isNull);
    },
  );

  test('corrupted secure-store entry: an unparsable value leaves raw null '
      'rather than crashing or being used as-is', () async {
    await CredentialStore.writeServerSecret('ref-1', 'not valid json{{{');
    final config = ServerConfig()
      ..items.add(
        ServerConfigGroupItem()
          ..groupid = 'g1'
          ..servers.add(
            ProxyConfig()
              ..tag = 'srv-1'
              ..secretRef = 'ref-1',
          ),
      );

    await expectLater(
      ServerManager.hydrateSecureCredentialsFor(config),
      completes,
    );
    expect(config.items.single.servers.single.raw, isNull);
  });

  test('profile deletion: removing a server from the live config and '
      'saving prunes its orphaned secret from secure storage', () async {
    final config = ServerConfig()
      ..items.add(
        _remoteGroup(
          groupid: 'g1',
          url: '',
          servers: [
            _server('srv-1', {'type': 'vless', 'uuid': 'u1'}),
            _server('srv-2', {'type': 'vless', 'uuid': 'u2'}),
          ],
        ),
      );
    await ServerManager.buildSecureServerConfigJsonFor(config);
    final ref1 = config.items.single.servers[0].secretRef;
    final ref2 = config.items.single.servers[1].secretRef;
    expect(await CredentialStore.readServerSecret(ref1), isNotNull);
    expect(await CredentialStore.readServerSecret(ref2), isNotNull);

    config.items.single.servers.removeAt(0);
    await ServerManager.buildSecureServerConfigJsonFor(config);

    expect(await CredentialStore.readServerSecret(ref1), isNull);
    expect(await CredentialStore.readServerSecret(ref2), isNotNull);
  });

  test('profile replacement (subscription refresh): swapping a group\'s '
      'servers for a new list prunes the old credentials', () async {
    final config = ServerConfig()
      ..items.add(
        _remoteGroup(
          groupid: 'g1',
          url: '',
          servers: [
            _server('old', {'type': 'vless', 'uuid': 'old-uuid'}),
          ],
        ),
      );
    await ServerManager.buildSecureServerConfigJsonFor(config);
    final oldRef = config.items.single.servers.single.secretRef;

    config.items.single.servers
      ..clear()
      ..add(_server('new', {'type': 'vless', 'uuid': 'new-uuid'}));
    await ServerManager.buildSecureServerConfigJsonFor(config);
    final newRef = config.items.single.servers.single.secretRef;

    expect(newRef, isNot(oldRef));
    expect(await CredentialStore.readServerSecret(oldRef), isNull);
    expect(await CredentialStore.readServerSecret(newRef), isNotNull);
  });

  test('credential rotation: re-saving a server whose raw changed keeps '
      'the same ref but updates the stored value', () async {
    final server = _server('srv-1', {'type': 'vless', 'uuid': 'uuid-v1'});
    final config = ServerConfig()
      ..items.add(
        ServerConfigGroupItem()
          ..groupid = 'g1'
          ..servers.add(server),
      );
    await ServerManager.buildSecureServerConfigJsonFor(config);
    final ref = server.secretRef;

    server.raw = {'type': 'vless', 'uuid': 'uuid-v2-rotated'};
    await ServerManager.buildSecureServerConfigJsonFor(config);

    expect(server.secretRef, ref); // same key, rotated in place
    final stored = await CredentialStore.readServerSecret(ref);
    expect(stored, contains('uuid-v2-rotated'));
    expect(stored, isNot(contains('uuid-v1')));
  });

  test('multiple profiles: each server/group gets its own independent '
      'ref and secret', () async {
    final config = ServerConfig()
      ..items.addAll([
        _remoteGroup(
          groupid: 'g1',
          url: 'https://sub.example.com/one',
          servers: [
            _server('a', {'type': 'vless', 'uuid': 'ua'}),
          ],
        ),
        _remoteGroup(
          groupid: 'g2',
          url: 'https://sub.example.com/two',
          servers: [
            _server('b', {'type': 'hysteria2', 'password': 'pb'}),
          ],
        ),
      ]);

    await ServerManager.buildSecureServerConfigJsonFor(config);

    final refs = {
      config.items[0].servers.single.secretRef,
      config.items[1].servers.single.secretRef,
      config.items[0].urlSecretRef,
      config.items[1].urlSecretRef,
    };
    expect(refs, hasLength(4)); // all distinct, nothing collided
  });

  test('no secret written back to plaintext persistence: a save after a '
      'failed migration keeps the old plaintext copy rather than losing '
      'it, but a save that succeeds never leaves raw in the JSON', () async {
    backend.throwOnWrite = true;
    final config = ServerConfig()
      ..items.add(
        ServerConfigGroupItem()
          ..groupid = 'g1'
          ..servers.add(_server('srv-1', {'type': 'vless', 'uuid': 'u1'})),
      );

    final failedJson = await ServerManager.buildSecureServerConfigJsonFor(
      config,
    );
    final failedServerJson =
        ((failedJson['items'] as List).single
                as Map<String, dynamic>)['servers']
            as List;
    // Fail-safe: migration failed, so the plaintext copy is preserved
    // rather than the credential being silently dropped.
    expect((failedServerJson.single as Map)['raw'], isNotNull);

    backend.throwOnWrite = false;
    final okJson = await ServerManager.buildSecureServerConfigJsonFor(config);
    final okServerJson =
        ((okJson['items'] as List).single as Map<String, dynamic>)['servers']
            as List;
    expect((okServerJson.single as Map).containsKey('raw'), isFalse);
  });
}
