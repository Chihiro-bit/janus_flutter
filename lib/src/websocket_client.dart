import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Simple wrapper around [WebSocketChannel] that exposes callbacks for incoming
/// data, errors and connection close events.
class JanusWebSocketClient {
  JanusWebSocketClient({
    required this.url,
    this.onData,
    this.onError,
    this.onDone,
  });

  final String url;
  final void Function(dynamic data)? onData;
  final void Function(Object error)? onError;
  final void Function()? onDone;

  WebSocketChannel? _channel;

  Future<void> connect() async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen(onData, onError: onError, onDone: onDone);
  }

  bool get isConnected => _channel != null;

  void send(dynamic data) {
    _channel?.sink.add(data);
  }

  Future<void> close() async {
    await _channel?.sink.close();
  }
}
