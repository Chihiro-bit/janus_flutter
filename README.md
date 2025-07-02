# janus_flutter

A Flutter plugin providing a client for the [Janus WebRTC Server](https://janus.conf.meetecho.com/).
It allows establishing WebRTC sessions and exchanging media streams directly from
Flutter applications.

## Getting Started

The plugin exposes the Janus session API and now includes helpers to manage
`RTCPeerConnection` instances. It takes care of handling ICE candidates,
SDP offer/answer negotiation and basic WebRTC events.

See `example/lib/main.dart` for a full example that connects to the Janus
`echotest` plugin and streams audio/video using `flutter_webrtc`.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

