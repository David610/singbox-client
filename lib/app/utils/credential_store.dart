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
//
// The second half of this file (`ProfileCredentialStore` and its
// `CredentialBackend`) is the document-level API used by SettingManager:
// it walks a whole persisted JSON document, replaces secret values with
// opaque `secure-credential:v1:` references stored in the same platform
// secure store, and atomically migrates legacy plaintext files. See
// docs/CREDENTIAL_STORAGE.md.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

  // Android: Keystore-backed storage via the plugin (the deprecated
  // `encryptedSharedPreferences` flag is intentionally not set -- the
  // plugin now manages the cipher and migrates old data itself).
  // accessibility.first_unlock -> iOS Keychain entry
  // decryptable only after the device's first unlock since boot (correct
  // trade-off for a VPN client that may need to reconnect from a
  // background/boot-triggered context, while still requiring the device to
  // have been unlocked at least once -- not `whenUnlocked`, which would
  // make credential-dependent reconnects fail while the device is locked).
  static const AndroidOptions _android = AndroidOptions();
  static const IOSOptions _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: _android,
    iOptions: _ios,
  );

  @override
  Future<void> write(String key, String value) => _storage.write(
    key: key,
    value: value,
    aOptions: _android,
    iOptions: _ios,
  );

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

  static Future<void> writeSubscriptionSecret(String ref, String urlOrToken) =>
      _backend.write('$subscriptionSecretPrefix$ref', urlOrToken);

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

/// Platform credential storage used by persisted VPN profiles.
///
/// On Android flutter_secure_storage is backed by Android Keystore and on
/// Apple platforms by Keychain. JSON files contain only opaque references.
abstract interface class CredentialBackend {
  Future<void> write(String key, String value);

  Future<String?> read(String key);

  Future<void> delete(String key);

  Future<Map<String, String>> readAll();
}

