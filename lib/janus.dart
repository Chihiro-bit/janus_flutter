import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'log/janus_log.dart';



// --- Data Classes ---
class Jsep {
  final String type;
  final String sdp;
  final bool? e2ee;

  Jsep({required this.type, required this.sdp, this.e2ee});

  factory Jsep.fromMap(Map<String, dynamic> map) {
    return Jsep(
      type: map['type'] as String,
      sdp: map['sdp'] as String,
      e2ee: map['e2ee'] as bool?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'sdp': sdp,
      if (e2ee != null) 'e2ee': e2ee,
    };
  }
}

class JanusError {
  final int code;
  final String reason;

  JanusError({required this.code, required this.reason});

  factory JanusError.fromMap(Map<String, dynamic> map) {
    return JanusError(
      code: map['code'] as int,
      reason: map['reason'] as String,
    );
  }

  @override
  String toString() => 'JanusError(code: $code, reason: $reason)';
}

// --- Callback Typedefs ---
typedef SuccessCallback<T> = void Function(T result);
typedef ErrorCallback = void Function(dynamic error);
typedef VoidCallback = void Function();

// Session callbacks
typedef SessionSuccessCallback = void Function();
typedef SessionDestroyedCallback = void Function();

// Plugin callbacks
typedef PluginSuccessCallback = void Function(JanusPluginHandle handle);
typedef OnMessageCallback = void Function(dynamic msg, Jsep? jsep);
typedef ConsentDialogCallback = void Function(bool on);
typedef IceStateCallback = void Function(String state);
typedef MediaStateCallback = void Function(String type, bool receiving, String? mid);
typedef WebRTCStateCallback = void Function(bool on, String? reason);
typedef SlowLinkCallback = void Function(bool uplink, int lost, String? mid);
typedef OnCleanupCallback = void Function();
typedef OnDetachedCallback = void Function();
typedef OnLocalStreamCallback = void Function(MediaStream stream);
typedef OnRemoteStreamCallback = void Function(MediaStream stream);
typedef OnIceCandidateCallback = void Function(RTCIceCandidate candidate);
typedef PeerConnectionStateCallback = void Function(RTCPeerConnectionState state);

// --- Main Janus Class ---
class Janus {
  static bool _initDone = false;
  static final Map<int, JanusSession> sessions = {};

  /// Initialize the Janus library
  static Future<void> init({
    List<String> debug = const [],
    VoidCallback? callback,
  }) async {
    if (_initDone) {
      callback?.call();
      return;
    }

    JanusLogger.init(debug: debug);
    JanusLogger.log('Initializing Janus library');

    _initDone = true;
    callback?.call();
  }

  /// Check if library is initialized
  static bool get initDone => _initDone;

  /// Check if WebRTC is supported (placeholder - would need platform-specific implementation)
  static bool isWebrtcSupported() => true;

  /// Generate random string for transactions
  static String randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }
}

// --- Janus Session ---
class JanusSession {
  final String server;
  final SessionSuccessCallback? onSuccess;
  final ErrorCallback? onError;
  final SessionDestroyedCallback? onDestroyed;
  final String? token;
  final String? apisecret;
  final bool destroyOnUnload;

  int? _sessionId;
  bool _connected = false;
  WebSocket? _webSocket;
  final Map<String, Completer<Map<String, dynamic>>> _transactions = {};
  final Map<int, JanusPluginHandle> _pluginHandles = {};
  Timer? _keepAliveTimer;

  JanusSession({
    required this.server,
    this.onSuccess,
    this.onError,
    this.onDestroyed,
    this.token,
    this.apisecret,
    this.destroyOnUnload = true,
  }) {
    if (!Janus.initDone) {
      onError?.call('Library not initialized');
      return;
    }
    _createSession();
  }

  // --- Public API ---
  String getServer() => server;
  bool isConnected() => _connected;
  int? getSessionId() => _sessionId;

