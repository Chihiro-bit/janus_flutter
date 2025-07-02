
import 'package:janus_flutter/janus.dart';

void main() {
  // 1. Initialize the Janus library
  Janus.init(
    debug: ["log", "error"],
    callback: () {
      // Initialization is complete, now we can create a session.
      createJanusSession();
    },
  );
}

void createJanusSession() {
  late JanusSession janus;
  late JanusPluginHandle videoRoomHandle;

  // 2. Create a new Janus session
  janus = JanusSession(
    server: 'wss://your-janus-server.com/ws', // Replace with your Janus server URL
    onSuccess: () {
      print("Janus session created successfully!");

      // 3. Attach to the VideoRoom plugin
      janus.attach(
        plugin: "janus.plugin.videoroom",
        success: (handle) {
          videoRoomHandle = handle;
          print("Attached to VideoRoom plugin! Handle ID: ${videoRoomHandle.getId()}");

          // 4. Join a room
          // This is a plugin-specific message.
          final joinMessage = {
            "request": "join",
            "room": 1234, // Example room number
            "ptype": "publisher",
            "display": "Dart User"
          };

          videoRoomHandle.send(
              message: joinMessage,
              success: (data) {
                print("Join request sent successfully.");
              },
              error: (error) {
                print("Error sending join request: $error");
              }
          );
        },
        error: (error) {
          print("Failed to attach to VideoRoom plugin: $error");
        },
        onmessage: (msg, jsep) {
          // 5. Handle asynchronous events from the plugin
          print("Got a message from the plugin:");
          print(msg);

          final event = msg['videoroom'];
          if (event == 'joined') {
            print("Successfully joined room ${msg['room']}!");
            // At this point, you would typically create an offer to start publishing.
            // videoRoomHandle.createOffer(...);
          } else if (event == 'event') {
            // Handle other events, like new publishers joining the room.
            if (msg['publishers'] != null) {
              print("New publishers in the room: ${msg['publishers']}");
              // For each publisher, you would create a new subscriber handle
              // and send a "join" request with ptype: "subscriber".
            }
          }

          if (jsep != null) {
            print("Got a JSEP offer/answer:");
            print(jsep.toMap());
            // Handle the JSEP, e.g., by creating an answer.
            // videoRoomHandle.createAnswer(jsep: jsep, ...);
          }
        },
        oncleanup: () {
          print("Plugin handle cleaned up.");
        },
      );
    },
    onError: (error) {
      print("Failed to create Janus session: $error");
    },
    onDestroyed: () {
      print("Janus session destroyed.");
    },
  );
}