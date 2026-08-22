import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