  /// Reconnect to the server
  Future<void> reconnect({
    SessionSuccessCallback? success,
    ErrorCallback? error,
  }) async {
    try {
      await _createSession();
      success?.call();
    } catch (e) {
      error?.call(e);
    }
  }

  /// Get server information
  Future<void> getInfo({
    SuccessCallback<Map<String, dynamic>>? success,
    ErrorCallback? error,
  }) async {
    if (!_connected) {
      error?.call('Not connected to server');
      return;
    }

    try {
      final transaction = Janus.randomString(12);
      final request = {
        'janus': 'info',
        'transaction': transaction,
      };

      if (token != null) request['token'] = token!;
      if (apisecret != null) request['apisecret'] = apisecret!;

      final response = await _sendMessage(request, transaction);
      success?.call(response);
    } catch (e) {
      error?.call(e);
    }
  }

  /// Destroy the session
  Future<void> destroy({
    SessionSuccessCallback? success,
    ErrorCallback? error,
    bool unload = false,
  }) async {
    JanusLogger.log('Destroying session $_sessionId (unload=$unload)');

    if (_sessionId == null) {
      JanusLogger.warn('No session to destroy');
      success?.call();
      onDestroyed?.call();
      return;
    }

    // Clean up plugin handles
    for (final handle in _pluginHandles.values) {
      await handle._cleanup();
    }
    _pluginHandles.clear();

    if (!_connected) {
      JanusLogger.warn('Not connected to server');
      _sessionId = null;
      success?.call();
      onDestroyed?.call();
      return;
    }

    try {
      final transaction = Janus.randomString(12);
      final request = {
        'janus': 'destroy',
        'transaction': transaction,
      };

      if (token != null) request['token'] = token!;
      if (apisecret != null) request['apisecret'] = apisecret!;

      if (unload) {
        // Just close the connection for unload
        await _webSocket?.close();
      } else {
        await _sendMessage(request, transaction);
      }

      _cleanup();
      success?.call();
      onDestroyed?.call();
    } catch (e) {
      _cleanup();
      error?.call(e);
      onDestroyed?.call();
    }
  }

  /// Attach to a plugin
  Future<void> attach({
    required String plugin,
    String? opaqueId,
    PluginSuccessCallback? success,
    ErrorCallback? error,
    OnMessageCallback? onmessage,
    ConsentDialogCallback? consentDialog,
    IceStateCallback? iceState,
    MediaStateCallback? mediaState,
    WebRTCStateCallback? webrtcState,
    SlowLinkCallback? slowLink,
    OnCleanupCallback? oncleanup,
    OnDetachedCallback? ondetached,
  }) async {
    if (!_connected) {
      error?.call('Not connected to server');
      return;
    }

    try {
      final transaction = Janus.randomString(12);
      final request = {
        'janus': 'attach',
        'plugin': plugin,
        'transaction': transaction,
      };

      if (opaqueId != null) request['opaque_id'] = opaqueId;
      if (token != null) request['token'] = token!;
      if (apisecret != null) request['apisecret'] = apisecret!;

      final response = await _sendMessage(request, transaction);

      if (response['janus'] != 'success') {
        final errorInfo = JanusError.fromMap(response['error']);
        error?.call(errorInfo);
        return;
      }

      final handleId = response['data']['id'] as int;
      JanusLogger.log('Created handle: $handleId');

      final pluginHandle = JanusPluginHandle(
        session: this,
        plugin: plugin,
        id: handleId,
        onmessage: onmessage,
        consentDialog: consentDialog,
        iceState: iceState,
        mediaState: mediaState,
        webrtcState: webrtcState,
        slowLink: slowLink,
        oncleanup: oncleanup,
        ondetached: ondetached,
      );

      _pluginHandles[handleId] = pluginHandle;
      success?.call(pluginHandle);
    } catch (e) {
      error?.call(e);
    }
  }

