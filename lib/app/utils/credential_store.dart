// Platform-backed secure storage for VPN credential material (VLESS UUIDs,
// Hysteria2 passwords, REALITY key material, remote subscription URLs/
// tokens) -- see docs/CLIENT_PRODUCTION_BASELINE.md and the P0
// credential-storage work item this file implements.
//
// Design constraints (do not violate these when editing this file):
//  - No custom cryptography. This is a thin wrapper over
//    `flutter_secure_storage`, which is Android-Keystore-backed
//    (EncryptedSharedPreferences, itself AES-GCM via Keystore-held keys) and
//    iOS-Keychain-backed. We never touch key material ourselves.
//  - No encryption key is ever stored next to the ciphertext by this code --
//    `flutter_secure_storage` on Android holds its AES key in the Android
//    Keystore (not in the EncryptedSharedPreferences file it protects) and
//    on iOS the Keychain itself is the secure store, so there is no
//    separate "key file" for this wrapper to mismanage.
//  - `_Backend` exists purely so tests can inject an in-memory fake instead
//    of touching a real platform channel (`flutter_secure_storage` has no
//    method-channel mock in a plain `flutter test` run). Production code
//    always uses `_SecureBackend`, which is the only backend that talks to
//    Keystore/Keychain.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value contract [CredentialStore] needs. Kept intentionally
/// narrow (read/write/delete/readAll) so a test fake can implement it in a
/// few lines without pulling in the real plugin's platform channel.
abstract class SecureKeyValueBackend {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

class _SecureBackend implements SecureKeyValueBackend {
  const _SecureBackend();

  // encryptedSharedPreferences: true -> Android Keystore-backed
  // EncryptedSharedPreferences (AES-GCM, key held in Keystore, never on
  // disk in the clear). accessibility.first_unlock -> iOS Keychain entry
  // decryptable only after the device's first unlock since boot (correct
  // trade-off for a VPN client that may need to reconnect from a
  // background/boot-triggered context, while still requiring the device to
  // have been unlocked at least once -- not `whenUnlocked`, which would
  // make credential-dependent reconnects fail while the device is locked).
  static const AndroidOptions _android = AndroidOptions(
    encryptedSharedPreferences: true,
  );
  static const IOSOptions _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: _android,
    iOptions: _ios,
  );

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value, aOptions: _android, iOptions: _ios);

  @override
  Future<String?> read(String key) =>
      _storage.read(key: key, aOptions: _android, iOptions: _ios);

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: key, aOptions: _android, iOptions: _ios);

  @override
  Future<Map<String, String>> readAll() =>
      _storage.readAll(aOptions: _android, iOptions: _ios);
}

/// Secure, platform-backed storage for credential-bearing values that used
/// to live inline in plaintext JSON (`subscribe.json`'s per-server `raw`
/// sing-box outbound, and a group's remote subscription URL/token in
/// `url_or_path`).
///
/// Every value is namespaced by a caller-chosen prefix (`server_secret_`,
/// `subscription_secret_`) so [pruneExcept] can safely garbage-collect only
/// the keys it owns without touching anything else that might end up in the
/// same secure-storage keychain/keystore in the future.
class CredentialStore {
  CredentialStore._();

  static const String serverSecretPrefix = 'vpn_server_secret_v1_';
  static const String subscriptionSecretPrefix = 'vpn_subscription_secret_v1_';

  static SecureKeyValueBackend _backend = const _SecureBackend();

  /// Test-only hook: swap in an in-memory fake so unit tests can exercise
  /// migration/read/write/corruption logic without a real Keystore/Keychain
  /// (unavailable under `flutter test`). Never call this from app code.
  static void debugOverrideBackend(SecureKeyValueBackend backend) {
    _backend = backend;
  }

  static void debugResetBackend() {
    _backend = const _SecureBackend();
  }

  static Future<void> writeServerSecret(String ref, String jsonPayload) =>
      _backend.write('$serverSecretPrefix$ref', jsonPayload);

  static Future<String?> readServerSecret(String ref) =>
      _backend.read('$serverSecretPrefix$ref');

  static Future<void> deleteServerSecret(String ref) =>
      _backend.delete('$serverSecretPrefix$ref');

  static Future<void> writeSubscriptionSecret(
    String ref,
    String urlOrToken,
  ) => _backend.write('$subscriptionSecretPrefix$ref', urlOrToken);

  static Future<String?> readSubscriptionSecret(String ref) =>
      _backend.read('$subscriptionSecretPrefix$ref');

  static Future<void> deleteSubscriptionSecret(String ref) =>
      _backend.delete('$subscriptionSecretPrefix$ref');

  /// Writes [value] under [prefix]+[ref] and reads it back to confirm the
  /// platform store actually persisted it before the caller treats the
  /// secret as safely migrated. Returns true only when write+verify both
  /// succeeded and the read-back value matches exactly. Never throws --
  /// callers must fail safe (keep the plaintext copy) on a false return
  /// rather than assume success.
  static Future<bool> writeAndVerify(
    String prefix,
    String ref,
    String value,
  ) async {
    try {
      final key = '$prefix$ref';
      await _backend.write(key, value);
      final verify = await _backend.read(key);
      return verify == value;
    } catch (_) {
      return false;
    }
  }

  /// Deletes every stored key under [prefix] whose ref is not in
  /// [activeRefs]. Best-effort: a failure to enumerate or delete never
  /// throws, since orphaned-secret cleanup must never block a save of the
  /// (already-correct) live configuration.
  static Future<void> pruneExcept(String prefix, Set<String> activeRefs) async {
    try {
      final all = await _backend.readAll();
      for (final key in all.keys) {
        if (!key.startsWith(prefix)) continue;
        final ref = key.substring(prefix.length);
        if (!activeRefs.contains(ref)) {
          try {
            await _backend.delete(key);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
