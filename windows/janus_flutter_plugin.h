#ifndef FLUTTER_PLUGIN_JANUS_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_JANUS_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace janus_flutter {

class JanusFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  JanusFlutterPlugin();

  virtual ~JanusFlutterPlugin();

  // Disallow copy and assign.
  JanusFlutterPlugin(const JanusFlutterPlugin&) = delete;
  JanusFlutterPlugin& operator=(const JanusFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace janus_flutter

#endif  // FLUTTER_PLUGIN_JANUS_FLUTTER_PLUGIN_H_
