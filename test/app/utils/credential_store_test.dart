import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/credential_store.dart';

class MemoryBackend implements CredentialBackend {
  final values = <String, String>{};
  bool failWrites = false;
  bool throwOnWrite = false;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<void> write(String key, String value) async {
    if (throwOnWrite) throw StateError('platform secure store unavailable');
    if (!failWrites) values[key] = value;
  }
}

Map<String, dynamic> profile(String id, String uuid, String password) => {
  'items': [
    {
      'groupid': id,
      'url_or_path': 'https://subscriptions.invalid/sub/$id-token',
      'servers': [
        {
          'tag': id,
          'raw': {
            'uuid': uuid,
            'password': password,
            'public_key': '$id-public-key',
          },
        },
      ],
    },
  ],
};

void main() {
  late Directory directory;
  late File file;
  late MemoryBackend backend;
  late ProfileCredentialStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('credential-store-');
    file = File('${directory.path}/subscribe.json');
    backend = MemoryBackend();
    store = ProfileCredentialStore(backend);
  });

  tearDown(() => directory.delete(recursive: true));

  test('migrates plaintext, verifies it, and survives restart', () async {
    final original = profile('one', 'uuid-one', 'password-one');
    await file.writeAsString(jsonEncode(original));

    expect(await store.readAndMigrate(file), original);
    final persisted = await file.readAsString();
    expect(persisted, isNot(contains('uuid-one')));
    expect(persisted, isNot(contains('password-one')));
    expect(persisted, isNot(contains('one-token')));
    expect(persisted, contains(ProfileCredentialStore.referencePrefix));

    final restarted = ProfileCredentialStore(backend);
    expect(await restarted.readAndMigrate(file), original);
  });

  test(
    'failed migration leaves the old configuration byte-for-byte usable',
    () async {
      final plaintext = jsonEncode(
        profile('one', 'uuid-one', 'password-one'),
      );
      await file.writeAsString(plaintext);
      backend.failWrites = true;

      expect(await store.readAndMigrate(file), jsonDecode(plaintext));
      expect(await file.readAsString(), plaintext);
    },
  );

  test('platform write exception also leaves plaintext usable', () async {
    final original = profile('one', 'uuid-one', 'password-one');
    final plaintext = jsonEncode(original);
    await file.writeAsString(plaintext);
    backend.throwOnWrite = true;

    expect(await store.readAndMigrate(file), original);
    expect(await file.readAsString(), plaintext);
  });

  test('missing and corrupted entries fail closed', () async {
    await store.write(file, profile('one', 'uuid-one', 'password-one'));
    final key = backend.values.keys.first;
    backend.values.remove(key);
    await expectLater(
      store.readAndMigrate(file),
      throwsA(isA<CredentialStoreException>()),
    );

    await store.write(file, profile('one', 'uuid-one', 'password-one'));
    backend.values[backend.values.keys.first] = 'corrupt';
    await expectLater(
      store.readAndMigrate(file),
      throwsA(isA<CredentialStoreException>()),
    );
  });

  test(
    'multiple profiles, rotation, replacement, and deletion reconcile secrets',
    () async {
      final two = {
        'items': [
          profile('one', 'uuid-one', 'password-one')['items'][0],
          profile('two', 'uuid-two', 'password-two')['items'][0],
        ],
      };
      await store.write(file, two);
      expect(await store.readAndMigrate(file), two);
      final initialCount = backend.values.length;

      final rotated = profile('one', 'uuid-rotated', 'password-rotated');
      await store.write(file, rotated);
      expect(await store.readAndMigrate(file), rotated);
      expect(backend.values.length, lessThan(initialCount));
      expect(await file.readAsString(), isNot(contains('rotated')));

      final replacement = profile('replacement', 'uuid-new', 'password-new');
      await store.write(file, replacement);
      expect(await store.readAndMigrate(file), replacement);

      await store.write(file, {'items': []});
      expect(backend.values, isEmpty);
    },
  );

  test('settings credentials use an isolated namespace', () async {
    final profileStore = ProfileCredentialStore(backend);
    final settingsStore = ProfileCredentialStore(
      backend,
      namespace: 'settings',
    );
    await profileStore.write(file, profile('one', 'uuid-one', 'password-one'));
    final settingsFile = File('${directory.path}/setting.json');
    final settings = {
      'webdav': {
        'url': 'https://dav.invalid',
        'user': 'alice',
        'password': 'dav-secret',
      },
      'socks_password': 'socks-secret',
    };
    await settingsStore.write(settingsFile, settings);
    expect(await settingsStore.readAndMigrate(settingsFile), settings);
    expect(await settingsFile.readAsString(), isNot(contains('dav-secret')));

    await profileStore.write(file, {'items': []});
    expect(backend.values.keys, everyElement(contains('.settings.')));
  });
}
