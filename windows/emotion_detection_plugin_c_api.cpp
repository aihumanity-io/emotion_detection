#include "include/emotion_detection/emotion_detection_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "emotion_detection_plugin.h"

void EmotionDetectionPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  emotion_detection::EmotionDetectionPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
