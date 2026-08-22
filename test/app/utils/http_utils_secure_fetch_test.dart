// Regression tests for the cleartext-provisioning hardening in
// HttpUtils.httpGetRequestSecure: production remote subscription/profile
// fetches must require https://, must never follow a redirect that
// downgrades to http://, must cap the number of redirect hops, must cap
// the response body size, and must fail cleanly (no crash, no unbounded
// buffering) on malformed/oversized/untrusted content.
//
// httpGetRequestSecure itself always rejects a non-https:// starting URL
// before any I/O happens, so the redirect/size mechanics below are
// exercised through fetchBoundedForTesting -- a @visibleForTesting escape
// hatch onto the exact same bounded-fetch code path, but usable against a
// plain-http loopback HttpServer (no TLS needed in a unit test). The
// scheme gate itself is tested directly against httpGetRequestSecure.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/http_utils.dart';

void main() {
  group('HttpUtils.httpGetRequestSecure', () {
    test('rejects a plain http:// URL without making any request', () async {
      final result = await HttpUtils.httpGetRequestSecure(
        'http://example.com/sub',
        null,
        null,
        const Duration(seconds: 5),
        null,
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
      expect(result.error!.message, contains('https'));
    });

    test('rejects an unsupported custom scheme', () async {
      final result = await HttpUtils.httpGetRequestSecure(
        'file:///etc/passwd',
        null,
        null,
        const Duration(seconds: 5),
        null,
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
    });

    test('rejects unparsable garbage input', () async {
      final result = await HttpUtils.httpGetRequestSecure(
        'not a url at all',
        null,
        null,
        const Duration(seconds: 5),
        null,
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
    });
  });

  group(
    'HttpUtils bounded-fetch mechanics (loopback http, TLS not needed)',
    () {
      late HttpServer server;

      tearDown(() async {
        await server.close(force: true);
      });

      test('a normal 200 response is returned intact', () async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) {
          req.response
            ..statusCode = 200
            ..write('{"ok":true}');
          req.response.close();
        });
        final url = Uri.parse('http://127.0.0.1:${server.port}/sub');

        final result = await HttpUtils.fetchBoundedForTesting(url);

        expect(result.error, isNull);
        expect(result.data!.item1, 200);
        expect(result.data!.item2, '{"ok":true}');
      });

      test(
        'malformed body content is still returned, not crashed on',
        () async {
          // HttpUtils only fetches bytes; parsing/validating subscription
          // content is the caller's job (AutoConfUtils), so a bounded fetch
          // must hand back whatever bytes it got rather than throwing on
          // content that isn't valid JSON/subscription data.
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((req) {
            req.response
              ..statusCode = 200
              ..write('{not: valid json ]]]');
            req.response.close();
          });
          final url = Uri.parse('http://127.0.0.1:${server.port}/sub');

          final result = await HttpUtils.fetchBoundedForTesting(url);

          expect(result.error, isNull);
          expect(result.data!.item2, '{not: valid json ]]]');
        },
      );

      test('a same-scheme redirect chain within the cap is followed', () async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) {
          if (req.uri.path == '/start') {
            req.response.statusCode = 302;
            req.response.headers.set(
              'location',
              'http://127.0.0.1:${server.port}/final',
            );
            req.response.close();
          } else {
            req.response
              ..statusCode = 200
              ..write('final-content');
            req.response.close();
          }
        });
        final url = Uri.parse('http://127.0.0.1:${server.port}/start');

        final result = await HttpUtils.fetchBoundedForTesting(url);

        expect(result.error, isNull);
        expect(result.data!.item2, 'final-content');
      });

      test('a redirect chain exceeding the hop cap is rejected', () async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) {
          final n = int.tryParse(req.uri.pathSegments.last) ?? 0;
          req.response.statusCode = 302;
          req.response.headers.set(
            'location',
            'http://127.0.0.1:${server.port}/hop/${n + 1}',
          );
          req.response.close();
        });
        final url = Uri.parse('http://127.0.0.1:${server.port}/hop/0');

        final result = await HttpUtils.fetchBoundedForTesting(
          url,
          maxRedirects: 2,
        );

        expect(result.data, isNull);
        expect(result.error, isNotNull);
        expect(result.error!.message, contains('redirect'));
      });

      test(
        'a response exceeding the byte cap is rejected, not buffered whole',
        () async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((req) {
            req.response.statusCode = 200;
            req.response.add(List<int>.filled(4096, 0x41));
            req.response.close();
          });
          final url = Uri.parse('http://127.0.0.1:${server.port}/sub');

          final result = await HttpUtils.fetchBoundedForTesting(
            url,
            maxBytes: 1024,
          );

          expect(result.data, isNull);
          expect(result.error, isNotNull);
        },
      );

      test(
        'a non-2xx/3xx status is surfaced as an error, not thrown',
        () async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((req) {
            req.response.statusCode = 500;
            req.response.close();
          });
          final url = Uri.parse('http://127.0.0.1:${server.port}/sub');

          final result = await HttpUtils.fetchBoundedForTesting(url);

          expect(result.data, isNull);
          expect(result.error, isNotNull);
        },
      );
    },
  );

  group('HttpUtils.validateRedirectTargetForTesting (downgrade rejection)', () {
    test('rejects an https->http downgrade redirect', () {
      final current = Uri.parse('https://sub.example.com/a');
      final result = HttpUtils.validateRedirectTargetForTesting(
        current,
        'http://sub.example.com/b',
        requireHttps: true,
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
      expect(result.error!.message, contains('https'));
    });

    test('accepts an https->https redirect', () {
      final current = Uri.parse('https://sub.example.com/a');
      final result = HttpUtils.validateRedirectTargetForTesting(
        current,
        'https://sub.example.com/b',
        requireHttps: true,
      );
      expect(result.error, isNull);
      expect(result.data!.scheme, 'https');
    });

    test('rejects a redirect with a missing Location header', () {
      final current = Uri.parse('https://sub.example.com/a');
      final result = HttpUtils.validateRedirectTargetForTesting(
        current,
        null,
        requireHttps: true,
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
    });
  });
}
