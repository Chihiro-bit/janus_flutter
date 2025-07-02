#include "include/janus_flutter/janus_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "janus_flutter_plugin.h"

void JanusFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  janus_flutter::JanusFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