final class PlatformCredentialBackend implements CredentialBackend {
  PlatformCredentialBackend({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

class CredentialStoreException implements Exception {
  const CredentialStoreException(this.message);

  final String message;

  @override
  String toString() => 'CredentialStoreException: $message';
}

/// Splits secret values from a profile JSON document and safely migrates old
/// plaintext documents. Writes are verified before the plaintext file is
/// atomically replaced, so a failed migration leaves the old file untouched.
class ProfileCredentialStore {
  ProfileCredentialStore(this.backend, {this.namespace = 'profile'});

  static const referencePrefix = 'secure-credential:v1:';
  static const storagePrefix = 'singbox-client.profile.v1.';
  static final Map<String, Future<void>> _pendingWrites = {};

  final CredentialBackend backend;
  final String namespace;
  final Random _random = Random.secure();

  String get _storagePrefix => 'singbox-client.$namespace.v1.';

  static const _secretKeys = {
    'uuid',
    'password',
    'private_key',
    'privateKey',
    'public_key',
    'publicKey',
    'short_id',
    'shortId',
    'pbk',
    'sid',
    'token',
    'secret',
    'auth_token',
    'authToken',
    'auth_str',
    'authStr',
    'access_token',
    'refresh_token',
    'pre_shared_key',
    'subscription_token',
    'subscriptionToken',
    'obfs-password',
    'obfs_password',
    'url_or_path',
    'decrypt_password',
  };

  Future<Map<String, dynamic>> readAndMigrate(File file) async {
    final original = await file.readAsString();
    final decoded = Map<String, dynamic>.from(jsonDecode(original) as Map);
    late Map<String, dynamic> protected;
    try {
      protected = await protect(decoded);
    } catch (_) {
      // A legacy plaintext document remains usable in memory when the
      // platform store is temporarily unavailable. It is never rewritten or
      // partially scrubbed until all secure writes verify successfully.
      if (!_containsReference(decoded)) return decoded;
      rethrow;
    }
    if (jsonEncode(protected) != jsonEncode(decoded)) {
      await _atomicWrite(file, jsonEncode(protected));
    }
    return resolve(protected);
  }

  static bool _containsReference(Object? value) {
    if (value is Map) return value.values.any(_containsReference);
    if (value is List) return value.any(_containsReference);
    return value is String && value.startsWith(referencePrefix);
  }

  Future<void> write(File file, Map<String, dynamic> document) async {
    final lockKey = '$namespace:${file.absolute.path}';
    final previous = _pendingWrites[lockKey] ?? Future<void>.value();
    final operation = previous.then(
      (_) => _write(file, document),
      onError: (_) => _write(file, document),
    );
    _pendingWrites[lockKey] = operation;
    try {
      await operation;
    } finally {
      if (identical(_pendingWrites[lockKey], operation)) {
        _pendingWrites.remove(lockKey);
      }
    }
  }

  Future<void> _write(File file, Map<String, dynamic> document) async {
    final protected = await protect(document);
    await _atomicWrite(file, jsonEncode(protected));
    await _deleteUnreferenced(protected);
  }

  Future<Map<String, dynamic>> protect(Map<String, dynamic> document) async {
    final copied = jsonDecode(jsonEncode(document));
    final result = await _protectValue(copied, null);
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> resolve(Map<String, dynamic> document) async {
    final result = await _resolveValue(jsonDecode(jsonEncode(document)));
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Object?> _protectValue(Object? value, String? key) async {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final childKey = entry.key.toString();
        out[childKey] = await _protectValue(entry.value, childKey);
      }
      return out;
    }
    if (value is List) {
      final out = <dynamic>[];
      for (var i = 0; i < value.length; i++) {
        out.add(await _protectValue(value[i], key));
      }
      return out;
    }
    if (value is String && value.isNotEmpty && _isSecretKey(key)) {
      if (value.startsWith(referencePrefix)) return value;
      // A fresh opaque identifier is essential for transactional rotation:
      // overwriting a path-derived key before the JSON commit could make the
      // old file resolve to a new credential if the file write then failed.
      final id = _randomId();
      final storageKey = '$_storagePrefix$id';
      await backend.write(storageKey, _encodeSecret(value));
      if (_decodeSecret(await backend.read(storageKey)) != value) {
        throw const CredentialStoreException(
          'secure-store verification failed',
        );
      }
      return '$referencePrefix$id';
    }
    return value;
  }

  String _randomId() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static bool _isSecretKey(String? key) {
    if (key == null) return false;
    final normalized = key.toLowerCase().replaceAll('-', '_');
    return _secretKeys.contains(key) ||
        normalized.contains('password') ||
        normalized.contains('token') ||
        normalized == 'private_key' ||
        normalized == 'pre_shared_key';
  }

  Future<Object?> _resolveValue(Object? value) async {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        out[entry.key.toString()] = await _resolveValue(entry.value);
      }
      return out;
    }
    if (value is List) {
      final out = <dynamic>[];
      for (final item in value) {
        out.add(await _resolveValue(item));
      }
      return out;
    }
    if (value is String && value.startsWith(referencePrefix)) {
      final id = value.substring(referencePrefix.length);
      final secret = _decodeSecret(await backend.read('$_storagePrefix$id'));
      return secret;
    }
    return value;
  }

  Future<void> _deleteUnreferenced(Map<String, dynamic> protected) async {
    final referenced = <String>{};

    void collect(Object? value) {
      if (value is Map) value.values.forEach(collect);
      if (value is List) value.forEach(collect);
      if (value is String && value.startsWith(referencePrefix)) {
        referenced.add(
          '$_storagePrefix${value.substring(referencePrefix.length)}',
        );
      }
    }

    collect(protected);
    final all = await backend.readAll();
    for (final key in all.keys.where((key) => key.startsWith(_storagePrefix))) {
      if (!referenced.contains(key)) await backend.delete(key);
    }
  }

  Future<void> _atomicWrite(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.credentials.${_randomId()}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static String _encodeSecret(String value) => jsonEncode({
    'value': value,
    'sha256': sha256.convert(utf8.encode(value)).toString(),
  });

  static String _decodeSecret(String? stored) {
    if (stored == null || stored.isEmpty) {
      throw const CredentialStoreException(
        'profile credential is missing or unreadable',
      );
    }
    try {
      final envelope = Map<String, dynamic>.from(jsonDecode(stored) as Map);
      final value = envelope['value'];
      final checksum = envelope['sha256'];
      if (value is! String ||
          value.isEmpty ||
          checksum != sha256.convert(utf8.encode(value)).toString()) {
        throw const CredentialStoreException(
          'profile credential is missing or unreadable',
        );
      }
      return value;
    } on CredentialStoreException {
      rethrow;
    } catch (_) {
      throw const CredentialStoreException(
        'profile credential is missing or unreadable',
      );
    }
  }
}
