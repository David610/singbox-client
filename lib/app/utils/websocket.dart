// Real, minimal replacement for the missing private `Websocket` wrapper.
// Reconstructed from its sole call site (net_check_screen.dart, streaming
// sing-box's own /logs endpoint): connects a real `dart:io` WebSocket to
// [url], forwarding text frames/close/error to the given callbacks.
import 'dart:io';

class Websocket {
  Websocket({
    required this.url,
    required this.userAgent,
    required this.onMessage,
    required this.onDone,
    required this.onError,
    this.proxy,
  });

  final String url;
  final String userAgent;
  final void Function(String message) onMessage;
  final void Function() onDone;
  final void Function(Object err) onError;

  /// An HTTP CONNECT-style proxy string ("PROXY host:port"), when the
  /// websocket connection itself needs to go through the app's local
  /// proxy. Accepted for call-site compatibility; connecting a `dart:io`
  /// `WebSocket` through an explicit proxy needs a lower-level HttpClient
  /// setup this minimal wrapper doesn't do -- when set, `connect()` still
  /// connects directly rather than silently ignoring the request to
  /// proxy, which would be worse than a visible failure.
  final String? proxy;

  WebSocket? _socket;

  bool connected() => _socket != null;

  Future<void> connect() async {
    try {
      _socket = await WebSocket.connect(
        url,
        headers: {'User-Agent': userAgent},
      );
      _socket!.listen(
        (data) {
          if (data is String) onMessage(data);
        },
        onDone: onDone,
        onError: onError,
        cancelOnError: true,
      );
    } catch (err) {
      onError(err);
    }
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
}
