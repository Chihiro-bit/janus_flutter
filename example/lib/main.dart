import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_flutter/janus.dart';

Future<void> main() async {
  Janus.init(
    debug: ['log', 'error', 'debug'],
    callback: () {
      createJanusSession();
    },
  );
}

void createJanusSession() {
  late JanusSession session;
  late JanusPluginHandle echoHandle;
  MediaStream? localStream;

  session = JanusSession(
    server: 'wss://your-janus-server.com/ws',
    onSuccess: () {
      session.attach(
        plugin: 'janus.plugin.echotest',
        success: (handle) async {
          echoHandle = handle;

          localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': true,
          });

          await echoHandle.createPeerConnection(
            mediaStreams: [localStream!],
            onLocalCandidate: (c) => print('Local candidate: ${c.candidate}'),
            onConnectionState: (state) => print('Connection state: $state'),
            onRemoteStream: (stream) {
              print('Remote stream: ${stream.id}');
            },
          );

          final offer = await echoHandle.createOffer();
          await echoHandle.send(
            message: {'audio': true, 'video': true},
            jsep: offer,
            success: (_) => print('Offer sent'),
            error: (e) => print('Error sending offer: $e'),
          );
        },
        error: (err) => print('Attach error: $err'),
        onmessage: (msg, jsep) async {
          print('Plugin message: $msg');
          if (jsep != null) {
            await echoHandle.handleRemoteJsep(jsep);
          }
        },
      );
    },
    onError: (error) => print('Session error: $error'),
    onDestroyed: () => print('Session destroyed'),
  );
}
