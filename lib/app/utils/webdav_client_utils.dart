// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:io';

import 'package:dio/io.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:webdav_client_plus/webdav_client_plus.dart';

class WebdavClientUtils {
  WebdavClientUtils._();

  static Future<ReturnResult<WebdavClient>> connect(
    int? proxyPort,
    String url,
    String user,
    String password,
  ) async {
    try {
      final client = WebdavClient.basicAuth(
        url: url,
        user: user,
        pwd: password,
      );
      if (proxyPort != null && proxyPort > 0) {
        client.setHttpClientAdapter(
          IOHttpClientAdapter(
            createHttpClient: () {
              final httpClient = HttpClient();
              httpClient.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
              return httpClient;
            },
          ),
        );
      }
      await client.readDir('/');
      return ReturnResult(data: client);
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static bool isInnerError(String message) {
    return message.contains('SocketException') ||
        message.contains('Connection refused') ||
        message.contains('Connection closed');
  }

  static Future<ReturnResult<List<WebdavFile>>> list(
    WebdavClient client,
  ) async {
    try {
      final files = await client.readDir('/');
      return ReturnResult(data: files);
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<ReturnResultError?> upload(
    WebdavClient client, {
    required String relativePath,
    required String localPath,
  }) async {
    try {
      await client.writeFile(localPath, relativePath);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }

  static Future<ReturnResultError?> download(
    WebdavClient client, {
    required String relativePath,
    required String localPath,
  }) async {
    try {
      await client.readFile(relativePath, localPath);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }

  static Future<ReturnResultError?> delete(
    WebdavClient client,
    String relativePath,
  ) async {
    try {
      await client.remove(relativePath);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }
}
