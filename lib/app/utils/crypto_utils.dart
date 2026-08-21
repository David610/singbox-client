// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class CryptoUtils {
  CryptoUtils._();

  static Future<String?> getFileSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  static String sha256OfString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}