  // --- Private Methods ---
  Future<void> _createSession() async {
    try {
      JanusLogger.log('Creating session to $server');

      if (server.startsWith('ws')) {
        await _connectWebSocket();
      } else {
        throw UnsupportedError('HTTP transport not implemented in this example');
      }
    } catch (e) {
      JanusLogger.error('Failed to create session: $e');
      onError?.call(e);
    }
  }

  Future<void> _connectWebSocket() async {
    try {
      _webSocket = await WebSocket.connect(server, protocols: ['janus-protocol']);

      _webSocket!.listen(
        _handleWebSocketMessage,
        onError: (error) {
          JanusLogger.error('WebSocket error: $error');
          onError?.call(error);
        },
        onDone: () {
          JanusLogger.log('WebSocket connection closed');
          _connected = false;
          onError?.call('Connection lost');
        },
      );

      // Create session
      final transaction = Janus.randomString(12);
      final request = {
        'janus': 'create',
        'transaction': transaction,
      };

      if (token != null) request['token'] = token!;
      if (apisecret != null) request['apisecret'] = apisecret!;

      final response = await _sendMessage(request, transaction);

      if (response['janus'] != 'success') {
        final errorInfo = JanusError.fromMap(response['error']);
        throw Exception(errorInfo.toString());
      }

      _sessionId = response['session_id'] ?? response['data']['id'];
      _connected = true;

      JanusLogger.log('Created session: $_sessionId');
      Janus.sessions[_sessionId!] = this;

      _startKeepAlive();
      onSuccess?.call();
    } catch (e) {
      JanusLogger.error('WebSocket connection failed: $e');
      throw e;
    }
  }

  void _handleWebSocketMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      JanusLogger.debug('Received: $json');

      final transaction = json['transaction'] as String?;
      if (transaction != null && _transactions.containsKey(transaction)) {
        final completer = _transactions.remove(transaction)!;
        completer.complete(json);
        return;
      }

      _handleEvent(json);
    } catch (e) {
      JanusLogger.error('Error handling WebSocket message: $e');
    }
  }

  void _handleEvent(Map<String, dynamic> json) {
    final janus = json['janus'] as String?;

    switch (janus) {
      case 'keepalive':
        JanusLogger.debug('Got keepalive');
        break;
      case 'ack':
        JanusLogger.debug('Got ack');
        break;
      case 'event':
        _handlePluginEvent(json);
        break;
      case 'webrtcup':
        _handleWebRTCUp(json);
        break;
      case 'hangup':
        _handleHangup(json);
        break;
      case 'detached':
        _handleDetached(json);
        break;
      case 'media':
        _handleMedia(json);
        break;
      case 'slowlink':
        _handleSlowLink(json);
        break;
      case 'trickle':
        _handleTrickle(json);
        break;
      case 'error':
        JanusLogger.error('Server error: ${json['error']}');
        break;
      default:
        JanusLogger.warn('Unknown event type: $janus');
    }
  }

  void _handlePluginEvent(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    if (pluginHandle == null) return;

    final plugindata = json['plugindata'] as Map<String, dynamic>?;
    final data = plugindata?['data'];
    final jsep = json['jsep'] != null ? Jsep.fromMap(json['jsep']) : null;

    pluginHandle.onmessage?.call(data, jsep);
  }

  void _handleWebRTCUp(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    pluginHandle?.webrtcState?.call(true, null);
  }

  void _handleHangup(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    final reason = json['reason'] as String?;
    pluginHandle?.webrtcState?.call(false, reason);
  }

  void _handleDetached(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    if (pluginHandle != null) {
      pluginHandle.ondetached?.call();
      _pluginHandles.remove(sender);
    }
  }

  void _handleMedia(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    final type = json['type'] as String?;
    final receiving = json['receiving'] as bool?;
    final mid = json['mid'] as String?;

    if (type != null && receiving != null) {
      pluginHandle?.mediaState?.call(type, receiving, mid);
    }
  }

  void _handleSlowLink(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    final uplink = json['uplink'] as bool?;
    final lost = json['lost'] as int?;
    final mid = json['mid'] as String?;

    if (uplink != null && lost != null) {
      pluginHandle?.slowLink?.call(uplink, lost, mid);
    }
  }

  void _handleTrickle(Map<String, dynamic> json) {
    final sender = json['sender'] as int?;
    if (sender == null) return;

    final pluginHandle = _pluginHandles[sender];
    final candidate = json['candidate'] as Map<String, dynamic>?;
    pluginHandle?._handleRemoteCandidate(candidate);
  }

  Future<Map<String, dynamic>> _sendMessage(Map<String, dynamic> message, String transaction) async {
    if (_webSocket == null) {
      throw Exception('WebSocket not connected');
    }

    final completer = Completer<Map<String, dynamic>>();
    _transactions[transaction] = completer;

    if (_sessionId != null) {
      message['session_id'] = _sessionId;
    }

    final jsonString = jsonEncode(message);
    JanusLogger.debug('Sending: $jsonString');
    _webSocket!.add(jsonString);

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _transactions.remove(transaction);
        throw TimeoutException('Request timeout', const Duration(seconds: 10));
      },
    );
  }

  void _startKeepAlive() {
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (!_connected || _webSocket == null) {
        timer.cancel();
        return;
      }

      final request = {
        'janus': 'keepalive',
        'session_id': _sessionId,
        'transaction': Janus.randomString(12),
      };

      if (token != null) request['token'] = token!;
      if (apisecret != null) request['apisecret'] = apisecret!;

      _webSocket!.add(jsonEncode(request));
    });
  }

  void _cleanup() {
    _keepAliveTimer?.cancel();
    _webSocket?.close();
    _connected = false;
    _sessionId = null;
    _transactions.clear();

    if (_sessionId != null) {
      Janus.sessions.remove(_sessionId);
    }
  }
}

