import 'package:janus_flutter/janus.dart';

/// Simple example showing how to connect to a Janus Gateway using this library.
void main() {
  Janus.init(callback: () async {
    final session = JanusSession(
      server: 'wss://your-janus-server.com/websocket',
      onSuccess: () {
        print('Janus session established: ${session.getSessionId()}');

        session.attach(
          plugin: 'janus.plugin.echotest',
          success: (handle) {
            print('Plugin attached with handle: ${handle.getId()}');
            handle.send(
              message: {'echo': 'Hello from Dart'},
              success: (_) => print('Message sent'),
              error: (e) => print('Failed to send message: $e'),
            );
          },
          error: (e) => print('Attach failed: $e'),
          onmessage: (msg, jsep) {
            print('Received message: $msg');
            if (jsep != null) {
              print('Received JSEP: ${jsep.toMap()}');
            }
          },
        );
      },
      onError: (e) => print('Session error: $e'),
      onDestroyed: () => print('Session destroyed'),
    );
  });
}
