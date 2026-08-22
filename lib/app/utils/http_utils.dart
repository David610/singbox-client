// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/app_utils.dart';
import 'package:meta/meta.dart';
import 'package:tuple/tuple.dart';

class HttpUtils {
  HttpUtils._();

  static const List<String> _defaultUserAgentCompatibles = <String>[
    'karing',
    'clash',
    'clash.meta',
    'sing-box',
    'v2ray',
    'shadowrocket',
  ];

  static Dio _client(int? proxyPort, Duration timeout) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        followRedirects: true,
        validateStatus: (_) => true,
      ),
    );
    if (proxyPort != null && proxyPort > 0) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
        client.badCertificateCallback = (cert, host, port) => false;
        return client;
      };
    }
    return dio;
  }

  static Future<String> getUserAgent({String? compatible}) async {
    final version = AppUtils.getBuildinVersion();
    if (compatible != null && compatible.isNotEmpty) {
      return '$compatible ${AppUtils.getName()}/$version';
    }
    return '${AppUtils.getName()}/$version';
  }

  static String getUserAgentAppend() => AppUtils.getName();

  static List<String> getUserAgents() => _defaultUserAgentCompatibles;

  static List<String> getUserAgentsByUa(
    List<String> selected,
    bool onlySelected,
  ) {
    if (!onlySelected) {
      return _defaultUserAgentCompatibles;
    }
    return _defaultUserAgentCompatibles
        .where((e) => selected.contains(e))
        .toList();
  }

  static String getUserAgentsByUaString(List<String> compatibles) {
    return compatibles.join(';');
  }

  static String getUserAgentsByUaStringShort(List<String> compatibles) {
    if (compatibles.isEmpty) {
      return '';
    }
    if (compatibles.length == 1) {
      return compatibles.first;
    }
    return '${compatibles.first} +${compatibles.length - 1}';
  }

  /// Bounded, HTTPS-only GET intended for fetching remote subscription /
  /// profile content from a user-supplied URL. Unlike [httpGetRequest]
  /// this:
  ///  - rejects any URL that isn't `https://` up front (no cleartext
  ///    "subscription" provisioning, and no other custom schemes);
  ///  - never follows a redirect off of https (an https-\>http downgrade
  ///    redirect is rejected, not silently followed);
  ///  - caps the number of redirect hops (default 5);
  ///  - caps the response body size (default 5 MiB), aborting the
  ///    transfer as soon as the cap is exceeded rather than buffering an
  ///    unbounded response into memory first.
  static const int kMaxRemoteContentBytes = 5 * 1024 * 1024;
  static const int kMaxRemoteContentRedirects = 5;

  static Future<ReturnResult<Tuple2<int, String>>> httpGetRequestSecure(
    String url,
    int? proxyPort,
    String? userAgent,
    Duration timeout,
    Map<String, String>? headers, {
    int maxRedirects = kMaxRemoteContentRedirects,
    int maxBytes = kMaxRemoteContentBytes,
  }) async {
    Uri? current = Uri.tryParse(url);
    if (current == null || !current.hasScheme) {
      return ReturnResult(
        error: ReturnResultError('invalid URL: $url', report: false),
      );
    }
    if (current.scheme.toLowerCase() != 'https') {
      return ReturnResult(
        error: ReturnResultError(
          'only https:// URLs are supported for remote subscription/profile fetch',
          report: false,
        ),
      );
    }
    return _fetchBounded(
      current,
      proxyPort,
      userAgent,
      timeout,
      headers,
      maxRedirects: maxRedirects,
      maxBytes: maxBytes,
      requireHttps: true,
    );
  }

  /// Test-only escape hatch onto the same bounded-redirect/bounded-size
  /// fetch mechanics [httpGetRequestSecure] uses, but against a plain
  /// `http://` URL (e.g. a `dart:io` `HttpServer` bound to loopback in a
  /// test) so the redirect-cap/size-cap/status-handling logic can be
  /// exercised without standing up TLS. Production code must always go
  /// through [httpGetRequestSecure], which enforces https:// first --
  /// this bypasses only that outer scheme gate, not the mechanics.
  @visibleForTesting
  static Future<ReturnResult<Tuple2<int, String>>> fetchBoundedForTesting(
    Uri url, {
    int maxRedirects = kMaxRemoteContentRedirects,
    int maxBytes = kMaxRemoteContentBytes,
  }) {
    return _fetchBounded(
      url,
      null,
      null,
      const Duration(seconds: 5),
      null,
      maxRedirects: maxRedirects,
      maxBytes: maxBytes,
      requireHttps: false,
    );
  }

  /// Test-only: the same downgrade-safe redirect-target validation used
  /// inside [_fetchBounded], exposed directly so the https-\>http
  /// downgrade rejection can be unit tested without any I/O at all.
  @visibleForTesting
  static ReturnResult<Uri> validateRedirectTargetForTesting(
    Uri current,
    String? location, {
    bool requireHttps = true,
  }) => _validateRedirectTarget(current, location, requireHttps);

  static ReturnResult<Uri> _validateRedirectTarget(
    Uri current,
    String? location,
    bool requireHttps,
  ) {
    if (location == null || location.isEmpty) {
      return ReturnResult(
        error: ReturnResultError(
          'redirect with no Location header',
          report: false,
        ),
      );
    }
    Uri? next = Uri.tryParse(location);
    if (next == null) {
      return ReturnResult(
        error: ReturnResultError(
          'invalid redirect location: $location',
          report: false,
        ),
      );
    }
    if (!next.hasScheme) {
      next = current.resolveUri(next);
    }
    if (requireHttps && next.scheme.toLowerCase() != 'https') {
      return ReturnResult(
        error: ReturnResultError(
          'refusing to follow redirect to non-https URL',
          report: false,
        ),
      );
    }
    return ReturnResult(data: next);
  }

  static Future<ReturnResult<Tuple2<int, String>>> _fetchBounded(
    Uri url,
    int? proxyPort,
    String? userAgent,
    Duration timeout,
    Map<String, String>? headers, {
    required int maxRedirects,
    required int maxBytes,
    required bool requireHttps,
  }) async {
    Uri current = url;
    final dio = _client(proxyPort, timeout);
    try {
      dio.options.followRedirects = false;
      dio.options.maxRedirects = 0;
      for (int hop = 0; hop <= maxRedirects; hop++) {
        final cancelToken = CancelToken();
        final response = await dio.getUri<List<int>>(
          current,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'User-Agent': ?userAgent, ...?headers},
            validateStatus: (_) => true,
          ),
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (received > maxBytes) {
              cancelToken.cancel('response exceeds max allowed size');
            }
          },
        );
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 300 && statusCode < 400) {
          final target = _validateRedirectTarget(
            current,
            response.headers.value('location'),
            requireHttps,
          );
          if (target.error != null) {
            return ReturnResult(error: target.error);
          }
          current = target.data!;
          continue;
        }
        if (statusCode < 200 || statusCode >= 300) {
          return ReturnResult(
            error: ReturnResultError('HTTP $statusCode', report: false),
          );
        }
        final data = response.data ?? const <int>[];
        if (data.length > maxBytes) {
          return ReturnResult(
            error: ReturnResultError(
              'response exceeds max allowed size',
              report: false,
            ),
          );
        }
        return ReturnResult(
          data: Tuple2(statusCode, String.fromCharCodes(data)),
        );
      }
      return ReturnResult(
        error: ReturnResultError('too many redirects', report: false),
      );
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    } finally {
      dio.close(force: true);
    }
  }

  static Future<ReturnResult<Tuple2<int, String>>> httpGetRequest(
    String url,
    int? proxyPort,
    String? userAgent,
    Duration timeout,
    Map<String, String>? headers,
    String? xhwid, {
    bool checkStatuscode = true,
    bool noResponseBody = false,
  }) async {
    try {
      final dio = _client(proxyPort, timeout);
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'User-Agent': ?userAgent, 'X-HWID': ?xhwid, ...?headers},
        ),
      );
      final statusCode = response.statusCode ?? 0;
      if (checkStatuscode && (statusCode < 200 || statusCode >= 300)) {
        return ReturnResult(
          error: ReturnResultError('HTTP $statusCode', report: false),
        );
      }
      final body = noResponseBody
          ? ''
          : String.fromCharCodes(response.data ?? const []);
      return ReturnResult(data: Tuple2(statusCode, body));
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<ReturnResult<Tuple2<int, HttpHeaders>>> httpHeadRequest(
    Uri url,
    int? proxyPort,
    String userAgent,
    String? xhwid,
    Duration timeout,
  ) async {
    try {
      final dio = _client(proxyPort, timeout);
      final response = await dio.headUri<void>(
        url,
        options: Options(headers: {'User-Agent': userAgent, 'X-HWID': ?xhwid}),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return ReturnResult(
          error: ReturnResultError('HTTP $statusCode', report: false),
        );
      }
      return ReturnResult(
        data: Tuple2(statusCode, _DioHttpHeaders(response.headers)),
      );
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<ReturnResult<Tuple2<int, String>>> httpPostRequest(
    String url,
    int? proxyPort,
    Map<String, String>? headers,
    dynamic body,
    Duration timeout,
    String? userAgent,
    String? xhwid,
    String? extra, {
    bool checkStatuscode = true,
  }) async {
    try {
      final dio = _client(proxyPort, timeout);
      final response = await dio.post<List<int>>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'User-Agent': ?userAgent, 'X-HWID': ?xhwid, ...?headers},
        ),
      );
      final statusCode = response.statusCode ?? 0;
      if (checkStatuscode && (statusCode < 200 || statusCode >= 300)) {
        return ReturnResult(
          error: ReturnResultError('HTTP $statusCode', report: false),
        );
      }
      final responseBody = String.fromCharCodes(response.data ?? const []);
      return ReturnResult(data: Tuple2(statusCode, responseBody));
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<ReturnResult<HttpHeaders>> httpDownload(
    Uri url,
    String savePath,
    int? proxyPort,
    String? userAgent,
    bool overwrite,
    Duration? timeout,
  ) async {
    try {
      if (!overwrite && await File(savePath).exists()) {
        return ReturnResult(
          error: ReturnResultError(
            'file already exists: $savePath',
            report: false,
          ),
        );
      }
      final dio = _client(proxyPort, timeout ?? const Duration(seconds: 30));
      final response = await dio.downloadUri(
        url,
        savePath,
        options: Options(headers: {'User-Agent': ?userAgent}),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return ReturnResult(
          error: ReturnResultError('HTTP $statusCode', report: false),
        );
      }
      return ReturnResult(data: _DioHttpHeaders(response.headers));
    } catch (err) {
      return ReturnResult(
        error: ReturnResultError(err.toString(), report: false),
      );
    }
  }

  static Future<ReturnResultError?> httpUpload(
    Uri url,
    String filePath,
    int? proxyPort,
    String? userAgent,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ReturnResultError('file not found: $filePath', report: false);
      }
      final dio = _client(proxyPort, const Duration(seconds: 30));
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      final response = await dio.postUri<void>(
        url,
        data: formData,
        options: Options(headers: {'User-Agent': ?userAgent}),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return ReturnResultError('HTTP $statusCode', report: false);
      }
      return null;
    } catch (err) {
      return ReturnResultError(err.toString(), report: false);
    }
  }

  static Future<ReturnResult<String>> httpGetTitle(
    String url,
    String userAgent,
  ) async {
    final result = await httpGetRequest(
      url,
      null,
      userAgent,
      const Duration(seconds: 10),
      null,
      null,
      checkStatuscode: false,
    );
    if (result.error != null || result.data == null) {
      return ReturnResult(error: result.error);
    }
    final match = RegExp(
      r'<title[^>]*>([^<]*)</title>',
      caseSensitive: false,
    ).firstMatch(result.data!.item2);
    return ReturnResult(data: match?.group(1)?.trim() ?? '');
  }
}

class _DioHttpHeaders implements HttpHeaders {
  _DioHttpHeaders(this._headers);
  final Headers _headers;

  @override
  String? value(String name) => _headers.value(name);

  @override
  List<String>? operator [](String name) => _headers[name];

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