// --- Janus Plugin Handle ---
class JanusPluginHandle {
  final JanusSession session;
  final String plugin;
  final int id;
  final OnMessageCallback? onmessage;
  final ConsentDialogCallback? consentDialog;
  final IceStateCallback? iceState;
  final MediaStateCallback? mediaState;
  final WebRTCStateCallback? webrtcState;
  final SlowLinkCallback? slowLink;
  final OnCleanupCallback? oncleanup;
  final OnDetachedCallback? ondetached;
  final OnLocalStreamCallback? onLocalStream;
  final OnRemoteStreamCallback? onRemoteStream;
  final OnIceCandidateCallback? onLocalCandidate;
  final PeerConnectionStateCallback? onPeerConnectionState;

  bool _detached = false;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _remoteCandidates = [];
  bool _remoteDescriptionSet = false;

  JanusPluginHandle({
    required this.session,
    required this.plugin,
    required this.id,
    this.onmessage,
    this.consentDialog,
    this.iceState,
    this.mediaState,
    this.webrtcState,
    this.slowLink,
    this.oncleanup,
    this.ondetached,
    this.onLocalStream,
    this.onRemoteStream,
    this.onLocalCandidate,
    this.onPeerConnectionState,
  });

  // --- Public API ---
  int getId() => id;
  String getPlugin() => plugin;
  bool isDetached() => _detached;

