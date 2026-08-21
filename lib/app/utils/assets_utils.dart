// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:flutter/services.dart';

class AssetsUtils {
  AssetsUtils._();

  static Future<String> loadUserAgreement(bool isChinese) async {
    final asset = isChinese
        ? 'assets/txts/user_agreement_cn.txt'
        : 'assets/txts/user_agreement_en.txt';
    try {
      return await rootBundle.loadString(asset);
    } catch (_) {
      return '';
    }
  }
}
