#ifndef FLUTTER_PLUGIN_EMOTION_DETECTION_PLUGIN_H_
#define FLUTTER_PLUGIN_EMOTION_DETECTION_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace emotion_detection {

class EmotionDetectionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  EmotionDetectionPlugin();

  virtual ~EmotionDetectionPlugin();

  // Disallow copy and assign.
  EmotionDetectionPlugin(const EmotionDetectionPlugin&) = delete;
  EmotionDetectionPlugin& operator=(const EmotionDetectionPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace emotion_detection

#endif  // FLUTTER_PLUGIN_EMOTION_DETECTION_PLUGIN_H_
