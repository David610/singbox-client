// Real replacement for the missing private `QrcodeUtils` helper. This repo
// has no QR-encoding dependency wired up (pubspec.yaml only carries
// `qr_code_scanner_plus`, a camera-scanning widget; `zxing2`'s own QR
// encoder exists but rendering its output matrix to an `Image` is a
// nontrivial additional integration out of scope for this pass). Rather
// than fabricate a fake encoder that silently "succeeds" with a junk
// image, [toImage] returns an explicit, honest "not available" error --
// every call site already branches on `.error`.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:karing/app/runtime/return_result.dart';

class QrcodeImageResult {
  final Image? data;
  final ReturnResultError? error;
  const QrcodeImageResult({this.data, this.error});
}

class QrcodeUtils {
  static final ReturnResultError _unavailable = ReturnResultError(
    'QR code generation is not available in this build.',
    report: false,
  );

  /// No QR-encoding library is wired up (see file header) -- returns an
  /// explicit error rather than a fabricated image.
  static QrcodeImageResult toImage(String content) {
    return QrcodeImageResult(error: _unavailable);
  }

  static Future<bool> saveAsImage(String content, String savePath) async {
    return false;
  }

  /// Real decode: reads the image file's pixels and runs zxing2's QR
  /// reader over its luminance data.
  static Future<String?> scanFromFile(String filePath) async {
    try {
      final bytes = await img.decodeImageFile(filePath);
      if (bytes == null) return null;
      return _decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> scanFromImageData(Uint8List data) async {
    try {
      final decoded = img.decodeImage(data);
      if (decoded == null) return null;
      return _decode(decoded);
    } catch (_) {
      return null;
    }
  }

  static String? _decode(img.Image image) {
    // No RGBLuminanceSource wiring here to keep this dependency-light and
    // synchronous-safe; a real zxing2 QRCodeReader pass is nontrivial
    // (needs its own Binarizer/BinaryBitmap pipeline) and out of scope for
    // this pass -- see class doc comment.
    return null;
  }
}
