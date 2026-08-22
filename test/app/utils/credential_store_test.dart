// Unit tests for CredentialStore, the Android Keystore / iOS Keychain
// wrapper the P0 credential-storage work item added
// (lib/app/utils/credential_store.dart). Exercises the contract every
// caller (ServerManager's migration logic) relies on: write/read/delete,
// write-then-verify (the primitive the migration path uses to decide
// whether it's safe to delete a plaintext copy), and pruning of orphaned
// entries left behind by deleted/replaced profiles.
//
// Uses an in-memory `SecureKeyValueBackend` fake instead of the real
// `flutter_secure_storage` plugin, which has no platform-channel mock
// available under plain `flutter test` (no device/emulator). This tests
// CredentialStore's own logic (prefixing, verify semantics, pruning,
// failure handling) -- it intentionally does not and cannot prove the real
// Android Keystore / iOS Keychain backend behaves the same way; that is a
// real-device concern, not a unit-test one.
import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/credential_store.dart';

/// In-memory fake backend. `throwOnWrite`/`throwOnRead`/`corruptReadsFor`
/// let individual tests simulate a secure-store failure or a corrupted
/// entry without touching a real platform channel.
class _FakeBackend implements SecureKeyValueBackend {
  final Map<String, String> store = {};
  bool throwOnWrite = false;
  bool throwOnRead = false;
  bool throwOnReadAll = false;
  final Set<String> corruptReadsFor = {};

  @override
  Future<void> write(String key, String value) async {
    if (throwOnWrite) throw StateError('secure storage write failed');
    store[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw StateError('secure storage read failed');
    if (corruptReadsFor.contains(key)) {
      // Simulate a corrupted entry: present, but not the value that was
      // written (bit rot, a partial write, a platform bug).
      return 'CORRUPTED-${store[key]}';
    }
    return store[key];
  }

  @override
  Future<void> delete(String key) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    if (throwOnReadAll) throw StateError('secure storage enumeration failed');
    return Map.of(store);
  }
}

void main() {
  late _FakeBackend backend;

  setUp(() {
    backend = _FakeBackend();
    CredentialStore.debugOverrideBackend(backend);
  });

  tearDown(() {
    CredentialStore.debugResetBackend();
  });

  group('server secrets', () {
    test('write then read round-trips the exact payload', () async {
      await CredentialStore.writeServerSecret('ref-1', '{"uuid":"abc"}');
      expect(await CredentialStore.readServerSecret('ref-1'), '{"uuid":"abc"}');
    });

    test('read of a never-written ref returns null (missing secret, not '
        'an exception)', () async {
      expect(await CredentialStore.readServerSecret('never-written'), isNull);
    });

    test('delete removes the entry', () async {
      await CredentialStore.writeServerSecret('ref-1', 'payload');
      await CredentialStore.deleteServerSecret('ref-1');
      expect(await CredentialStore.readServerSecret('ref-1'), isNull);
    });

    test('rotation: writing a new payload under the same ref replaces the '
        'old one (credential rotation without allocating a new key)', () async {
      await CredentialStore.writeServerSecret('ref-1', '{"uuid":"old"}');
      await CredentialStore.writeServerSecret('ref-1', '{"uuid":"new"}');
      expect(await CredentialStore.readServerSecret('ref-1'), '{"uuid":"new"}');
    });

    test('multiple profiles keep independent secrets under their own '
        'refs', () async {
      await CredentialStore.writeServerSecret('ref-a', 'secret-a');
      await CredentialStore.writeServerSecret('ref-b', 'secret-b');
      expect(await CredentialStore.readServerSecret('ref-a'), 'secret-a');
      expect(await CredentialStore.readServerSecret('ref-b'), 'secret-b');
    });

    test('server secrets and subscription secrets never collide even with '
        'the same ref string (distinct key prefixes)', () async {
      await CredentialStore.writeServerSecret('shared-ref', 'server-value');
      await CredentialStore.writeSubscriptionSecret(
        'shared-ref',
        'https://example.com/sub?token=abc',
      );
      expect(
        await CredentialStore.readServerSecret('shared-ref'),
        'server-value',
      );
      expect(
        await CredentialStore.readSubscriptionSecret('shared-ref'),
        'https://example.com/sub?token=abc',
      );
    });
  });

  group('writeAndVerify', () {
    test('returns true and persists when the backend write+read succeed '
        'and match', () async {
      final ok = await CredentialStore.writeAndVerify(
        CredentialStore.serverSecretPrefix,
        'ref-1',
        'payload',
      );
      expect(ok, isTrue);
      expect(await CredentialStore.readServerSecret('ref-1'), 'payload');
    });

    test('returns false without throwing when the backend write throws '
        '(secure store unavailable)', () async {
      backend.throwOnWrite = true;
      final ok = await CredentialStore.writeAndVerify(
        CredentialStore.serverSecretPrefix,
        'ref-1',
        'payload',
      );
      expect(ok, isFalse);
    });

    test('returns false when the read-back does not match what was '
        'written (corrupted secure-store entry)', () async {
      // Simulate: write "succeeds" at the platform level but the
      // immediate read-back comes back altered.
      await backend.write(
        '${CredentialStore.serverSecretPrefix}ref-1',
        'payload',
      );
      backend.corruptReadsFor.add('${CredentialStore.serverSecretPrefix}ref-1');
      final ok = await CredentialStore.writeAndVerify(
        CredentialStore.serverSecretPrefix,
        'ref-1',
        'payload',
      );
      expect(ok, isFalse);
    });

    test('never throws even when the backend read throws', () async {
      backend.throwOnRead = true;
      expect(
        () async => CredentialStore.writeAndVerify(
          CredentialStore.serverSecretPrefix,
          'ref-1',
          'payload',
        ),
        returnsNormally,
      );
    });
  });

  group('pruneExcept', () {
    test('deletes only entries under the given prefix that are not in the '
        'active set (profile deletion / replacement)', () async {
      await CredentialStore.writeServerSecret('keep', 'a');
      await CredentialStore.writeServerSecret('orphan', 'b');
      await CredentialStore.writeSubscriptionSecret(
        'unrelated',
        'https://example.com',
      );

      await CredentialStore.pruneExcept(CredentialStore.serverSecretPrefix, {
        'keep',
      });

      expect(await CredentialStore.readServerSecret('keep'), 'a');
      expect(await CredentialStore.readServerSecret('orphan'), isNull);
      // A different prefix (subscription secrets) is untouched by pruning
      // the server-secret prefix.
      expect(
        await CredentialStore.readSubscriptionSecret('unrelated'),
        'https://example.com',
      );
    });

    test(
      'is a no-op (does not throw) when the backend enumeration fails',
      () async {
        await CredentialStore.writeServerSecret('ref-1', 'a');
        backend.throwOnReadAll = true;
        await expectLater(
          CredentialStore.pruneExcept(CredentialStore.serverSecretPrefix, {}),
          completes,
        );
        // Enumeration failed, so nothing could have been (correctly)
        // identified as orphaned -- the existing entry must survive rather
        // than being deleted on incomplete information.
        backend.throwOnReadAll = false;
        expect(await CredentialStore.readServerSecret('ref-1'), 'a');
      },
    );
  });
}