  Future<void> initPeerConnection({
    required Map<String, dynamic> configuration,
    MediaStream? stream,
  }) async {
    _peerConnection = await createPeerConnection(configuration);
    _localStream = stream;
    if (stream != null) {
      onLocalStream?.call(stream);
      for (final track in stream.getTracks()) {
        await _peerConnection!.addTrack(track, stream);
      }
    }

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate == null) {
        trickleComplete();
        return;
      }
      onLocalCandidate?.call(candidate);
      _trickleCandidate(candidate);
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      onPeerConnectionState?.call(state);
    };
  }

  Future<Jsep> createOffer([Map<String, dynamic> constraints = const {}]) async {
    final description = await _peerConnection!.createOffer(constraints);
    await _peerConnection!.setLocalDescription(description);
    return Jsep(type: description.type, sdp: description.sdp!);
  }

  Future<Jsep> createAnswer([Map<String, dynamic> constraints = const {}]) async {
    final description = await _peerConnection!.createAnswer(constraints);
    await _peerConnection!.setLocalDescription(description);
    return Jsep(type: description.type, sdp: description.sdp!);
  }

  Future<void> handleRemoteJsep(Jsep jsep) async {
    final desc = RTCSessionDescription(jsep.sdp, jsep.type);
    await _peerConnection!.setRemoteDescription(desc);
    _remoteDescriptionSet = true;
    for (final cand in _remoteCandidates) {
      await _peerConnection!.addCandidate(cand);
    }
    _remoteCandidates.clear();
  }

  Future<void> trickleComplete() async {
    final request = {
      'janus': 'trickle',
      'candidate': {'completed': true},
      'session_id': session.getSessionId(),
      'handle_id': id,
      'transaction': Janus.randomString(12),
    };

    await session._sendMessage(request, request['transaction'] as String);
  }

  Future<void> _trickleCandidate(RTCIceCandidate candidate) async {
    final request = {
      'janus': 'trickle',
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMlineIndex,
      },
      'session_id': session.getSessionId(),
      'handle_id': id,
      'transaction': Janus.randomString(12),
    };

    await session._sendMessage(request, request['transaction'] as String);
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic>? cand) async {
    if (cand == null) return;
    if (cand['completed'] == true) {
      return;
    }
    final candidate = RTCIceCandidate(
      cand['candidate'] as String?,
      cand['sdpMid'] as String?,
      cand['sdpMLineIndex'] as int?,
    );
    if (_remoteDescriptionSet) {
      await _peerConnection?.addCandidate(candidate);
    } else {
      _remoteCandidates.add(candidate);
    }
  }

  /// Send a message to the plugin
  Future<void> send({
    required Map<String, dynamic> message,
    Jsep? jsep,
    SuccessCallback<dynamic>? success,
    ErrorCallback? error,
  }) async {
    if (_detached) {
      error?.call('Handle is detached');
      return;
    }

    try {
      final transaction = Janus.randomString(12);
      final request = {
        'janus': 'message',
        'body': message,
        'transaction': transaction,
        'session_id': session.getSessionId(),
        'handle_id': id,
      };

      if (jsep != null) {
        request['jsep'] = jsep.toMap();
      }

      if (session.token != null) request['token'] = session.token!;
      if (session.apisecret != null) request['apisecret'] = session.apisecret!;

      final response = await session._sendMessage(request, transaction);

      if (response['janus'] == 'success') {
        final plugindata = response['plugindata'];
        final data = plugindata?['data'];
        success?.call(data);
      } else if (response['janus'] == 'ack') {
        success?.call(null);
      } else {
        final errorInfo = JanusError.fromMap(response['error']);
        error?.call(errorInfo);
      }
    } catch (e) {
      error?.call(e);
    }
  }

  /// Detach from the plugin
  Future<void> detach({
    SessionSuccessCallback? success,
    ErrorCallback? error,
  }) async {
    if (_detached) {
      success?.call();
      return;
    }

    try {
      final transaction = Janus.randomString(12);
      final request = {
        'janus': 'detach',
        'transaction': transaction,
        'session_id': session.getSessionId(),
        'handle_id': id,
      };

      if (session.token != null) request['token'] = session.token!;
      if (session.apisecret != null) request['apisecret'] = session.apisecret!;

      await session._sendMessage(request, transaction);
      await _cleanup();
      success?.call();
    } catch (e) {
      await _cleanup();
      error?.call(e);
    }
  }

  Future<void> _cleanup() async {
    _detached = true;
    await _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    session._pluginHandles.remove(id);
    oncleanup?.call();
  }
}
