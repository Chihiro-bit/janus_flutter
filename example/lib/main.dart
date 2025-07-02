import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_flutter/janus.dart';

void main() {
  runApp(const JanusWebRtcExample());
}

class JanusWebRtcExample extends StatefulWidget {
  const JanusWebRtcExample({super.key});

  @override
  State<JanusWebRtcExample> createState() => _JanusWebRtcExampleState();
}

class _JanusWebRtcExampleState extends State<JanusWebRtcExample> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  JanusSession? _session;
  JanusPluginHandle? _handle;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _initJanus();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _initJanus() async {
    await Janus.init(debug: ['log', 'error']);
    _session = JanusSession(
      server: 'wss://your-janus-server/ws',
      onSuccess: _attach,
      onError: (e) => debugPrint('Session error: $e'),
    );
  }

  Future<void> _attach() async {
    await _session!.attach(
      plugin: 'janus.plugin.echotest',
      success: (handle) async {
        _handle = handle;
        await _startWebRtc();
      },
      onmessage: (msg, jsep) async {
        if (jsep != null && _handle != null) {
          await _handle!.handleRemoteJsep(jsep);
        }
      },
      oncleanup: () => debugPrint('Handle cleaned up'),
    );
  }

  Future<void> _startWebRtc() async {
    final localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
    _localRenderer.srcObject = localStream;

    await _handle!.initPeerConnection(
      configuration: {'iceServers': []},
      stream: localStream,
      onRemoteStream: (stream) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      },
    );

    final offer = await _handle!.createOffer();
    await _handle!.send(message: {'audio': true, 'video': true}, jsep: offer);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Janus WebRTC Example')),
        body: Column(
          children: [
            Expanded(child: RTCVideoView(_localRenderer)),
            Expanded(child: RTCVideoView(_remoteRenderer)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _session?.destroy();
    super.dispose();
  }
}
