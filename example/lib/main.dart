import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_flutter/janus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Janus.init(debug: ['log', 'error', 'debug']);
  runApp(const JanusExampleApp());
}

class JanusExampleApp extends StatefulWidget {
  const JanusExampleApp({super.key});

  @override
  State<JanusExampleApp> createState() => _JanusExampleAppState();
}

class _JanusExampleAppState extends State<JanusExampleApp> {
  JanusSession? _session;
  JanusPluginHandle? _echoHandle;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    super.dispose();
  }

  Future<void> _startEchoTest() async {
    setState(() => _connecting = true);

    _session = JanusSession(
      server: 'wss://janus.conf.meetecho.com/ws',
      onSuccess: () {
        _session!.attach(
          plugin: 'janus.plugin.echotest',
          success: (handle) async {
            _echoHandle = handle;

            _localStream = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': true,
            });
            _localRenderer.srcObject = _localStream;

            await _echoHandle!.initPeerConnection(
              mediaStreams: [_localStream!],
              onRemoteStream: (stream) {
                setState(() {
                  _remoteStream = stream;
                  _remoteRenderer.srcObject = _remoteStream;
                });
              },
            );

            final offer = await _echoHandle!.createOffer();
            await _echoHandle!.send(
              message: {'audio': true, 'video': true},
              jsep: offer,
            );

            setState(() {});
          },
          error: (err) {
            debugPrint('Attach error: $err');
            setState(() => _connecting = false);
          },
          onmessage: (msg, jsep) async {
            if (jsep != null) {
              await _echoHandle!.handleRemoteJsep(jsep);
            }
          },
        );
      },
      onError: (error) {
        debugPrint('Session error: $error');
        setState(() => _connecting = false);
      },
      onDestroyed: () {
        setState(() {
          _connecting = false;
          _session = null;
          _echoHandle = null;
          _localRenderer.srcObject = null;
          _remoteRenderer.srcObject = null;
          _localStream?.dispose();
          _localStream = null;
          _remoteStream = null;
        });
      },
    );
  }

  Future<void> _stop() async {
    await _echoHandle?.closePeerConnection();
    await _session?.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Janus Echo Test')),
        body: Column(
          children: [
            Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
            Expanded(child: RTCVideoView(_remoteRenderer)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: _connecting
                  ? ElevatedButton(onPressed: _stop, child: const Text('Stop'))
                  : ElevatedButton(
                      onPressed: _startEchoTest,
                      child: const Text('Start Echo Test'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
