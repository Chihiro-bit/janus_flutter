# janus_flutter_example

This example demonstrates how to connect to a Janus WebRTC server and run the
`janus.plugin.echotest` plugin. Two video windows will appear showing the local
and remote streams.

## Getting Started

### Running the example

1. Install Flutter on your machine.
2. From the repository root run `flutter pub get` inside the `example` folder.
3. Start the example with `flutter run`.

The example uses the public Janus demo server at
`wss://janus.conf.meetecho.com/ws`. You can change the server URL in
`example/lib/main.dart` if you are running your own Janus instance.
